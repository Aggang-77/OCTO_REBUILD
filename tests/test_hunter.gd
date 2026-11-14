extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 --script tests/test_hunter.gd
var failures: Array[String] = []
var checks: int = 0
var attacks: Array[StringName] = []
var target: HunterTarget
var threat: HunterThreat
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func ticks(count: int, follow_distance: float = -1.0) -> void:
	for i in range(count):
		if follow_distance > 0.0:
			threat.position = target.position + Vector3(0,0,follow_distance)
		await physics_frame

func fresh(level: int) -> void:
	target.set_difficulty(level)
	target.safe_zone = null
	target.arena_bounds_enabled = false
	target.reset_target(Vector3.ZERO)
	threat.reset_threat()
	threat.position = Vector3(0,0,3)
	threat.severable = true
	attacks.clear()

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	world.add_child(floor_body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(200,0.2,200)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.1
	target = load("res://scenes/hunter_target.tscn").instantiate()
	world.add_child(target)
	threat = HunterThreat.new()
	threat.aim_offset=Vector3.UP*0.95
	threat.health = 80.0
	world.add_child(threat)
	threat.active = false
	target.attack_landed.connect(func(kind: StringName, _source: Node3D, _damage: float): attacks.append(kind))
	await ticks(12)
	for clip in ["idle","jog","sprint","elbow","slash","captured","fall","get_up","stop","turn_run","look","combo"]:
		check(target.animation._clips.has(clip), "Imported animation: " + clip)
	check(target.animation.skeleton != null, "Skinned selected character skeleton loaded")
	check(target.animation.tree != null and target.animation.tree.active, "AnimationTree running")
	for index in range(3):
		target.set_character(index)
		await ticks(3)
		check(target.animation.skeleton.find_bone("RightHand")>=0, "Character %d has retargeted right hand" % index)
		check(target.animation._clips.size()>=12, "Character %d has the complete motion set" % index)
		check(is_instance_valid(target.animation.weapon_socket) and target.animation.weapon_socket.get_parent()==target.animation.skeleton, "Character %d sword is attached to the hand skeleton" % index)
		check(target.animation.weapon.blade_tip().distance_to(target.animation.weapon.blade_base())>0.7, "Character %d blade extends out from its grip" % index)
		check(target.get_node("Visual").get_child_count()==1, "Character switching replaces the previous model")
		var skeleton := target.animation.skeleton
		var hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
		var foot := skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
		var hand := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
		check(foot.y < hips.y-0.35, "Character %d legs point below the hips in idle" % index)
		check(hand.y < hips.y+0.45, "Character %d arms relax below the shoulders" % index)
	target.set_character(0)
	check(target.animation.play_action(&"slash")<0.75, "Sword slash completes in under 0.75 seconds")
	check(target.animation.action_hit_time(&"slash")<0.25, "Sword hit timing follows the faster animation")
	target.animation.cancel_action()
	fresh(1)
	await ticks(120, 3.0)
	check(Vector2(target.velocity.x,target.velocity.z).length() <= 2.05, "Level 1 obeys slow movement speed")
	check(target.position.length() > 1.0, "Level 1 autonomously flees the threat")
	check(attacks.is_empty(), "Level 1 never attacks")
	check(target.try_capture(threat), "Valid contact can capture a target")
	await ticks(510)
	check(target.objective.result == &"captured", "Level 1 sustained capture completes octopus objective")
	check(attacks.is_empty(), "Level 1 does not counterattack while captured")
	fresh(2)
	await ticks(90,3.0)
	check(Vector2(target.velocity.x,target.velocity.z).length() > 4.0, "Level 2 flees quickly")
	check(attacks.is_empty(), "Level 2 does not attack during free movement")
	check(target.try_capture(threat), "Level 2 can be captured")
	await ticks(170)
	check(&"elbow" in attacks, "Level 2 uses supplied elbow action after capture")
	check(not is_instance_valid(target.capture_source), "Elbow breaks a normal restraint")
	check(target.objective.result == &"", "Brief capture does not grant victory")
	fresh(2)
	target.try_capture(threat,3.0)
	await ticks(170)
	check(is_instance_valid(target.capture_source), "Strong restraints resist an insufficient elbow escape")
	fresh(3)
	await ticks(260,1.2)
	check(&"slash" in attacks, "Level 3 proactively slashes nearby tentacles")
	check(threat.health <= 0.0 and not threat.active, "Sword damage can sever a tentacle")
	fresh(3)
	threat.severable = false
	await ticks(100,1.5)
	check(not (&"slash" in attacks), "Non-severable threats are not sword targets")
	fresh(3)
	await ticks(18,1.8)
	threat.position = Vector3(0,0,20)
	await ticks(70)
	check(threat.health == 80.0, "Sword rechecks range at impact")
	fresh(1)
	var wall := StaticBody3D.new()
	world.add_child(wall)
	wall.position = Vector3(0,1,1.5)
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(5,2,0.3)
	var wall_collision := CollisionShape3D.new()
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	await ticks(70)
	check(target.perceived_threats.is_empty(), "Solid walls block threat line of sight")
	wall.queue_free()
	await ticks(2)
	fresh(1)
	wall = StaticBody3D.new()
	world.add_child(wall)
	wall.position = Vector3(0,1,-1.5)
	wall_collision = CollisionShape3D.new()
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	await ticks(180,3.0)
	check(absf(target.position.x)>0.6, "Flee planner steers around an obstacle behind the target")
	check(target.position.z > -1.1 or absf(target.position.x)>2.7, "Flee movement does not cross a solid obstacle")
	wall.queue_free()
	await ticks(2)
	fresh(1)
	var second := HunterThreat.new()
	world.add_child(second)
	second.position=Vector3(-2,0,0)
	await ticks(100,3.0)
	check(target.perceived_threats.size()==2, "Planner considers multiple independent tentacles")
	second.queue_free()
	await ticks(2)
	fresh(1)
	target.try_capture(threat)
	threat.active = false
	await ticks(3)
	check(not is_instance_valid(target.capture_source), "Inactive capture source releases its target")
	fresh(1)
	target.apply_damage(100.0)
	check(target.incapacitated, "Health depletion incapacitates target")
	check(target.objective.result == &"", "Damage alone does not complete capture objective")
	target.try_capture(threat)
	await ticks(500)
	check(target.objective.result == &"captured", "Incapacitated target can still fulfill capture objective")
	fresh(1)
	threat.active = false
	var exit := Node3D.new()
	world.add_child(exit)
	target.safe_zone = exit
	await ticks(110)
	check(target.objective.result == &"escaped", "Safe-zone hold resolves target escape")
	var snapshot := target.get_target_data()
	check(snapshot.has("target_id") and snapshot.has("capture_score") and snapshot.has("velocity"), "Integration snapshot includes identity, score and motion")
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty()}
	var file := FileAccess.open("res://.tools/test_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("HUNTER_TEST_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
