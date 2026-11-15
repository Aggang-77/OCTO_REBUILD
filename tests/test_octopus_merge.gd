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

func wait_native(tick: int, timeout: float = 15.0) -> bool:
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

func _source_controls_checks() -> void:
	var local = preload("res://scripts/octopus/arm_controls.gd")
	var upstream = preload("res://native/octo/game/scripts/arm_controls.gd")
	check(FileAccess.get_sha256("res://scripts/octopus/arm_controls.gd") == FileAccess.get_sha256("res://native/octo/game/scripts/arm_controls.gd"),
		"Imported control module is byte-for-byte upstream8bb7434")
	check(FileAccess.get_sha256("res://scripts/octopus/octopus_skin.gdshader") == FileAccess.get_sha256("res://native/octo/game/shaders/octopus_skin.gdshader"),
		"GPU skin shader is byte-for-byte upstream8bb7434")
	var skin_local := FileAccess.get_file_as_string("res://scripts/octopus/octopus_skin.gd").replace("\r\n", "\n").replace("res://scripts/octopus/octopus_skin.gdshader", "res://shaders/octopus_skin.gdshader")
	check(skin_local == FileAccess.get_file_as_string("res://native/octo/game/scripts/octopus_skin.gd").replace("\r\n", "\n"),
		"GPU skin module differs from upstream only in its resource path")
	check(local.KEYS == [KEY_R, KEY_E, KEY_W, KEY_Q, KEY_P, KEY_O, KEY_I, KEY_U], "Source mirrored eight-key mapping is preserved")
	check(local.REACH_TIME == 0.18 and local.ANCHOR_TIMEOUT == 0.40 and local.PULL_TIME == 0.42 and local.RELEASE_TIME == 0.16,
		"Source native-time phase timings are preserved")
	for arm in range(8):
		var a = local.new()
		var b = upstream.new()
		var same := true
		for row in [[0.0,true,false,false,false,false,true], [0.18,true,false,false,false,false,true],
			[0.23,true,false,false,false,true,true], [0.24,true,false,false,false,false,true],
			[0.41,true,false,false,false,false,true], [0.5,true,true,false,false,true,true],
			[0.6,true,true,true,false,true,true], [0.7,false,false,false,false,false,false],
			[0.0,true,false,false,false,false,false], [0.18,true,false,false,false,false,false],
			[0.30,true,false,false,false,false,false]]:
			var actual: Dictionary = a.sample(arm,row[0],row[1],row[2],row[3],row[4],row[5],1.0,row[6])
			var expected: Dictionary = b.sample(arm,row[0],row[1],row[2],row[3],row[4],row[5],1.0,row[6])
			same = same and actual == expected and a.phases[arm] == b.phases[arm]
		check(same, "Arm%d source parity covers seal, real-contact pull, loss, modifiers, Spaceoff and time reset" % arm)
	var controls = local.new()
	controls.sample(0,0.0,true,false,false,false,false,1.0,true)
	controls.sample(0,0.18,true,false,false,false,false,1.0,true)
	check(controls.phases[0] == "anchor", "Reach advances to anchor after0.18native seconds")
	var cmd: Dictionary = controls.sample(0,0.30,true,false,false,false,false,1.0,true)
	check(controls.phases[0] == "anchor" and cmd.extension == 1.32, "Spaceheld cannot enter powered pull before real attachment")
	for render_frame in range(100):
		controls.sample(0,0.30,true,false,false,false,false,1.0,true)
	check(controls.phases[0] == "anchor" and controls.starts[0] == 0.18,
		"Repeated render samples cannot advance a source phase without native simulation time")
	cmd = controls.sample(0,0.31,true,false,false,false,true,1.0,true)
	check(controls.phases[0] == "pull" and cmd.extension == 0.67, "Confirmed actual attachment permits the source strong pull")
	cmd = controls.sample(0,0.32,true,false,false,false,false,1.0,true)
	check(controls.phases[0] == "release" and cmd.activation == 0.0, "Lost attachment ends the powered stroke")

