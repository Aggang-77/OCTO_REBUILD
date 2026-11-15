extends "res://scripts/octopus/rebuild_demo.gd"
## Native muscle controls/skin plus explicit Godot terrain/contact coupling.
signal bridge_failed(message: String)
signal native_reset
const ANCHOR = preload("res://scripts/octopus/contact_anchor.gd")
var arena: TidalArena
var hunter: HunterTarget
var spawn := Vector3.ZERO # World origin at the map floor; native center starts at localY0.27.
var anchors: Array[Node3D] = []
var threats: Array[HunterThreat] = []
var capture_threat: HunterThreat
var grips: Dictionary = {}
var forces: Dictionary = {}
var collider_bodies: Dictionary = {}
var next_collider_id: int = 1
var scene_suffix: String = " 0 0"
var suspended: bool = false
var resetting: bool = false
var release_cooldown: float = 0.0
var contact_shape := SphereShape3D.new()
var fault: String = ""
var snapshot_age: float = 0.0
var terrain_reset: String = ""
# Main-thread scene export is cached as immutable text for the pipe worker.
var mesh_setup: Array[String] = []
var mesh_setup_index: int = 0
var mesh_setup_active: bool = false
var static_triangle_count: int = 0
var geometry_ready: bool = false
var setup_started_usec: int = 0
var mesh_upload_started_usec: int = 0
var grip_candidates: Dictionary = {}
var arm_commands: Array[Dictionary] = []
var hero_target_body: RigidBody3D
var hero_target_local := Vector3.ZERO

func _ready() -> void:
	setup_started_usec = Time.get_ticks_usec()
	animals = 1
	creature_scale = 1.5
	resetting = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -30
	terrain_reset = _build_reset_command()
	mesh_setup = _build_mesh_setup()
	for arm in range(8):
		var anchor := ANCHOR.new()
		anchor.name = "ArmContact%d" % arm
		anchor.controller = self
		anchor.arm = arm
		add_child(anchor)
		anchors.append(anchor)
		var threat := HunterThreat.new()
		threat.threat_id = StringName("octopus_arm_%d" % arm)
		threat.health = 100.0
		threat.radius = 0.12 * creature_scale
		threat.cut_radius = 0.10 * creature_scale
		threat.physics_anchor = anchor
		threat.restraint_strength = 3.2
		anchor.add_child(threat)
		threat.severed.connect(func(_attacker: Node3D): _disable_arm(arm))
		threat.escape_impulse.connect(func(power: float, target: Node3D):
			add_site_force(arm, anchor.site, (anchor.global_position - target.global_position).normalized() * power * 4.0))
		threats.append(threat)
	# A stable aggregate source represents the octopus's actual surviving grips.
	# Switching which tentacle holds the hunter does not interrupt a continuous hold.
	capture_threat = HunterThreat.new()
	capture_threat.threat_id = &"octopus_capture"
	capture_threat.is_tentacle = false
	capture_threat.severable = false
	capture_threat.restraint_strength = 3.2
	capture_threat.escape_impulse.connect(func(power: float, target: Node3D):
		for arm in grips:
			add_site_force(arm, anchors[arm].site,
				(anchors[arm].global_position - target.global_position).normalized() * power * 4.0))
	add_child(capture_threat)
	var server := ProjectSettings.globalize_path("res://native/octo/octo_game_server.exe")
	if not FileAccess.file_exists(server):
		fail("문어 엔진이 없습니다. tools/build_octopus.ps1을 실행하세요.")
		return
	OS.set_environment("OCTO_SERVER", server)
	super._ready()

func make_stage() -> void:
	make_target_marker() # Arena, camera and HUD are supplied by the game.

func _build_reset_command() -> String:
	var command := "game_reset5 %.5f %.5f %.5f %.5f 65 -28 -28 0.875" % [spawn.x, spawn.y, spawn.z, creature_scale]
	for z in range(65):
		for x in range(65):
			command += " %.4f" % arena.terrain_height(-28.0 + x * 0.875, -28.0 + z * 0.875)
	return command

