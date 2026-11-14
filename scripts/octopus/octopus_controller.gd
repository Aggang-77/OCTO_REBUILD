extends "res://scripts/octopus/rebuild_demo.gd"
## Native muscle controls/skin plus explicit Godot terrain/contact coupling.
signal bridge_failed(message: String)
signal native_reset
const ANCHOR = preload("res://scripts/octopus/contact_anchor.gd")
var arena: TidalArena
var hunter: HunterTarget
var spawn := Vector3(0, 0.65, 0)
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

func _ready() -> void:
	animals = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -30
	terrain_reset = _build_reset_command()
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
		threat.radius = 0.12
		threat.cut_radius = 0.10
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
	pass # The integration scene supplies arena, camera and UI.

func _build_reset_command() -> String:
	var command := "game_reset %.5f %.5f %.5f 65 -28 -28 0.875" % [spawn.x, spawn.y, spawn.z]
	for z in range(65):
		for x in range(65):
			command += " %.4f" % arena.terrain_height(-28.0 + x * 0.875, -28.0 + z * 0.875)
	return command

func reset_command() -> String:
	# Called on the pipe worker too: no scene/resource access on that thread.
	return terrain_reset

func request_reset() -> void:
	release_grips()
	forces.clear()
	scene_suffix = " 0 0"
	dragging = false
	resetting = true
	for threat in threats:
		threat.reset_threat()
	inbox_lock.lock()
	reset_requested = true
	inbox_lock.unlock()

func add_site_force(arm: int, site: int, force: Vector3) -> void:
	var key := Vector2i(arm, site)
	forces[key] = (forces.get(key, Vector3.ZERO) + force).limit_length(700.0)

func step_command() -> String:
	var out := "step3 8"
	for arm in range(8):
		var enabled := threats[arm].active
		var reach := enabled and Input.is_physical_key_pressed(EXTEND_KEYS[arm])
		var paddle := enabled and Input.is_physical_key_pressed(STROKE_KEYS[arm])
		out += " 0 %d %f %f %f 0 0.15 0 %f" % [arm, 1.0 if enabled else 0.0,
			0.0 if reach else 3.6, 1.28 if reach else 0.70, (1.0 if paddle else -1.0) if enabled else 0.0]
	out += " %d 0 %d %f %f %f 30 20 %d" % [drag_kind if dragging else 0,
		drag_index, drag_target.x, drag_target.y, drag_target.z,
		1 if Input.is_physical_key_pressed(KEY_SPACE) else 0]
	return out + scene_suffix

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
		inbox_lock.lock()
		if auto_step and not pending and not stop_reader and Time.get_ticks_usec() >= next_due_usec:
			var command := terrain_reset if reset_requested else latest_command
			reset_requested = false
			if not command.is_empty():
				request_id += 1
				pending = true
				sent_at = Time.get_ticks_usec()
				next_due_usec = maxi(next_due_usec + 16667, sent_at)
				pipe.store_string("1 %d %s\n" % [request_id, command])
				pipe.flush()
		inbox_lock.unlock()
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
		var frame: Dictionary = parsed.snapshot.frame
		current = frame.world
		current["body_nodes"] = frame.body_nodes
		current["reactions"] = frame.reactions
		snapshot_age = 0.0
		update_scene()
		if int(current.tick) == 0:
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
	elif current.is_empty() and pending and Time.get_ticks_usec() - sent_at > 15000000:
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
	auto_step = not suspended and not get_tree().paused
	latest_command = step_command() if auto_step else ""
	inbox_lock.unlock()

func _physics_process(delta: float) -> void:
	if quitting or get_tree().paused or suspended or current.is_empty() or resetting:
		return
	release_cooldown = maxf(0.0, release_cooldown - delta)
	if Input.is_physical_key_pressed(KEY_SPACE):
		release_grips()
		release_cooldown = 0.25
	_validate_grips()
	var contacts: Array[String] = []
	var world := get_world_3d().direct_space_state
	for arm in range(-1, 8):
		var nodes: Array = current.body_nodes if arm < 0 else current.animals[0].arms[arm].nodes
		for site in range(nodes.size()):
			var radius := 0.065 if arm < 0 else 0.036 * (1.0 - 0.8 * float(site) / 16.0)
			contact_shape.radius = radius + 0.025
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = contact_shape
			query.transform.origin = vec(nodes[site])
			query.collision_mask = 1 | 4 | 16
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
			# Query the hunter independently so a simultaneous floor contact does
			# not hide a real foot/leg contact from suction detection.
			if arm >= 0 and site >= 4 and not grips.has(arm):
				query.collision_mask = 4
				var hunter_info := world.get_rest_info(query)
				if not hunter_info.is_empty():
					var hitbox = instance_from_id(hunter_info.collider_id)
					if hitbox is RigidBody3D and hitbox.get_meta("hunter_target", null) == hunter:
						_try_grip(arm, site, hitbox, hunter_info.point)
	var out := " %d" % forces.size()
	for key: Vector2i in forces:
		var force: Vector3 = forces[key]
		out += " %d %d %.5f %.5f %.5f" % [key.x, key.y, force.x, force.y, force.z]
	forces.clear()
	out += " %d" % contacts.size()
	for contact in contacts:
		out += contact
	scene_suffix = out

func _try_grip(arm: int, site: int, body: RigidBody3D, point: Vector3) -> void:
	if grips.has(arm) or not threats[arm].active or release_cooldown > 0.0 or Input.is_physical_key_pressed(KEY_SPACE) or hunter.objective.result != &"":
		return
	# Broadphase is enlarged; suction itself requires real hitbox surface contact.
	var center := vec(current.animals[0].arms[arm].nodes[site])
	var radius := 0.036 * (1.0 - 0.8 * float(site) / 16.0)
	if center.distance_to(point) > radius + 0.008:
		return
	var anchor := anchors[arm]
	anchor.site = site
	anchor.global_position = center
	var part: StringName = body.get_meta("hunter_part")
	# The native site has much less mass than the character's lab test rigid.
	# A bounded, softer spring avoids unstable 60 Hz feedback across solvers.
	var id := hunter.physics_rig.attach_grip(part, anchor, point, 90.0, 2.0, 6.0, 0.8)
	if id < 0:
		return
	grips[arm] = {"id": id, "part": part}
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
	if grips.has(arm):
		hunter.physics_rig.release_grip(grips[arm].id)
		grips.erase(arm)
	if not _capture_supported():
		hunter.release_capture(capture_threat)
	anchors[arm].site = 12
	release_cooldown = maxf(release_cooldown, 0.25)

func release_grips() -> void:
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
		if event.pressed and event.keycode == KEY_SPACE:
			release_grips()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not current.is_empty():
		dragging = false
		if event.pressed:
			var center := vec(current.animals[0].center)
			var hit = AABB(center - Vector3.ONE * 0.45, Vector3.ONE * 0.9).intersects_ray(
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
