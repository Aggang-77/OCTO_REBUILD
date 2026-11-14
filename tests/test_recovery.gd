extends SceneTree
## Regression: the get-up OneShot faded back to the down animation before idle.

var failures: Array[String] = []
var checks := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func ticks(count: int) -> void:
	for i in range(count): await physics_frame

func recovery_case(lab: Node3D, character: int, scene_name: String) -> void:
	lab._select_character(character)
	await ticks(90)
	var actor: HunterTarget = lab.hunter
	var rig := actor.physics_rig
	var pelvis_bone: int = rig.parts[&"pelvis"]["bone"]
	var standing_height := (rig.parts[&"pelvis"]["goal"] as Transform3D).origin.y - actor.position.y
	var standing_pose := actor.animation.skeleton.global_transform * actor.animation.skeleton.get_bone_global_pose(pelvis_bone)
	var standing_visible := standing_pose.origin.y - actor.position.y
	var transitions: Array[StringName] = []
	var on_state := func(_old: StringName, state: StringName): transitions.append(state)
	actor.state_changed.connect(on_state)
	check(actor.knock_down(Vector3(16, 2, 4)), "%s character %d enters one real knockdown" % [scene_name, character])
	var minimum_goal := INF
	var minimum_visible := INF
	var sampled_tail := 0
	var stood_up := false
	var after_standing := 0
	for i in range(480):
		await physics_frame
		# Inspect the final handoff, after the authored kneeling portion is over.
		var in_tail := actor._recover_left > 0 and actor._recover_left / actor._recover_duration < 0.12
		if not actor.is_fallen() and &"getting_up" in transitions:
			stood_up = true
			if after_standing < 60: in_tail = true
			after_standing += 1
		if in_tail:
			sampled_tail += 1
			minimum_goal = minf(minimum_goal, (rig.parts[&"pelvis"]["goal"] as Transform3D).origin.y - actor.position.y)
			var visible_pose := actor.animation.skeleton.global_transform * actor.animation.skeleton.get_bone_global_pose(pelvis_bone)
			minimum_visible = minf(minimum_visible, visible_pose.origin.y - actor.position.y)
	actor.state_changed.disconnect(on_state)
	var label := "%s character %d" % [scene_name, character]
	check(transitions.count(&"falling") == 1 and transitions.count(&"getting_up") == 1, label + " does not restart the fall/get-up state")
	check(stood_up and actor.state == &"idle" and not actor.is_fallen(), label + " completes recovery and stays standing")
	check(sampled_tail > 20 and minimum_goal > standing_height * 0.80,
		label + " never blends the get-up tail back to the fallen animation")
	check(minimum_visible > standing_visible * 0.80, label + " has no visible collapse at the recovery handoff")
	check(not actor.animation.tree.get("parameters/Strike/active") and actor.animation._mode == &"locomotion",
		label + " clears the get-up OneShot onto locomotion")
	measurements.append({"scene": scene_name, "character": character, "standing_height": standing_height, "standing_visible_height": standing_visible,
		"minimum_goal_height": minimum_goal, "minimum_visible_height": minimum_visible, "transitions": transitions})
	# Fixing a transition must not suppress a fresh, sufficiently strong impact.
	rig.apply_part_impulse(&"torso", Vector3(24, 2, 0))
	check(actor.is_fallen(), label + " still reacts to a new physical knockdown")

func _run() -> void:
	for scene_name in ["hunter_lab", "tidal_hunter_lab"]:
		var lab: Node3D = load("res://scenes/%s.tscn" % scene_name).instantiate()
		root.add_child(lab)
		current_scene = lab
		for character in range(3):
			await recovery_case(lab, character, scene_name)
		lab.queue_free()
		await ticks(3)
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "measurements": measurements}
	FileAccess.open("res://.tools/recovery_results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("RECOVERY_TEST_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