func _build_mesh_setup() -> Array[String]:
	var started := Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	for body: StaticBody3D in arena.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer == 0:
			continue
		for collision: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
			if collision.disabled or collision.shape == null:
				continue
			# A nested dynamic body is never part of this static map upload.
			var owner_body: Node = collision.get_parent()
			while owner_body != null and not owner_body is CollisionObject3D:
				owner_body = owner_body.get_parent()
			if owner_body != body:
				continue
			var faces := PackedVector3Array()
			if collision.shape is ConcavePolygonShape3D:
				faces = collision.shape.get_faces()
			elif collision.shape is BoxShape3D:
				faces = _box_faces(collision.shape.size)
			for point: Vector3 in faces:
				vertices.append(collision.global_transform * point)
	static_triangle_count = vertices.size() / 3
	var commands: Array[String] = ["mesh_begin %d" % vertices.size()]
	# Multiples of three preserve triangle boundaries and stay below the
	# Windows pipe buffer without any worker-side scene/resource access.
	for offset in range(0, vertices.size(), 600):
		var count := mini(600, vertices.size() - offset)
		var values := PackedStringArray()
		values.resize(1 + count * 3)
		values[0] = "mesh_chunk %d %d" % [offset, count]
		for index in range(count):
			var point: Vector3 = vertices[offset + index]
			var component := 1 + index * 3
			values[component] = String.num(point.x, 6)
			values[component + 1] = String.num(point.y, 6)
			values[component + 2] = String.num(point.z, 6)
		commands.append(" ".join(values))
	commands.append("mesh_commit")
	print("STATIC_MESH_EXPORT triangles=%d chunks=%d elapsed_ms=%.2f" % [static_triangle_count,
		commands.size() - 2, float(Time.get_ticks_usec() - started) / 1000.0])
	return commands

func _box_faces(size: Vector3) -> PackedVector3Array:
	var half := size * 0.5
	var corners := PackedVector3Array()
	for index in range(8):
		corners.append(Vector3(half.x if index & 1 else -half.x,
			half.y if index & 2 else -half.y, half.z if index & 4 else -half.z))
	var faces := PackedVector3Array()
	for index in [0, 2, 3, 0, 3, 1, 4, 5, 7, 4, 7, 6,
		0, 4, 6, 0, 6, 2, 1, 3, 7, 1, 7, 5,
		0, 1, 5, 0, 5, 4, 2, 6, 7, 2, 7, 3]:
		faces.append(corners[index])
	return faces

func reset_command() -> String:
	# Called on the pipe worker too: no scene/resource access on that thread.
	return terrain_reset

func request_reset() -> void:
	setup_started_usec = Time.get_ticks_usec()
	release_grips()
	forces.clear()
	_clear_target()
	scene_suffix = " 0 0"
	dragging = false
	resetting = true
	geometry_ready = false
	grip_candidates.clear()
	arm_commands.clear()
	for controls in arm_controllers:
		controls.reset()
	for threat in threats:
		threat.reset_threat()
	inbox_lock.lock()
	reset_requested = true
	inbox_lock.unlock()

func add_site_force(arm: int, site: int, force: Vector3) -> void:
	var key := Vector2i(arm, site)
	forces[key] = (forces.get(key, Vector3.ZERO) + force).limit_length(700.0)

func _actual_actor_grip(arm: int) -> bool:
	return grips.has(arm) and hunter.physics_rig.grips.has(grips[arm].id)

func _arm_locked(animal: int, arm: int) -> bool:
	return (animal == 0 and _actual_actor_grip(arm)) or super._arm_locked(animal, arm)

func _source_arm_command(arm: int) -> Dictionary:
	while arm_controllers.size() < animals:
		arm_controllers.append(ARM_CONTROLS.new())
	var manual := threats[arm].active and Input.is_physical_key_pressed(ARM_KEYS[arm])
	var any_arm := false
	for key in ARM_KEYS:
		any_arm = any_arm or Input.is_physical_key_pressed(key)
	var locked := _arm_locked(0, arm)
	var release_grab := Input.is_physical_key_pressed(KEY_CTRL) and (manual or (not any_arm and not Input.is_physical_key_pressed(KEY_SHIFT)))
	var grab_target := manual and not locked and Input.is_physical_key_pressed(KEY_SHIFT) and not release_grab and target_kind != 0
	var held := not locked and manual and not release_grab
	var suction_on := Input.is_physical_key_pressed(KEY_SPACE)
	var attached := _actual_actor_grip(arm)
	if not current.is_empty():
		for contact in current.animals[0].arms[arm].get("attached", []):
			attached = attached or bool(contact)
	var cmd: Dictionary = arm_controllers[0].sample(arm, float(current.get("time", 0.0)), held,
		false, false, false, attached and suction_on, 1.0, suction_on)
	if grab_target:
		cmd.activation = 0.90
		cmd.extension = 1.42
		cmd.curvature = 0.0
		cmd.sweep = 0.0
	if arm_controllers[0].phases[arm] == "rest":
		cmd.extension = 1.04
		cmd.curvature = 0.0
		cmd.sweep = 0.0
	cmd["twist"] = (float(Input.is_physical_key_pressed(KEY_PERIOD)) - float(Input.is_physical_key_pressed(KEY_COMMA))) * 3.0 if manual and not locked and not release_grab else 0.0
	cmd["grab_mode"] = 2 if release_grab else (1 if grab_target else 0)
	return cmd

