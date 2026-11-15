extends SceneTree
var failures: Array[String] = []
var checks := 0
const CONTROLLER = preload("res://scripts/octopus/octopus_controller.gd")

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
	print("PASS: " if ok else "FAIL: ", text)

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _input_parity() -> void:
	check(FileAccess.get_sha256("res://scripts/octopus/arm_controls.gd") == FileAccess.get_sha256("res://native/octo/game/scripts/arm_controls.gd"), "Latest 9a2a7df control module matches source bytes")
	var latest = preload("res://native/octo/game/scripts/arm_controls.gd")
	var local = preload("res://scripts/octopus/arm_controls.gd")
	for arm in range(8):
		var a = local.new()
		var b = latest.new()
		var same := true
		for row in [[0.0,false],[0.19,false],[0.29,true],[0.50,false],[0.68,false]]:
			same = same and a.sample(arm,row[0],true,false,false,false,row[1]) == b.sample(arm,row[0],true,false,false,false,row[1])
		check(same, "Arm%d latest reach/seal/pull/release source parity" % arm)
	var o = CONTROLLER.new()
	o.animals = 1
	o.creature_scale = 1.5
	var states: Array = []
	for arm in range(8):
		o.threats.append(HunterThreat.new())
		states.append({"attached": [], "grabbed": false})
	o.current = {"time":0.0,"animals":[{"arms":states}],"rigids":[]}
	key(KEY_R,true)
	key(KEY_SHIFT,true)
	var cmd: Dictionary = o._source_arm_command(0)
	check(int(cmd.grab_mode) == 0 and is_equal_approx(cmd.extension,1.38), "Shift without a selected target cannot request a remote grab or old continuous reach")
	var body := RigidBody3D.new()
	root.add_child(body)
	o.hero_target_body = body
	o.target_kind = 3
	o.target_index = 0
	cmd = o._source_arm_command(0)
	check(int(cmd.grab_mode) == 1 and is_equal_approx(cmd.activation,0.90) and is_equal_approx(cmd.extension,1.42), "Shift plus selected hero uses latest strong attack command")
	var wire: PackedStringArray = o.step_command().split(" ",false)
	check(wire[0] == "step6" and int(wire[83]) == 3, "Step6 serializes the selected hero target after the source command and drag fields")
	states[0].grabbed = true
	key(KEY_PERIOD,true)
	cmd = o._source_arm_command(0)
	check(float(cmd.activation) == 0.0 and float(cmd.twist) == 0.0 and int(cmd.grab_mode) == 0, "A grabbed arm locks movement, Shift attack and twist")
	key(KEY_CTRL,true)
	cmd = o._source_arm_command(0)
	check(int(cmd.grab_mode) == 2 and int(o._source_arm_command(1).grab_mode) == 0, "Ctrl plus arm releases only that arm")
	key(KEY_R,false)
	check(int(o._source_arm_command(1).grab_mode) == 0, "Ctrl+Shift without an arm is reserved for the existing secret chord")
	key(KEY_SHIFT,false)
	check(int(o._source_arm_command(1).grab_mode) == 2, "Ctrl alone releases all arms")
	for code in [KEY_SHIFT,KEY_CTRL,KEY_PERIOD]:
		key(code,false)
	for threat in o.threats:
		threat.free()
	o.free()
	body.queue_free()

func _run() -> void:
	if not "--startup-only" in OS.get_cmdline_user_args():
		_input_parity()
	if "--controls-only" in OS.get_cmdline_user_args():
		_finish()
		return
	var game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var o = game.octopus
	var deadline := Time.get_ticks_msec() + 15000
	while (not o.geometry_ready or o.current.is_empty() or int(o.current.get("tick",0)) < 2) and o.fault.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(o.geometry_ready and o.fault.is_empty() and int(o.current.get("tick",0)) >= 2, "Latest engine starts once with the actual map collision mesh ready")
	if o.geometry_ready and o.fault.is_empty():
		check(str(o.current.get("source_commit", "")).begins_with("9a2a7df"), "Running engine reports the latest requested source commit")
		check(o.current.animals[0].arms[0].grab_radii.size() == 17 and is_equal_approx(float(o.current.size_scale),1.5), "Latest physical grab radii and world scale reach Godot")
		var body: RigidBody3D = game.hunter.physics_rig.get_part_body(&"torso")
		o.select_mouse_target(game.camera.unproject_position(body.global_position))
		check(o.target_kind == 3 and is_instance_valid(o.hero_target_body) and o.target_marker.visible, "A real hunter hitbox ray selects a world target and gold marker")
		var target_tick := int(o.current.tick)
		var target_deadline := Time.get_ticks_msec() + 3000
		while int(o.current.tick) <= target_tick and o.fault.is_empty() and Time.get_ticks_msec() < target_deadline:
			await process_frame
		check(o.fault.is_empty() and int(o.current.tick) > target_tick, "The selected hero step6 target packet is accepted without running a grab fixture")
	if "--extended-gameplay" in OS.get_cmdline_user_args() and o.geometry_ready and o.fault.is_empty():
		await _extended_gameplay_checks(game)
	_finish()

func _finish() -> void:
	var result := {"checks":checks,"failures":failures,"passed":failures.is_empty()}
	var file := FileAccess.open("res://.tools/octopus_merge_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("OCTOPUS_MERGE_RESULT ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

# Expensive gameplay coverage is retained explicitly opt-in, separate from smoke.
func _wait_native_ticks(o, tick: int, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not o.fault.is_empty():
			return false
		if o.geometry_ready and not o.resetting and not o.current.is_empty() and int(o.current.tick) >= tick:
			return true
		await process_frame
	return false

func _extended_gameplay_checks(game) -> void:
	var o = game.octopus
	var target: HunterTarget = game.hunter
	check(game.arena.props.size() == 48 and o.views[0].skel.get_bone_count() == 193 and o.threats.size() == 8,
		"Original map props, GameReady skeleton and eight threat adapters remain integrated")
	check(o.current.body_nodes.size() == 19 and o.views[0].skin_config.covered_surfaces > 0,
		"Physical mantle and source GPU skin remain connected")
	var shape: Vector3 = o.mantle_scale_from_shell(o.current.body_nodes,o.vec(o.current.animals[0].center),o.quat(o.current.animals[0].orientation).inverse())
	check(absf(shape.x * shape.y * shape.z - 1.0) < 0.00001,
		"Mantle gross deformation preserves volume rather than ballooning")
	for arm in range(8):
		var rests: Array = o.views[0].bone_rests[(7-arm)%8]
		var direction: Vector3 = rests[5].origin - rests[0].origin
		var angle := rad_to_deg(atan2(direction.x,direction.z) + o.MODEL_YAW)
		check(absf(wrapf(angle - arm*45.0,-180.0,180.0)) < 3.0,
			"Arm%d source skin/yaw correspondence remains aligned" % arm)
	o._clear_target()
	var before: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_R,true) # Latest ordinary gait; Shift is now target attack, not reach.
	check(await _wait_native_ticks(o,int(o.current.tick)+65), "Native solver advances under actual latest arm input")
	var after: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_R,false)
	check(before.distance_to(after) > 0.01, "Actual arm input produces measurable native movement")
	# The following inherited checks isolate objective timing; real acquisition
	# and continuous physical holding are covered by --physical-capture.
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
	check(await _wait_native_ticks(o,5), "Native stepping resumes after a finished round resets")
