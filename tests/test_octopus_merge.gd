extends SceneTree
var checks: int = 0
var failures: Array[String] = []
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func wait_native(tick: int, timeout: float = 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not game.octopus.fault.is_empty():
			return false
		if game.octopus.geometry_ready and not game.octopus.resetting and not game.octopus.current.is_empty() and int(game.octopus.current.tick) >= tick:
			return true
		await process_frame
	return false

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	if "--model-layout-only" in OS.get_cmdline_user_args():
		var model: Node3D = load("res://assets/octopus/Octopus_GameReady_v5.glb").instantiate()
		root.add_child(model)
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var layout = preload("res://scripts/octopus/arm_layout.gd")
		for arm in range(8):
			var first := skeleton.get_bone_global_rest(skeleton.find_bone("A%d_00" % layout.MODEL_ARM_IDS[arm])).origin
			var fifth := skeleton.get_bone_global_rest(skeleton.find_bone("A%d_05" % layout.MODEL_ARM_IDS[arm])).origin
			var direction := fifth - first
			var angle := rad_to_deg(atan2(direction.x, direction.z)) + rad_to_deg(layout.MODEL_YAW)
			print("MODEL_ARM_REST arm=%d model=%d degrees=%.4f expected=%.4f" % [arm, layout.MODEL_ARM_IDS[arm], angle, layout.HOME_DEGREES[arm]])
			check(absf(wrapf(angle - layout.HOME_DEGREES[arm], -180.0, 180.0)) < 3.0,
				"Original model arm %d matches the generated symmetric home angle" % arm)
		model.queue_free()
		_finish()
		return
	if "--map-geometry-only" in OS.get_cmdline_user_args():
		var map: TidalArena = load("res://scenes/tidal_colosseum_environment.tscn").instantiate()
		root.add_child(map)
		var exporter = load("res://scripts/octopus/octopus_controller.gd").new()
		exporter.arena = map
		var commands: Array[String] = exporter._build_mesh_setup()
		var triangle_count: int = exporter.static_triangle_count
		check(triangle_count > 0 and commands[0] == "mesh_begin %d" % (triangle_count * 3) and commands[-1] == "mesh_commit",
			"Actual static map collision geometry is exported into the native setup protocol")
		var vertices := 0
		var contiguous := true
		for index in range(1, commands.size() - 1):
			var fields := commands[index].split(" ", false)
			var offset := int(fields[1])
			var count := int(fields[2])
			contiguous = contiguous and offset == vertices and count <= 600 and count % 3 == 0 and fields.size() == 3 + count * 3
			vertices += count
		check(contiguous and vertices == triangle_count * 3, "Mesh chunks are contiguous, triangle-aligned and bounded to 600 vertices")
		var box := StaticBody3D.new()
		map.add_child(box)
		box.position = Vector3(3, 5, 7)
		box.rotation_degrees.y = 30.0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(2, 4, 6)
		box.add_child(shape)
		var disabled := CollisionShape3D.new()
		disabled.shape = BoxShape3D.new()
		disabled.disabled = true
		box.add_child(disabled)
		commands = exporter._build_mesh_setup()
		check(exporter.static_triangle_count == triangle_count + 12,
			"An enabled transformed BoxShape exports twelve triangles and a disabled shape is excluded")
		var last_chunk := commands[-2].split(" ", false)
		var box_start := 3 + (int(last_chunk[2]) - 36) * 3
		var exported_corner := Vector3(float(last_chunk[box_start]), float(last_chunk[box_start + 1]), float(last_chunk[box_start + 2]))
		check(exported_corner.distance_to(shape.global_transform * Vector3(-1, -2, -3)) < 0.000002,
			"Static collider faces include the full world transform")
		var empty := TidalArena.new()
		exporter.arena = empty
		check(exporter._build_mesh_setup() == ["mesh_begin 0", "mesh_commit"],
			"An empty static map still sends the explicit begin and commit handshake")
		empty.free()
		exporter.free()
		map.queue_free()
		_finish()
		return
	game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var o = game.octopus
	var target: HunterTarget = game.hunter
	check(await wait_native(30), "Integrated scene starts the real native octopus solver")
	if o.current.is_empty():
		_finish()
		return
	print("OCTOPUS_REAL_MAP_PROFILE tick=%d triangles=%d solver_ms=%.3f rpc_ms=%.3f" % [int(o.current.tick), int(o.current.static_triangles), float(o.current.diagnostics.step_ms), o.rpc_ms])
	check(o.geometry_ready and game.ready_for_round and int(o.current.static_triangles) == o.static_triangle_count and o.static_triangle_count > 0,
		"Native stepping waits for the complete actual map collision mesh")
	check(is_equal_approx(float(o.current.size_scale), 1.5) and is_equal_approx(o.creature_scale, 1.5),
		"Native physical size and skin size both use 1.5")
	var drag_fields: PackedStringArray = o.step_command().split(" ", false)
	check(is_equal_approx(float(drag_fields[104]), 67.5) and is_equal_approx(float(drag_fields[105]), 67.5),
		"Production drag stiffness and force cap scale with physical size and mass")
	check(o.views[0].scene.scale.is_equal_approx(Vector3.ONE * o.MODEL_SCALE * 1.5),
		"GameReady renderer applies the same whole-creature scale")
	check(o.EXTEND_KEYS == [KEY_U, KEY_O, KEY_J, KEY_L, KEY_S, KEY_F, KEY_W, KEY_R] and
		o.STROKE_KEYS == [KEY_I, KEY_P, KEY_K, KEY_SEMICOLON, KEY_A, KEY_D, KEY_Q, KEY_E],
		"All eight arm bindings match their body-front spatial order")
	for arm in range(8):
		var state: Dictionary = o.current.animals[0].arms[arm]
		check(is_equal_approx(rad_to_deg(float(state.home_angle)), float(o.HOME_DEGREES[arm])) and
			int(state.model_arm) == int(o.MODEL_ARM_IDS[arm]), "Arm %d native home angle and skin identity share the layout" % arm)
		var rests: Array = o.views[0].bone_rests[o.MODEL_ARM_IDS[arm]]
		var rest_direction: Vector3 = rests[5].origin - rests[0].origin
		var rest_angle := rad_to_deg(atan2(rest_direction.x, rest_direction.z))
		check(absf(wrapf(rest_angle - o.HOME_DEGREES[arm], -180.0, 180.0)) < 3.0,
			"Arm %d GameReady rest direction matches the symmetric body-front home angle" % arm)
		check(state.contact_radii.size() == 17 and state.sucker_directions.size() == 17,
			"Arm %d exposes actual node contact radii and sucker faces" % arm)
	check(game.arena.props.size() == 48, "Original map and 48 physical props coexist with the octopus")
	check(o.views[0].skel.get_bone_count() == 193 and o.threats.size() == 8, "Original octopus skeleton and eight hunter threat adapters are connected")
	check(o.current.body_nodes.size() == 19, "Latest native torso cage and mantle shell reach the Godot contact bridge")
	check(o.current.animals[0].arms[0].tissue.size() == 16 and o.current.animals[0].arms[0].creep.size() == 16,
		"Latest viscous tissue and creep state reach the integrated renderer")
	check(o.views[0].torso_root >= 0, "Original GameReady root bone is connected to the new physical mantle shell")
	check(target.capture_seconds_override == 10.0 and target.objective.continuous_capture, "Merged scene selects continuous ten-second capture")
	var before: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_U, true)
	await process_frame
	check(o.step_command().contains("0 0 1.000000 0.000000 1.480000"), "Physical U key reaches latest right-front native muscle command")
	var tick := int(o.current.tick)
	check(await wait_native(tick + 65), "Native simulation keeps advancing under actual key input")
	check(float(o.current.animals[0].arms[0].uncoil) >= 0.99, "Held U progressively uncoils the actual native arm")
	var after: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_U, false)
	check(before.distance_to(after) > 0.01, "Held U produces measurable movement of the actual native arm")
	for arm in range(8):
		check(o.step_command().contains("0 %d 0.000000 3.600000 0.580000 0 0.02 0 0.000000 0 0 0" % arm),
			"Idle arm %d has no active input or suction flag" % arm)
		key(o.EXTEND_KEYS[arm], true)
		check(o.step_command().contains("0 %d 1.000000 0.000000 1.480000 0 0.02 0 -1.000000 1 0 0" % arm),
			"Arm %d extend has its own phase flag" % arm)
		key(o.EXTEND_KEYS[arm], false)
		key(o.STROKE_KEYS[arm], true)
		check(o.step_command().contains("0 %d 1.000000 3.600000 0.580000 0 0.02 0 1.000000 0 1 0" % arm),
			"Arm %d stroke has its own phase flag" % arm)
		key(o.EXTEND_KEYS[arm], true)
		await process_frame
		check(o.step_command().contains("0 %d 1.000000 0.000000 1.480000 0 0.02 0 1.000000 1 1 0" % arm), "Arm %d preserves both independent latest control channels" % arm)
		key(o.EXTEND_KEYS[arm], false)
		key(o.STROKE_KEYS[arm], false)
	key(KEY_U, true)
	o._update_grab_rearm()
	key(KEY_SPACE, true)
	o._update_grab_rearm()
	key(KEY_SPACE, false)
	o._update_grab_rearm()
	check(o.grab_rearm_required[0], "Space leaves a held extend key disarmed after release")
	key(KEY_U, false)
	o._update_grab_rearm()
	key(KEY_U, true)
	o._update_grab_rearm()
	check(not o.grab_rearm_required[0], "A fresh extend rising edge rearms the corresponding actor sucker")
	key(KEY_U, false)
	o._update_grab_rearm()
	# Exercise the real contact gate against a separated hitbox: no distance cheat.
	var body := target.physics_rig.get_part_body(&"torso")
	o._try_grip(0, 12, body, o.vec(o.current.animals[0].arms[0].nodes[12]), Vector3.UP)
	check(o.grips.is_empty(), "An idle arm cannot start a hunter grip even when passed a contact sample")
	key(KEY_U, true)
	o._try_grip(0, 12, body, body.global_position, Vector3.UP)
	key(KEY_U, false)
	check(o.grips.is_empty() and not is_instance_valid(target.capture_source), "A separated torso cannot be captured by a proximity shortcut")
	game._toggle_pause()
	await create_timer(0.15, true).timeout
	var paused_tick := int(o.current.tick)
	var paused_progress := target.objective.capture_progress
	await create_timer(0.25, true).timeout
	check(int(o.current.tick) == paused_tick and target.objective.capture_progress == paused_progress, "Pause stops native stepping and objective time together")
	game._toggle_pause()
	# Test precise win timing without wall-clock scheduling or frame-rate ambiguity.
	o.suspended = true
	target.process_mode = Node.PROCESS_MODE_DISABLED
	var wins: Array = []
	target.objective.resolved.connect(func(result: StringName, _score: int): wins.append(result))
	for level in range(1, 4):
		target.set_difficulty(level)
		check(target.objective.capture_seconds == 10.0, "Difficulty %d keeps the requested ten-second goal" % level)
		target.objective.tick_capture(9.99, true)
		check(target.objective.result == &"", "Difficulty %d cannot win before ten seconds" % level)
		target.objective.tick_capture(0.0, false)
		check(target.objective.capture_progress == 0.0, "Difficulty %d fully resets progress when the hold breaks" % level)
		target.objective.tick_capture(0.01, true)
		check(target.objective.result == &"", "A new hold cannot reuse time from the previous capture")
		target.objective.reset_objective()
	target.try_capture(o.threats[0], 3.2)
	target.objective.tick_capture(5.0, true)
	target.release_capture()
	check(target.objective.capture_progress == 0.0, "Explicit release clears the continuous timer immediately")
	target.objective.tick_capture(10.0, false)
	check(target.objective.result == &"", "An unrestrained target never grants a timer victory")
	target.objective.reset_objective()
	for i in range(599):
		target.objective.tick_capture(1.0 / 60.0, true)
	check(target.objective.result == &"", "599 fixed steps remain below the ten-second threshold")
	target.objective.tick_capture(1.0 / 60.0, true)
	check(target.objective.result == &"captured" and game.round_result == &"captured", "The 600th captured step resolves octopus victory in the actual game")
	target.objective.tick_capture(10.0, true)
	check(wins.size() == 1, "Victory is emitted only once per round")
	game.reset_round()
	var reset_deadline := Time.get_ticks_msec() + 7000
	while o.resetting and Time.get_ticks_msec() < reset_deadline:
		await process_frame
	check(not o.resetting and game.round_result == &"" and target.objective.capture_progress == 0.0 and o.grips.is_empty(), "Reset clears victory, grips and timer and restarts the actual native world")
	check(await wait_native(5), "Native stepping resumes after a finished round resets")
	_finish()

func _finish() -> void:
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://.tools/octopus_merge_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("OCTOPUS_MERGE_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