func step_command() -> String:
	update_target_marker()
	var out := "step6 8"
	arm_commands.clear()
	for arm in range(8):
		var cmd := _source_arm_command(arm)
		arm_commands.append(cmd)
		out += " 0 %d %f %f %f %f 0.02 %d %f" % [arm, cmd.activation,
			cmd.curvature, cmd.extension, cmd.twist, cmd.grab_mode, cmd.sweep]
	out += " %d 0 %d %f %f %f %f %f %d" % [drag_kind if dragging else 0,
		drag_index, drag_target.x, drag_target.y, drag_target.z, drag_stiffness, drag_max_force * creature_scale,
		int(Input.is_physical_key_pressed(KEY_SPACE))]
	out += " %d %d %f %f %f" % [target_kind, maxi(target_index, 0), target_hit.x, target_hit.y, target_hit.z]
	for arm in range(8):
		out += " %d" % int(_actual_actor_grip(arm))
	return out + scene_suffix

func _clear_target() -> void:
	target_kind = 0
	target_index = -1
	hero_target_body = null
	if target_marker != null:
		target_marker.hide()

func select_mouse_target(screen_point: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_point) * 200.0, 1 | 4 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is RigidBody3D or hit.collider.get_meta("hunter_target", null) != hunter:
		_clear_target()
		return
	hero_target_body = hit.collider
	target_kind = 3
	target_index = hunter.physics_rig.part_order.find(hero_target_body.get_meta("hunter_part"))
	hero_target_local = hero_target_body.to_local(hit.position)
	target_hit = hit.position
	target_previous_center = hero_target_body.global_position
	update_target_marker()

func target_center() -> Vector3:
	return hero_target_body.global_position if target_kind == 3 and is_instance_valid(hero_target_body) else super.target_center()

func update_target_marker() -> void:
	if target_kind == 3:
		if not is_instance_valid(hero_target_body):
			_clear_target()
			return
		target_hit = hero_target_body.to_global(hero_target_local)
		if target_marker != null:
			target_marker.show()
			target_marker.global_position = hero_target_body.global_position + Vector3.UP * 0.40
	else:
		super.update_target_marker()

func _apply_ctrl_release() -> void:
	if not Input.is_physical_key_pressed(KEY_CTRL):
		return
	var any_arm := false
	for key in ARM_KEYS:
		any_arm = any_arm or Input.is_physical_key_pressed(key)
	# Reserve Ctrl+Shift without an arm for the hidden integration chord.
	if not any_arm and Input.is_physical_key_pressed(KEY_SHIFT):
		return
	for arm in grips.keys():
		if not any_arm or Input.is_physical_key_pressed(ARM_KEYS[arm]):
			_drop_grip(arm)

func _grab_radius(arm: int, site: int) -> float:
	var radii: Array = current.animals[0].arms[arm].get("grab_radii", [])
	return float(radii[site]) if site < radii.size() else 0.0

func _drive_hero_grab(arm: int) -> void:
	if target_kind != 3 or not is_instance_valid(hero_target_body) or int(_source_arm_command(arm).grab_mode) != 1:
		return
	var nodes: Array = current.animals[0].arms[arm].nodes
	var site := nodes.size() - 4
	var center := vec(nodes[site])
	var delta := target_hit - center
	var distance := delta.length()
	var gap := maxf(0.0, distance - _grab_radius(arm, site)) / creature_scale
	if distance > 0.00000001:
		var force := delta / distance * minf(52.0, 90.0 * gap) * creature_scale
		add_site_force(arm, site, force)
		for cage_node in range(7):
			add_site_force(-1, cage_node, -force / 7.0)
	var shape := SphereShape3D.new()
	shape.radius = _grab_radius(arm, site) + 0.035 * creature_scale
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = center
	query.collision_mask = 4
	var hit := get_world_3d().direct_space_state.get_rest_info(query)
	if not hit.is_empty() and instance_from_id(hit.collider_id) == hero_target_body:
		_try_grip(arm, site, hero_target_body, hit.point)

