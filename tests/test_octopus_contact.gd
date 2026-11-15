extends "res://tests/test_octopus_merge.gd"
## Latest-source physical fixture. Explicit --physical-capture (or
## --capture-contact) enables the expensive real-grab/ten-second checks.
## Default invocation retains the short input/startup smoke only.

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--physical-capture" in args and not "--capture-contact" in args:
		await super._run()
		return
	await _physical_capture()

func _fixture_start(game) -> bool:
	var o = game.octopus
	var h: HunterTarget = game.hunter
	if not await _wait_native_ticks(o,2):
		check(false,"Native solver starts for the opt-in physical fixture")
		return false
	h.profile = h.profile.duplicate()
	h.profile.move_speed = 0.0
	# Initial fixture placement only. No solver coordinates are changed.
	var spawn: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[13])
	spawn.y = game.arena.terrain_height(spawn.x,spawn.z) + 0.04
	h.reset_target(spawn + Vector3(0,0,0.2))
	await create_timer(0.5).timeout
	var torso: RigidBody3D = h.physics_rig.get_part_body(&"torso")
	o.select_mouse_target(game.camera.unproject_position(torso.global_position))
	check(o.target_kind == 3 and is_instance_valid(o.hero_target_body),
		"Physical fixture selects an actual hunter hitbox through the production ray")
	return o.target_kind == 3

func _wait_grips(o, count: int, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and o.fault.is_empty():
		if o.grips.size() >= count:
			return true
		await process_frame
	return false

func _release_inputs(o) -> void:
	for code in o.ARM_KEYS:
		key(code,false)
	for code in [KEY_SHIFT,KEY_CTRL,KEY_SPACE,KEY_COMMA,KEY_PERIOD]:
		key(code,false)

func _physical_capture() -> void:
	var game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var o = game.octopus
	var h: HunterTarget = game.hunter
	if not await _fixture_start(game):
		_finish_contact()
		return
	# Exercise production Shift approach only: no debug force, fabricated
	# contact, actor face/suction gate or direct native position writes.
	key(KEY_SHIFT,true)
	key(o.ARM_KEYS[0],true)
	var acquired := await _wait_grips(o,1)
	check(acquired,"Selected-target Shift approach acquires a real physical hunter grip")
	if not acquired:
		_release_inputs(o)
		_finish_contact()
		return
	var arm: int = o.grips.keys()[0]
	var id: int = o.grips[arm].id
	check(o.anchors[arm].site == o.current.animals[0].arms[arm].nodes.size()-4 and h.physics_rig.grips.has(id),
		"Real binding uses the source proximal grip node and the actor physical rig")
	key(o.ARM_KEYS[arm],false)
	key(KEY_SHIFT,false)
	await create_timer(0.15).timeout
	check(o._actual_actor_grip(arm),"Releasing the arm key preserves an actual carry")
	key(o.ARM_KEYS[arm],true)
	key(KEY_SHIFT,true)
	key(KEY_PERIOD,true)
	var command: Dictionary = o._source_arm_command(arm)
	check(float(command.activation) == 0.0 and float(command.twist) == 0.0 and int(command.grab_mode) == 0,
		"A real grabbed arm locks movement, repeated attack and twist")
	key(KEY_SPACE,true)
	key(KEY_SPACE,false)
	await create_timer(0.1).timeout
	check(o._actual_actor_grip(arm),"Space floor-suction changes do not release a real targeted carry")
	_release_inputs(o)
	key(KEY_CTRL,true)
	await physics_frame
	check(o.grips.is_empty() and not is_instance_valid(h.capture_source) and h.objective.capture_progress == 0.0,
		"Ctrl-alone releases real actor bindings and resets continuous capture")
	key(KEY_CTRL,false)
	# Normal reset isolates the release probe from the full physical hold.
	game.reset_round()
	if not await _fixture_start(game):
		_finish_contact()
		return
	key(KEY_SHIFT,true)
	key(o.ARM_KEYS[0],true)
	key(o.ARM_KEYS[7],true)
	check(await _wait_grips(o,2),"Multiple actual source-targeted arm grips participate in capture")
	var source: Node3D = h.capture_source
	var progress: float = h.objective.capture_progress
	if is_instance_valid(source):
		game._open_secret_fight()
		await create_timer(0.35).timeout
		check(h.capture_source == source and h.objective.capture_progress == progress,
			"Secret fight freezes an actual ongoing physical hold and its timer")
		game._close_secret_fight()
		await create_timer(0.1).timeout
		check(h.capture_source == source and h.objective.capture_progress >= progress,
			"Returning from secret fight preserves the same physical capture")
	else:
		check(false,"An actual capture is required for secret hold preservation")
	var deadline := Time.get_ticks_msec() + 30000
	while game.round_result == &"" and Time.get_ticks_msec() < deadline and o.fault.is_empty():
		await process_frame
	check(h.objective.result == &"captured" and game.round_result == &"captured",
		"Real contact and springs sustain the complete continuous ten-second win")
	check(game.result_label.text.contains("문어 승리"),"Physical capture victory is displayed")
	var bounds: Rect2 = game.result_label.get_global_rect()
	check(bounds.position.x >= 410.0 and bounds.end.x <= root.get_visible_rect().size.x,
		"Victory message stays inside the visible gameplay area")
	check(o.suspended and h.process_mode == Node.PROCESS_MODE_DISABLED,
		"A physically won round stops native and hunter simulation")
	_release_inputs(o)
	if "--capture-contact" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tools/octopus_capture_victory.png")
	_finish_contact()

func _finish_contact() -> void:
	var result := {"checks":checks,"failures":failures,"passed":failures.is_empty()}
	var file := FileAccess.open("res://.tools/octopus_contact_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("OCTOPUS_CONTACT_RESULT ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
