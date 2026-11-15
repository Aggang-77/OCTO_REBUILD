extends SceneTree
## End-to-end physical capture fixture with an initial hunter spawn/speed,
## ordinary key inputs and a bounded force-driven approach. Native sites, real
## collision queries, spring holds and the ten-second timer run normally.
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

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	var game = load("res://scenes/octopus_game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var o = game.octopus
	var h: HunterTarget = game.hunter
	var startup_deadline := Time.get_ticks_msec() + 7000
	while not o.geometry_ready and o.fault.is_empty() and Time.get_ticks_msec() < startup_deadline:
		await process_frame
	if o.current.is_empty() or not o.geometry_ready:
		check(false, "Native solver starts for physical capture fixture")
		_finish()
		return
	# A precise force-driven contact fixture uses a stiff spring; its force
	# cap remains the production 20 N base scaled by physical mass.
	o.drag_stiffness = 1000.0
	h.profile = h.profile.duplicate()
	h.profile.move_speed = 0.0
	var spawn: Vector3 = o.vec(o.current.animals[0].arms[0].nodes[12])
	spawn.y = game.arena.terrain_height(spawn.x, spawn.z) + 0.04
	h.reset_target(spawn + Vector3(0, 0, 0.2))
	await create_timer(0.5).timeout
	# Use the real global release control during approach so an old terrain
	# plant cannot prevent a bounded tip force from reaching the hunter.
	key(KEY_SPACE, true)
	for code in o.EXTEND_KEYS:
		key(code, true)
	o.dragging = true
	o.drag_kind = 2
	for approach_arm in [1, 0]:
		o.drag_index = approach_arm
		var approach_deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < approach_deadline:
			o.drag_target = h.physics_rig.get_part_position(&"left_foot" if approach_arm == 1 else &"right_foot") + Vector3(0, 0.07, 0)
			await create_timer(0.05).timeout
	for code in o.EXTEND_KEYS:
		key(code, false)
	key(KEY_SPACE, false)
	await create_timer(0.10).timeout
	for code in o.EXTEND_KEYS:
		key(code, true)
	o.drag_index = 0
	var deadline := Time.get_ticks_msec() + 30000
	var contact_seen := false
	var multiple_contacts_seen := false
	var interruption_checked := false
	var source: Node3D
	var carry_checked := false
	var secondary_prepared := false
	var contact_samples := {"broad": 0, "narrow": 0, "facing": 0, "best_gap": INF, "best_face": -1.0}
	while Time.get_ticks_msec() < deadline and game.round_result == &"":
		_inspect_contacts(o, h, contact_samples)
		o.drag_target = h.physics_rig.get_part_position(&"right_foot") + Vector3(0, 0.07, 0)
		if is_instance_valid(h.capture_source):
			contact_seen = true
			# Establish the second genuine contact with another bounded tip
			# force. Existing carrying arms are never repositioned by the fixture.
			o.dragging = o.grips.size() < 2
			if o.dragging:
				o.drag_index = 1 if not o.grips.has(1) else 7
				o.drag_target = h.physics_rig.get_part_position(&"left_foot") + Vector3(0, 0.10, 0)
			if not is_instance_valid(source):
				source = h.capture_source
			multiple_contacts_seen = multiple_contacts_seen or o.grips.size() >= 2
			if h.objective.capture_progress > 0.05 and not carry_checked:
				var held_arm: int = o.grips.keys()[0]
				key(o.EXTEND_KEYS[held_arm], false)
				await create_timer(0.15).timeout
				check(o.grips.has(held_arm) and int(o.current.animals[0].arms[held_arm].phase) == 4,
					"Releasing the extend key preserves an actual hunter grip in native carry phase")
				carry_checked = true
			if carry_checked and not secondary_prepared and o.grips.size() < 2:
				# Release this arm's old terrain plant, let the peel finish, then
				# start a fresh real-contact attempt near the hunter's foot.
				var secondary: int = o.drag_index
				key(o.EXTEND_KEYS[secondary], false)
				await create_timer(1.0).timeout
				key(o.EXTEND_KEYS[secondary], true)
				secondary_prepared = true
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
	print("PHYSICAL_CONTACT_DIAGNOSTIC ", contact_samples, " candidates=", o.grip_candidates, " grips=", o.grips, " tip=", o.current.animals[0].arms[0].nodes[-1], " target=", o.drag_target, " torso=", h.physics_rig.get_part_position(&"torso"), " capture_seconds=", h.objective.capture_progress * 10.0)
	check(contact_seen, "Held extend plus stable native sucker-face contact starts a physical hunter grip")
	check(carry_checked, "Physical fixture exercises carry after releasing extend")
	for code in o.EXTEND_KEYS:
		key(code, false)
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

func _inspect_contacts(o: Node3D, h: HunterTarget, stats: Dictionary) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	query.shape = shape
	query.collision_mask = 4
	query.margin = 0.001
	var space := o.get_world_3d().direct_space_state
	for arm in range(8):
		var state: Dictionary = o.current.animals[0].arms[arm]
		for site in range(4, 17):
			var radius: float = state.contact_radii[site]
			shape.radius = radius + 0.025 * o.creature_scale
			var center: Vector3 = o.vec(state.nodes[site])
			query.transform.origin = center
			var info := space.get_rest_info(query)
			if info.is_empty():
				continue
			var hitbox = instance_from_id(info.collider_id)
			if not hitbox is RigidBody3D or hitbox.get_meta("hunter_target", null) != h:
				continue
			stats.broad += 1
			var gap: float = center.distance_to(info.point) - radius
			var facing: float = o.vec(state.sucker_directions[site]).dot(-info.normal)
			stats.best_gap = minf(stats.best_gap, gap)
			stats.best_face = maxf(stats.best_face, facing)
			if gap <= 0.008 * o.creature_scale:
				stats.narrow += 1
				if facing >= 0.3:
					stats.facing += 1

func _finish() -> void:
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://.tools/octopus_contact_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("OCTOPUS_CONTACT_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