func _wrap_hero_grip(arm: int) -> void:
	if not _actual_actor_grip(arm):
		return
	var body: RigidBody3D = hunter.physics_rig.get_part_body(grips[arm].part)
	var nodes: Array = current.animals[0].arms[arm].nodes
	var site: int = anchors[arm].site
	var outward := (vec(nodes[site]) - body.global_position).normalized()
	var tangent := vec(nodes[site]) - vec(nodes[maxi(0, site - 2)])
	tangent -= outward * tangent.dot(outward)
	if tangent.length_squared() < 0.00000001:
		tangent = outward.cross(Vector3.UP)
	if tangent.length_squared() < 0.00000001:
		tangent = outward.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	for index in range(site + 1, nodes.size()):
		var u := float(index - site) / float(nodes.size() - 1 - site)
		var wanted: Vector3 = body.global_position + (outward * cos(1.7 * u) + tangent * sin(1.7 * u)) * float(grips[arm].radius)
		var force := ((wanted - vec(nodes[index])) * 12.0).limit_length(7.0 * creature_scale)
		add_site_force(arm, index, force)
		body.apply_central_force(-force)

func send(command: String) -> void:
	# The main thread only publishes commands; the worker owns every live write.
	inbox_lock.lock()
	if command == terrain_reset:
		reset_requested = true
	else:
		latest_command = command
	inbox_lock.unlock()

func read_pipe() -> void:
	# A single worker owns all post-reset writes. Main-thread sending while the
	# worker waits for its next 60 Hz slot can enqueue two large Windows pipe
	# requests and deadlock against the server's response. Keep one in flight.
	var pending_bytes := PackedByteArray()
	while not stop_reader:
		if child.has("pid") and not OS.is_process_running(child.pid):
			break
		var available := pipe.get_length()
		if available > 0:
			pending_bytes.append_array(pipe.get_buffer(mini(available, 1048576)))
			if pending_bytes.size() > 4194304:
				inbox_lock.lock()
				inbox.append("OVERSIZE")
				inbox_lock.unlock()
				break
			var newline := pending_bytes.find(10)
			while newline >= 0:
				var line := pending_bytes.slice(0, newline).get_string_from_utf8()
				pending_bytes = pending_bytes.slice(newline + 1)
				inbox_lock.lock()
				inbox.append(line)
				inbox_times.append(float(Time.get_ticks_usec() - sent_at) / 1000.0)
				pending = false
				inbox_lock.unlock()
				newline = pending_bytes.find(10)
		var wire := ""
		inbox_lock.lock()
		if not pending and not stop_reader:
			var command := ""
			var setup := false
			if reset_requested:
				command = terrain_reset
				reset_requested = false
				mesh_setup_index = 0
				mesh_setup_active = true
				setup = true
			elif mesh_setup_active:
				if mesh_setup_index == 0:
					mesh_upload_started_usec = Time.get_ticks_usec()
				command = mesh_setup[mesh_setup_index]
				mesh_setup_index += 1
				mesh_setup_active = mesh_setup_index < mesh_setup.size()
				setup = true
			elif auto_step and Time.get_ticks_usec() >= next_due_usec:
				command = latest_command
			if not command.is_empty():
				request_id += 1
				pending = true
				sent_at = Time.get_ticks_usec()
				next_due_usec = sent_at + 16667 if setup else maxi(next_due_usec + 16667, sent_at)
				wire = "1 %d %s\n" % [request_id, command]
		inbox_lock.unlock()
		if not wire.is_empty():
			pipe.store_string(wire)
			pipe.flush()
		# A millisecond sleep can round to a Windows15ms scheduler slot.
		# Drain the finite setup queue promptly; normal gameplay stays paced.
		if mesh_setup_active or not pending_bytes.is_empty() or available > 0:
			OS.delay_usec(100)
		else:
			OS.delay_msec(1)

