extends SceneTree
var target: HunterTarget
var world: Node3D
var threat: HunterThreat
var failures: Array[String]=[]
var checks: int=0
var rendered_error: float=0.0

func _initialize() -> void:_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func ticks(count: int) -> void:
	for i in range(count):await physics_frame

func sample_final_pose() -> void:
	var rig := target.physics_rig
	var skeleton := target.animation.skeleton
	for name in rig.part_order:
		var part: Dictionary=rig.parts[name]
		var expected: Transform3D=part["goal"]*Transform3D(Basis.IDENTITY,-part["offset"])
		var actual := skeleton.global_transform*skeleton.get_bone_global_pose(part["bone"])
		rendered_error=maxf(rendered_error,actual.origin.distance_to(expected.origin))
		rendered_error=maxf(rendered_error,actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()))

func _run() -> void:
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	var floor_body:=StaticBody3D.new()
	world.add_child(floor_body)
	floor_body.position.y=-0.1
	var floor_collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(200,0.2,200)
	floor_collision.shape=shape
	floor_body.add_child(floor_collision)
	target=load("res://scenes/hunter_target.tscn").instantiate()
	world.add_child(target)
	threat=HunterThreat.new()
	threat.health=80.0
	threat.active=false
	world.add_child(threat)
	await ticks(30)
	# Compare the actual final skeleton against the pre-physics animation while
	# running freely. The floor is present, so ordinary foot contact is exercised.
	target.set_difficulty(2)
	target.arena_bounds_enabled=false
	target.animation.skeleton.skeleton_updated.connect(sample_final_pose)
	for i in range(150):
		threat.global_position=target.global_position+Vector3(0,0,3)
		threat.active=true
		await physics_frame
	check(rendered_error<0.001,"Free running retains the authored body pose exactly")
	check(target.physics_rig.get_root_feedback_velocity().length()<0.001,"Unrestrained running has no simulation drag on the AI root")
	check(not target.is_fallen(),"Ordinary running and planted feet do not cause a knockdown")
	target.animation.skeleton.skeleton_updated.disconnect(sample_final_pose)
	threat.active=false
	for index in range(3):
		target.set_character(index)
		target.set_difficulty(3)
		target.reset_target(Vector3.ZERO)
		await ticks(45)
		check(target.animation.cloth.panels.size()==16,"Character %d has separate mid-skirt and hem simulation"%index)
		for height in [0.45,0.95,1.55]:
			target.reset_target(Vector3.ZERO)
			threat.reset_threat()
			threat.global_position=Vector3(0,0,1.4)
			threat.aim_offset=Vector3.UP*height
			target._decision_left=10.0
			target._start_action(&"slash",threat)
			await ticks(43)
			print("HEIGHT_HIT ",index," / ",height," HP ",threat.health," pitch ",target.animation.aim.pitch)
			check(is_equal_approx(threat.health,35.0),"Character %d steel blade hits height %.2f exactly once per swing"%[index,height])
			threat.active=false
		# Actual gravity and rigid-body contacts must put the torso on the floor.
		target.reset_target(Vector3.ZERO)
		await ticks(30)
		check(target.knock_down(Vector3(16,2,4)),"Character %d can enter physical knockdown"%index)
		await ticks(70)
		check(target.physics_rig.get_part_position(&"torso").y<0.55,"Character %d falls onto its physical body"%index)
		var finite_cloth:=true
		for panel in target.animation.cloth.panels:
			if not (panel["tip"] as Vector3).is_finite():finite_cloth=false
		check(finite_cloth,"Character %d skirt remains stable through a fall"%index)
		await ticks(240)
		check(not target.is_fallen() and target.physics_rig.get_part_position(&"torso").y>0.95,"Character %d recovers and stands after knockdown"%index)
	# Complete a whole slash. Its oldest points must remain until the entire
	# effect fades, and the mesh must apply one opacity to the entire sheet.
	target.reset_target(Vector3.ZERO)
	threat.reset_threat()
	threat.global_position=Vector3(0,0,1.3)
	threat.aim_offset=Vector3.UP*0.95
	target._decision_left=10.0
	target._start_action(&"slash",threat)
	var weapon:=target.animation.weapon
	await ticks(38)
	var sample_count:=weapon.samples.size()
	var first_point: Vector3=weapon.samples[0]["tip"] if sample_count>0 else Vector3.INF
	check(sample_count>12,"A complete slash leaves a long continuous trail")
	threat.active=false
	await ticks(12)
	check(weapon.samples.size()==sample_count and weapon.samples[0]["tip"]==first_point,"Old and new points remain together while the stroke fades")
	var opacity:=weapon.get_stroke_opacity(weapon._stroke)
	check(opacity>0.0 and opacity<1.0,"Completed stroke fades gradually as one effect")
	var uniform_opacity:=weapon.trail_mesh.get_surface_count()>0
	if uniform_opacity:
		var colors: PackedColorArray=weapon.trail_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		# ImmediateMesh packs vertex colors to 8-bit channels. Compare all sheet
		# vertices to one another, allowing packing precision against the fade clock.
		if absf(colors[0].a-opacity*HunterWeapon.TRAIL_ALPHA)>0.005:uniform_opacity=false
		for i in range(colors.size()):
			var expected:=colors[0 if i%12<6 else 6].a
			if absf(colors[i].a-expected)>0.001:uniform_opacity=false
	check(uniform_opacity,"Every point of a swing uses the same fade, without a disappearing tail")
	await ticks(45)
	check(weapon.samples.is_empty() and weapon.trail_mesh.get_surface_count()==0,"The whole trail disappears cleanly after its fade")
	# Strong impulses and held bodies must remain compatible with knockdown.
	target.reset_target(Vector3.ZERO)
	await ticks(70)
	target.physics_rig.apply_part_impulse(&"torso",Vector3(24,2,0))
	check(target.is_fallen(),"A sufficiently large actual impact triggers falling automatically")
	var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
	FileAccess.open("res://.tools/motion_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MOTION_TEST_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
