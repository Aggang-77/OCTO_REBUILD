extends SceneTree
var game: Node3D
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func ticks(count: int = 2) -> void:
	for i in range(count):
		await process_frame

func key(code: Key, control: bool = false, shift: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = control
	event.shift_pressed = shift
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func native_ticks(target_tick: int) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if game.octopus.geometry_ready and not game.octopus.resetting and not game.octopus.current.is_empty() and int(game.octopus.current.tick) >= target_tick:
			return true
		await process_frame
	return false

func _run() -> void:
	game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	check(await native_ticks(30), "Merged game starts before hidden mode entry")
	if game.octopus.current.is_empty():
		_finish()
		return
	var octopus = game.octopus
	var pid: int = octopus.child.pid
	game.hunter.set_character(1)
	game.character_picker.select(1)
	game.hunter.objective.health = 73.0
	key(KEY_F10)
	await ticks()
	check(not is_instance_valid(game._secret_layer), "Plain F10 does not reveal the hidden fight mode")
	key(KEY_F10, true)
	await ticks()
	check(not is_instance_valid(game._secret_layer), "Incomplete modifier chord cannot enter the hidden mode")
	key(KEY_F10, true, true, true)
	await ticks()
	check(not is_instance_valid(game._secret_layer), "Keyboard repeat cannot open the hidden mode")
	game.level_picker.grab_focus()
	key(KEY_F10, true, true)
	await ticks(4)
	check(is_instance_valid(game._secret_fight), "Secret chord opens the existing playable fight mode with GUI focus")
	if not is_instance_valid(game._secret_fight):
		_finish()
		return
	var fight: Node3D = game._secret_fight
	check(fight.player.character_index == 1, "Fight starts with the character selected in the chase")
	check(fight.player.fighter.control == &"player" and fight.rival.fighter.control == &"sparring", "Manual fighter and opponent AI are ready")
	check(fight.get_world_3d() != game.get_world_3d(), "Fight uses a separate physics world from the suspended map")
	check(PhysicsServer3D.space_is_active(fight.get_world_3d().space) and not PhysicsServer3D.space_is_active(game.get_world_3d().space),
		"Fight physics runs while the original chase physics space stays suspended")
	check(current_scene == game and octopus.child.pid == pid, "Opening the mode retains the chase scene and native process")
	await create_timer(0.15).timeout
	var frozen_tick: int = int(octopus.current.tick)
	var frozen_hunter: Vector3 = game.hunter.global_position
	var frozen_prop: Vector3 = game.arena.props[0].global_position
	var frozen_progress: float = game.hunter.objective.capture_progress
	await create_timer(0.3).timeout
	check(int(octopus.current.tick) == frozen_tick, "Native octopus does not step while fighting")
	check(game.hunter.global_position == frozen_hunter and game.arena.props[0].global_position == frozen_prop, "Background hunter and physical map props stay frozen")
	check(game.hunter.objective.capture_progress == frozen_progress and game.hunter.objective.health == 73.0, "Chase health and capture time are preserved")
	fight._ai_toggle.button_pressed = false
	var serial: int = fight.player.fighter.attack_serial
	key(KEY_U)
	await ticks(4)
	check(fight.player.fighter.attack_serial > serial, "Actual U key reaches only the embedded fighter elbow controls")
	check(int(octopus.current.tick) == frozen_tick, "The fighter elbow U key cannot extend an arm in the suspended chase")
	key(KEY_ESCAPE)
	await ticks()
	check(paused and fight._paused, "Embedded fight can pause through its actual keyboard input")
	key(KEY_F10)
	await ticks(4)
	check(not is_instance_valid(game._secret_layer) and not paused, "F10 returns from a paused fight to the running chase")
	check(PhysicsServer3D.space_is_active(game.get_world_3d().space), "Returning reactivates the original chase physics space")
	check(octopus.child.pid == pid and game.hunter.character_index == 1 and game.hunter.objective.health == 73.0, "Return preserves native process, selected hunter and round health")
	check(await native_ticks(frozen_tick + 8), "Original native world resumes instead of resetting")
	game._toggle_pause()
	check(paused, "Chase can be paused before entering the secret mode")
	key(KEY_F10, true, true)
	await ticks(4)
	check(is_instance_valid(game._secret_fight) and not paused, "Secret mode also opens from a paused chase")
	key(KEY_F10, true, true)
	await ticks(4)
	check(not is_instance_valid(game._secret_layer) and paused, "Returning restores the chase's prior paused state")
	game._toggle_pause()
	game._on_result(&"captured", 1000)
	key(KEY_F10, true, true)
	await ticks(4)
	key(KEY_F10)
	await ticks(4)
	check(game.round_result == &"captured" and octopus.suspended and game.hunter.process_mode == Node.PROCESS_MODE_DISABLED,
		"Returning preserves an already won round without restarting it")
	if "--capture-secret-fight" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		key(KEY_F10, true, true)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tools/secret_fight.png")
		key(KEY_F10)
		await ticks(4)
	_finish()

func _finish() -> void:
	paused = false
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://.tools/secret_fight_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("SECRET_FIGHT_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
