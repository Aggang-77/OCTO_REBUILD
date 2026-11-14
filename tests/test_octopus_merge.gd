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
		if not game.octopus.current.is_empty() and int(game.octopus.current.tick) >= tick:
			return true
		await process_frame
	return false

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var o = game.octopus
	var target: HunterTarget = game.hunter
	check(await wait_native(30), "Integrated scene starts the real native octopus solver")
	if o.current.is_empty():
		_finish()
		return
	check(game.arena.props.size() == 48, "Original map and 48 physical props coexist with the octopus")
	check(o.views[0].skel.get_bone_count() == 193 and o.threats.size() == 8, "Original octopus skeleton and eight hunter threat adapters are connected")
	check(o.current.body_nodes.size() == 7, "Actual native torso sites reach the Godot contact bridge")
	check(target.capture_seconds_override == 10.0 and target.objective.continuous_capture, "Merged scene selects continuous ten-second capture")
	var before: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_J, true)
	await process_frame
	check(o.step_command().contains("0 0 1.000000 0.000000 1.280000"), "Physical J key reaches right-front native muscle command")
	var tick := int(o.current.tick)
	check(await wait_native(tick + 65), "Native simulation keeps advancing under actual key input")
	var after: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[-1]) - o.vec(o.current.animals[0].center)
	key(KEY_J, false)
	check(before.distance_to(after) > 0.01, "Held J produces measurable movement of the actual native arm")
	for arm in range(8):
		key(o.EXTEND_KEYS[arm], true)
		key(o.STROKE_KEYS[arm], true)
		await process_frame
		check(o.step_command().contains("0 %d 1.000000 0.000000 1.280000 0 0.15 0 1.000000" % arm), "Arm %d preserves both independent original control channels" % arm)
		key(o.EXTEND_KEYS[arm], false)
		key(o.STROKE_KEYS[arm], false)
	# Exercise the real contact gate against a separated hitbox: no distance cheat.
	var body := target.physics_rig.get_part_body(&"torso")
	o._try_grip(0, 12, body, body.global_position)
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
	var reset_deadline := Time.get_ticks_msec() + 5000
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