func poll() -> void:
	if pipe == null or quitting:
		return
	while true:
		inbox_lock.lock()
		var line: String = inbox.pop_front() if not inbox.is_empty() else ""
		if not inbox_times.is_empty():
			rpc_ms = inbox_times.pop_front()
		inbox_lock.unlock()
		if line.is_empty():
			break
		var parsed = JSON.parse_string(line)
		if not parsed is Dictionary or int(parsed.get("id", -1)) != last_response_id + 1 or int(parsed.get("version", 0)) != 1:
			fail("문어 엔진의 응답이 올바르지 않습니다.")
			return
		last_response_id += 1
		last_progress_usec = Time.get_ticks_usec()
		if not parsed.get("ok", false):
			fail("문어 엔진: " + str(parsed.get("error", "unknown")))
			return
		if parsed.get("mesh_upload", false):
			continue
		var frame: Dictionary = parsed.snapshot.frame
		current = frame.world
		current["body_nodes"] = frame.body_nodes
		current["reactions"] = frame.reactions
		geometry_ready = bool(frame.get("geometry_ready", false))
		current["geometry_ready"] = geometry_ready
		if int(current.tick) == 0:
			get_window().title = "OCTO / " + str(current.get("source_commit", "unknown")).substr(0, 7) + " / 갯벌 추격전"
		snapshot_age = 0.0
		update_scene()
		if int(current.tick) == 0 and geometry_ready and resetting:
			print("STATIC_MESH_READY triangles=%d elapsed_ms=%.2f upload_ms=%.2f" % [int(current.static_triangles), float(Time.get_ticks_usec() - setup_started_usec) / 1000.0, float(Time.get_ticks_usec() - mesh_upload_started_usec) / 1000.0])
			resetting = false
			native_reset.emit()
		# Reactions belong to this one response, never to a rendered-frame cache.
		if not resetting and not suspended and not get_tree().paused:
			for reaction in frame.reactions:
				var body = collider_bodies.get(int(reaction.collider))
				if is_instance_valid(body) and body is RigidBody3D:
					body.apply_impulse(vec(reaction.impulse), vec(reaction.point) - body.global_position)
	if child.has("pid") and not OS.is_process_running(child.pid):
		fail("문어 물리 엔진이 종료되었습니다.")
	elif auto_step and last_progress_usec > 0 and Time.get_ticks_usec() - last_progress_usec > 15000000:
		fail("문어 물리 엔진이 응답하지 않습니다.")
	elif resetting and pending and Time.get_ticks_usec() - sent_at > 15000000:
		fail("문어 물리 엔진 시작 시간이 초과되었습니다.")

func update_scene() -> void:
	super.update_scene()
	capture_threat.global_position = vec(current.animals[0].center)
	for arm in range(8):
		anchors[arm].global_position = vec(current.animals[0].arms[arm].nodes[anchors[arm].site])

func _process(delta: float) -> void:
	if quitting:
		return
	poll()
	if current.is_empty() or quitting:
		return
	snapshot_age += delta if not suspended and not get_tree().paused else 0.0
	inbox_lock.lock()
	auto_step = geometry_ready and not resetting and not suspended and not get_tree().paused
	latest_command = step_command() if auto_step else ""
	inbox_lock.unlock()

func _physics_process(delta: float) -> void:
	if quitting or get_tree().paused or suspended or current.is_empty() or resetting:
		return
	release_cooldown = maxf(0.0, release_cooldown - delta)
	_apply_ctrl_release()
	_validate_grips()
	update_target_marker()
	for arm in range(8):
		_drive_hero_grab(arm)
		_wrap_hero_grip(arm)
	var contacts: Array[String] = []
	var world := get_world_3d().direct_space_state
	for arm in range(-1, 8):
		var nodes: Array = current.body_nodes if arm < 0 else current.animals[0].arms[arm].nodes
		for site in range(nodes.size()):
			var radius := _contact_radius(arm, site)
			contact_shape.radius = radius + 0.025 * creature_scale
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = contact_shape
			query.transform.origin = vec(nodes[site])
			query.collision_mask = 4 | 16 # Static terrain is solved by the uploaded native mesh.
			query.margin = 0.001
			var info := world.get_rest_info(query)
			if info.is_empty():
				continue
			var body = instance_from_id(info.collider_id)
			var collider_id := 0
			if body is RigidBody3D:
				if not body.has_meta("octo_collider_id"):
					body.set_meta("octo_collider_id", next_collider_id)
					collider_bodies[next_collider_id] = body
					next_collider_id += 1
				collider_id = int(body.get_meta("octo_collider_id"))
			var point: Vector3 = info.point
			var normal: Vector3 = info.normal
			contacts.append(" %d %d %.5f %.5f %.5f %.5f %.5f %.5f %d" % [arm, site,
				point.x, point.y, point.z, normal.x, normal.y, normal.z, collider_id])
	var out := " %d" % forces.size()
	for key: Vector2i in forces:
		var force: Vector3 = forces[key]
		out += " %d %d %.5f %.5f %.5f" % [key.x, key.y, force.x, force.y, force.z]
	forces.clear()
	out += " %d" % contacts.size()
	for contact in contacts:
		out += contact
	scene_suffix = out

