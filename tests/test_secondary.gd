extends SceneTree
var target: HunterTarget
var world: Node3D
var failures: Array[String]=[]
var checks: int=0
var visible_hinge_error: float=0.0
var visible_angle_error: float=0.0
var visible_samples: int=0

func _initialize() -> void:_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func ticks(count: int) -> void:
	for i in range(count):await physics_frame

func sample_visible_limits() -> void:
	var rig:=target.physics_rig
	if rig.ragdoll_weight<0.999:return
	var skeleton:=target.animation.skeleton
	visible_samples+=1
	for name in rig.part_order:
		var part: Dictionary=rig.parts[name]
		if not part.has("joint"):continue
		var parent: Dictionary=rig.parts[part["parent"]]
		var a:=skeleton.get_bone_global_pose(parent["bone"])*Transform3D(Basis.IDENTITY,parent["offset"])*(part["joint_frame_a"] as Transform3D)
		var b:=skeleton.get_bone_global_pose(part["bone"])*Transform3D(Basis.IDENTITY,part["offset"])*(part["joint_frame_b"] as Transform3D)
		var relative:=a.basis.inverse()*b.basis
		if part["joint"] is HingeJoint3D:
			visible_hinge_error=maxf(visible_hinge_error,acos(clampf(a.basis.z.dot(b.basis.z),-1,1)))
			var angle:=atan2(relative.x.y,relative.x.x)
			visible_angle_error=maxf(visible_angle_error,maxf(-angle,angle-part["joint_upper"].z))
		elif part["joint"] is Generic6DOFJoint3D:
			var angles:=rig._swing_twist_angles(relative.get_rotation_quaternion())
			for axis in range(3):visible_angle_error=maxf(visible_angle_error,maxf(part["joint_lower"][axis]-angles[axis],angles[axis]-part["joint_upper"][axis]))

func _run() -> void:
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	var floor_body:=StaticBody3D.new()
	world.add_child(floor_body)
	floor_body.position.y=-0.1
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(100,0.2,100)
	collision.shape=shape
	floor_body.add_child(collision)
	target=load("res://scenes/hunter_target.tscn").instantiate()
	world.add_child(target)
	await ticks(30)
	for index in range(3):
		target.set_character(index)
		target.reset_target(Vector3.ZERO)
		await ticks(60)
		var hair:=target.animation.hair_motion
		check(hair.strands.size()==24,"Character %d has eight independent three-part hair sections"%index)
		var hair_motion:=0.0
		var hair_root_error:=0.0
		var hair_angle_excess:=0.0
		for frame in range(90):
			target.visual.rotation.y=sin(frame*0.06)*0.65
			await physics_frame
			var skeleton:=target.animation.skeleton
			var head:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
			for strand in hair.strands:
				if not strand["root"]:continue
				var rest: Transform3D=head*strand["rest"]
				var tip: Vector3=strand["tip"]
				hair_motion=maxf(hair_motion,tip.distance_to(rest*strand["axis"]))
				var expected_direction: Vector3=rest.basis*strand["axis"]
				var angle:=expected_direction.normalized().angle_to((tip-rest.origin).normalized())
				hair_angle_excess=maxf(hair_angle_excess,angle-float(strand["maximum"]))
		print("HAIR_RESPONSE ",index," movement ",hair_motion," angle excess ",hair_angle_excess)
		check(hair_motion>0.002,"Character %d hair responds to turns instead of remaining rigid"%index)
		check(hair_angle_excess<0.02,"Character %d hair stays within its small strand angle limits"%index)
		check(target.animation.skirt_materials.size()>0,"Character %d entire skirt uses per-vertex leg collision"%index)
		var parameters_ok:=true
		for material in target.animation.skirt_materials:
			var starts: PackedVector4Array=material.get_shader_parameter("leg_start")
			var ends: PackedVector4Array=material.get_shader_parameter("leg_end")
			if starts.size()!=4 or ends.size()!=4:parameters_ok=false
			elif (Vector3(starts[0].x,starts[0].y,starts[0].z)-target.animation.cloth.leg_capsules[0]["start"]).length()>0.001:parameters_ok=false
		check(parameters_ok,"Character %d cloth collision follows the final physical leg positions"%index)
		target.reset_target(Vector3.ZERO)
		await ticks(30)
		var rig:=target.physics_rig
		visible_hinge_error=0.0
		visible_angle_error=0.0
		visible_samples=0
		rig.modifier.modification_processed.connect(sample_visible_limits)
		target.knock_down(Vector3(18,3,8))
		var smallest:=100.0
		var largest:=-100.0
		var sideways:=0.0
		var separation:=0.0
		var maximum_body_angle_excess:=0.0
		var worst_joint: Dictionary={}
		for frame in range(78):
			if frame==15:
				# Attempt both forbidden backward bending and sideways twisting.
				rig.get_part_body(&"right_shin").apply_torque_impulse(Vector3(-1.5,0.8,1.0))
				rig.get_part_body(&"left_forearm").apply_torque_impulse(Vector3(0.8,1.0,-0.7))
			await physics_frame
			for part in [&"left_shin",&"right_shin",&"left_forearm",&"right_forearm"]:
				var joint:=rig.get_joint_state(part)
				smallest=minf(smallest,joint["hinge_angle"])
				largest=maxf(largest,joint["hinge_angle"])
				sideways=maxf(sideways,joint["hinge_swing"])
				separation=maxf(separation,joint["anchor_error"])
			for part in [&"torso",&"head",&"left_thigh",&"right_thigh",&"left_hand",&"right_hand",&"left_foot",&"right_foot"]:
				var joint:=rig.get_joint_state(part)
				var angles: Vector3=joint["angles"]
				for axis in range(3):
					var excess: float=maxf(joint["lower"][axis]-angles[axis],angles[axis]-joint["upper"][axis])
					if excess>maximum_body_angle_excess:
						maximum_body_angle_excess=excess
						worst_joint={"part":part,"axis":axis,"angles":angles,"lower":joint["lower"],"upper":joint["upper"]}
		print("ANATOMY_FALL ",index," hinge degrees ",rad_to_deg(smallest)," .. ",rad_to_deg(largest)," sideways ",rad_to_deg(sideways)," separation ",separation," body excess ",rad_to_deg(maximum_body_angle_excess))
		print("WORST_JOINT ",worst_joint)
		check(smallest>deg_to_rad(-6.0) and largest<deg_to_rad(156.0),"Character %d elbows and knees resist reverse bending and over-folding"%index)
		# The finite-step rigid-body solver may briefly overshoot under a twisting
		# impulse. The rendered skeleton must still stay exactly within its limits.
		check(sideways<deg_to_rad(15.0),"Character %d physical elbow and knee axes stay bounded under twisting impacts"%index)
		check(visible_samples>40 and visible_hinge_error<0.002 and visible_angle_error<0.002,"Character %d visible body never bends past its anatomical joint limits"%index)
		rig.modifier.modification_processed.disconnect(sample_visible_limits)
		check(separation<0.05,"Character %d limbs stay connected during falling and twisting impacts"%index)
		check(maximum_body_angle_excess<deg_to_rad(8.0),"Character %d neck, spine, hips, wrists and ankles respect anatomical limits"%index)
		await ticks(250)
		check(not target.is_fallen(),"Character %d still gets up with anatomical joint limits"%index)
	var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
	FileAccess.open("res://.tools/secondary_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SECONDARY_TEST_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
