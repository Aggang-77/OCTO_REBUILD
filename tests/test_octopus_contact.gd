extends SceneTree
## End-to-end physical capture fixture. Only the hunter spawn/speed are set up;
## native sites, collision queries, springs and the ten-second timer run normally.
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func _run() -> void:
	var game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var o = game.octopus
	var h: HunterTarget = game.hunter
	await create_timer(1.5).timeout
	if o.current.is_empty():
		check(false, "Native solver starts for physical capture fixture")
		_finish()
		return
	h.profile = h.profile.duplicate()
	h.profile.move_speed = 0.0
	var spawn: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[12])
	spawn.y = game.arena.terrain_height(spawn.x, spawn.z) + 0.04
	h.reset_target(spawn + Vector3(0, 0, 0.2))
	await create_timer(0.5).timeout
	o.dragging = true
	o.drag_kind = 2
	o.drag_index = 0
	var deadline := Time.get_ticks_msec() + 16000
	var contact_seen := false
	var multiple_contacts_seen := false
	var interruption_checked := false
	var source: Node3D
	while Time.get_ticks_msec() < deadline and game.round_result == &"":
		o.drag_target = h.physics_rig.get_part_position(&"torso") + Vector3(0, 0, -0.12)
		if is_instance_valid(h.capture_source):
			contact_seen = true
			o.dragging = false
			if not is_instance_valid(source):
				source = h.capture_source
			multiple_contacts_seen = multiple_contacts_seen or o.grips.size() >= 2
			if h.objective.capture_progress > 0.10 and not interruption_checked:
				var held_progress := h.objective.capture_progress
				var visit_started := Time.get_ticks_msec()
				game._open_secret_fight()
				await create_timer(0.35).timeout
				check(h.capture_source == source and h.objective.capture_progress == held_progress,
					"Secret fight freezes an actual ongoing physical capture")
				game._close_secret_fight()
				deadline += Time.get_ticks_msec() - visit_started
				await create_timer(0.1).timeout
				check(h.capture_source == source and h.objective.capture_progress >= held_progress,
					"Returning from secret fight continues the same physical hold and timer")
				interruption_checked = true
		await create_timer(0.1).timeout
	check(contact_seen, "Actual native tentacle contact automatically starts a physical hunter grip")
	check(interruption_checked, "Physical capture survives a secret-mode round trip")
	check(multiple_contacts_seen, "Multiple actual tentacle grips participate in capture")
	check(h.objective.result == &"captured" and game.round_result == &"captured",
		"Real contact and springs maintain a ten-second hold and win the game")
	check(game.result_label.text.contains("문어 승리"), "Physical capture victory is shown in the game UI")
	var message_rect: Rect2 = game.result_label.get_global_rect()
	check(message_rect.position.x >= 410.0 and message_rect.end.x <= root.get_visible_rect().size.x,
		"Victory message stays inside the visible gameplay area")
	check(o.suspended and h.process_mode == Node.PROCESS_MODE_DISABLED,
		"The won round stops octopus and hunter simulation")
	if "--capture-contact" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tools/octopus_capture_victory.png")
	_finish()

func _finish() -> void:
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://.tools/octopus_contact_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("OCTOPUS_CONTACT_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