func _contact_radius(arm: int, site: int) -> float:
	if arm < 0:
		return (0.065 if site < 7 else 0.033) * creature_scale
	var state: Dictionary = current.animals[0].arms[arm]
	var contact_radii: Array = state.get("contact_radii", [])
	if site < contact_radii.size():
		return float(contact_radii[site])
	return 0.036 * creature_scale * (1.0 - 0.8 * float(site) / 16.0)

func _try_grip(arm: int, site: int, body: RigidBody3D, point: Vector3, _normal: Vector3 = Vector3.ZERO) -> void:
	if target_kind != 3 or body != hero_target_body or _arm_locked(0, arm) or int(_source_arm_command(arm).grab_mode) != 1 or hunter.objective.result != &"":
		return
	var center := vec(current.animals[0].arms[arm].nodes[site])
	if site != current.animals[0].arms[arm].nodes.size() - 4 or center.distance_to(point) > _grab_radius(arm, site) + 0.035 * creature_scale:
		return
	var anchor := anchors[arm]
	anchor.site = site
	anchor.global_position = center
	var part: StringName = body.get_meta("hunter_part")
	var id := hunter.physics_rig.attach_grip(part, anchor, point, 90.0 * creature_scale, 2.0 * creature_scale * creature_scale, 6.0 * pow(creature_scale, 3.0), 0.8 * creature_scale)
	if id < 0:
		return
	grips[arm] = {"id": id, "part": part, "radius": center.distance_to(body.global_position)}
	hunter.try_capture(capture_threat, capture_threat.restraint_strength)

func _capture_supported() -> bool:
	for arm in grips:
		if threats[arm].active and hunter.physics_rig.grips.has(grips[arm].id):
			return true
	return false

func _validate_grips() -> void:
	for arm in grips.keys():
		if not hunter.physics_rig.grips.has(grips[arm].id):
			_drop_grip(arm)
	if is_instance_valid(hunter.capture_source):
		if not _capture_supported():
			hunter.release_capture()
	if snapshot_age > 0.25:
		release_grips()

func _drop_grip(arm: int) -> void:
	grip_candidates.erase(arm)
	if grips.has(arm):
		hunter.physics_rig.release_grip(grips[arm].id)
		grips.erase(arm)
	if not _capture_supported():
		hunter.release_capture(capture_threat)
	anchors[arm].site = 12
	release_cooldown = maxf(release_cooldown, 0.25)

func release_grips() -> void:
	grip_candidates.clear()
	for arm in grips.keys():
		_drop_grip(arm)
	if is_instance_valid(hunter):
		hunter.release_capture()

func _disable_arm(arm: int) -> void:
	_drop_grip(arm)
	threats[arm].active = false

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or suspended or resetting:
		return
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_CTRL:
			_apply_ctrl_release()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not current.is_empty():
		dragging = false
		if event.pressed:
			if not Input.is_physical_key_pressed(KEY_ALT):
				select_mouse_target(event.position)
				return
			var center := vec(current.animals[0].center)
			var hit = AABB(center - Vector3.ONE * 0.45 * creature_scale, Vector3.ONE * 0.9 * creature_scale).intersects_ray(
				camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if hit != null:
				dragging = true
				drag_kind = 1
				drag_index = 0
				drag_target = center
				drag_plane = Plane(camera.global_basis.z, drag_target)
	if event is InputEventMouseMotion and dragging:
		var hit = drag_plane.intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
		if hit != null:
			drag_target = hit

func fail(message: String) -> void:
	fault = message
	quitting = true
	stop_reader = true
	release_grips()
	push_error(message)
	bridge_failed.emit(message)