func _run() -> void:
	_source_controls_checks()
	if "--controls-only" in OS.get_cmdline_user_args():
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
	check(await wait_native(30), "Integrated scene starts the real upstream native solver after mesh commit")
	if o.current.is_empty() or not o.geometry_ready or not o.fault.is_empty():
		_finish()
		return
	print("OCTOPUS_REAL_MAP_PROFILE tick=%d triangles=%d solver_ms=%.3f rpc_ms=%.3f" % [int(o.current.tick), int(o.current.static_triangles), float(o.current.diagnostics.step_ms), o.rpc_ms])
	check(str(o.current.get("source_commit", "")).begins_with("8bb7434"), "Gameplay bridge reports the requested authoritative source commit")
	check(o.geometry_ready and game.ready_for_round and int(o.current.static_triangles) == o.static_triangle_count and o.static_triangle_count > 0,
		"Round starts only after the complete actual map collision mesh is ready")
	check(is_equal_approx(float(o.current.size_scale),1.5) and o.views[0].scene.scale.is_equal_approx(Vector3.ONE * o.MODEL_SCALE * 1.5),
		"World coordinate transform and source skin both retain1.5size")
	check(is_equal_approx(o.spawn.y, game.arena.terrain_height(o.spawn.x,o.spawn.z)), "Reset5 origin is the actual map floor without the obsolete spawn offset")
	check(o.MODEL_YAW == -PI / 8.0, "Authoritative source model yaw is preserved")
	check(o.views[0].skel.get_bone_count() == 193 and o.threats.size() == 8 and game.arena.props.size() == 48,
		"Original octopus, hunter threat adapters and48physical props coexist")
	check(o.views[0].skin_config.covered_surfaces > 0 and o.views[0].web is MeshInstance3D,
		"Authoritative GPU skin and deforming interarm web are installed")
	var mantle: Vector3 = o.mantle_scale_from_shell(o.current.body_nodes,o.vec(o.current.animals[0].center),o.quat(o.current.animals[0].orientation).inverse())
	check(absf(mantle.x * mantle.y * mantle.z - 1.0) < 0.00001, "Source mantle gross deformation preserves scale determinant one")
	for arm in range(8):
		var state: Dictionary = o.current.animals[0].arms[arm]
		check(state.contact_radii.size() == 17 and state.sucker_dirs.size() == 17,
			"Arm%d world contact envelope and material sucker directions reach the scene" % arm)
		var rests: Array = o.views[0].bone_rests[(7-arm)%8]
		var direction: Vector3 = rests[5].origin - rests[0].origin
		var angle := rad_to_deg(atan2(direction.x,direction.z) + o.MODEL_YAW)
		check(absf(wrapf(angle - arm*45.0,-180.0,180.0)) < 3.0, "Arm%d original skin correspondence retains source yaw and reversed mapping" % arm)
	var fields: PackedStringArray = o.step_command().split(" ",false)
	check(fields[0] == "step5" and is_equal_approx(float(fields[80]),30.0) and is_equal_approx(float(fields[81]),30.0),
		"Step5 preserves source drag stiffness and converts the20native force cap to30world units")
	for arm in range(8):
		o.arm_controllers[0].reset()
		key(o.ARM_KEYS[arm],true)
		fields = o.step_command().split(" ",false)
		var offset := 2 + arm*9
		check(is_equal_approx(float(fields[offset+2]),0.8) and is_equal_approx(float(fields[offset+4]),1.38) and int(fields[82]) == 0,
			"Arm%d source reach command remains active with Spaceoff" % arm)
		key(KEY_SPACE,true)
		fields = o.step_command().split(" ",false)
		check(int(fields[82]) == 1 and o._actor_suction_allowed(arm), "Spaceheld enables real suction only for active arm%d" % arm)
		key(KEY_SHIFT,true)
		fields = o.step_command().split(" ",false)
		check(is_equal_approx(float(fields[offset+2]),0.78) and is_equal_approx(float(fields[offset+4]),1.35), "Shift preserves source continuous reach on arm%d" % arm)
		key(KEY_CTRL,true)
		fields = o.step_command().split(" ",false)
		check(is_equal_approx(float(fields[offset+4]),1.10), "Ctrl takes source brace precedence on arm%d" % arm)
		key(KEY_PERIOD,true)
		fields = o.step_command().split(" ",false)
		check(is_equal_approx(float(fields[offset+5]),3.0), "Period applies source material twist to arm%d" % arm)
		key(KEY_PERIOD,false)
		key(KEY_COMMA,true)
		fields = o.step_command().split(" ",false)
		check(is_equal_approx(float(fields[offset+5]),-3.0), "Comma applies opposite source twist to arm%d" % arm)
		for code in [KEY_COMMA,KEY_CTRL,KEY_SHIFT,KEY_SPACE,o.ARM_KEYS[arm]]:
			key(code,false)
		fields = o.step_command().split(" ",false)
		check(float(fields[offset+2]) == 0.0 and is_equal_approx(float(fields[offset+4]),1.04) and not o._actor_suction_allowed(arm),
			"Arm%d release returns to source passive rest and Spaceoff forbids acquisition" % arm)
	key(KEY_UP,true)
	fields = o.step_command().split(" ",false)
	var arrows_idle := true
	for arm in range(8):
		arrows_idle = arrows_idle and float(fields[2+arm*9+2]) == 0.0
	check(arrows_idle, "Arrow keys do not enable the superseded crawl assist")
	key(KEY_UP,false)
	var before: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_R,true)
	key(KEY_SHIFT,true)
	var tick := int(o.current.tick)
	check(await wait_native(tick+65), "Native simulation advances under an actual source reach input")
	var after: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	check(before.distance_to(after) > 0.01, "Source R+Shift produces measurable native arm movement")
	key(KEY_SHIFT,false)
	key(KEY_R,false)
	var body := target.physics_rig.get_part_body(&"torso")
	key(KEY_R,true)
	o._try_grip(0,12,body,o.vec(o.current.animals[0].arms[0].nodes[12]),Vector3.UP)
	check(o.grips.is_empty(), "Spaceoff rejects an attempted actor grip even with an active arm")
	key(KEY_SPACE,true)
	o._try_grip(0,12,body,body.global_position,Vector3.UP)
	check(o.grips.is_empty(), "Spaceheld cannot acquire a physically separated hunter")
	key(KEY_SPACE,false)
	key(KEY_R,false)
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
	var reset_deadline := Time.get_ticks_msec() + 15000
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
