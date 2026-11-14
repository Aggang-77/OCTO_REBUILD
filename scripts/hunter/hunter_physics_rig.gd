class_name HunterPhysicsRig
extends Node3D
## A motor-driven articulated rigid body. Motors have finite torque, not fixed poses.
signal grip_reaction(grip_id: int, force_on_character: Vector3, world_contact: Vector3)
signal grip_released(grip_id: int)
@export var enabled: bool = true:
	set(value):
		enabled=value
		for part in parts.values():
			var body: RigidBody3D=part["body"]
			body.freeze=not value
			body.collision_layer=target.physical_hitbox_layer if value else 0
			body.collision_mask=target.physical_collision_mask if value else 0
		if is_instance_valid(modifier):modifier.active=value
		if value and initialized:reset_pose()
@export var muscle_strength: float = 1.0
@export var debug_hitboxes: bool = false:
	set(value):
		debug_hitboxes=value
		for part in parts.values():
			if is_instance_valid(part.get("debug_mesh")):part["debug_mesh"].visible=value
var skeleton: Skeleton3D
var target: CharacterBody3D
var modifier: HunterPhysicsModifier
var parts: Dictionary = {}
var part_order: Array[StringName] = []
var grips: Dictionary = {}
var initialized: bool = false
var total_mass: float = 0.0
var last_character_force := Vector3.ZERO
var last_external_force := Vector3.ZERO
var _next_grip: int = 1
var _settle_frames: int = 0
var ragdoll_weight: float = 0.0
var motor_scale: float = 1.0
var cutting: bool = false
var _cut_exceptions: Array[Array] = []
var _balance_load_seconds: float = 0.0
var _knockdown_cooldown: float = 0.0

func setup(value: Skeleton3D, actor: CharacterBody3D) -> void:
	skeleton=value
	target=actor
	process_physics_priority=10
	var definitions: Array[Array] = [
		[&"pelvis","Hips","Spine",&"",12.0,0.115],
		[&"torso","Spine2","Neck",&"pelvis",15.0,0.125],
		[&"head","Head","",&"torso",4.0,0.105]]
	for side in ["left","right"]:
		var prefix := "Left" if side=="left" else "Right"
		definitions.append([StringName(side+"_upper_arm"),prefix+"Arm",prefix+"ForeArm",&"torso",2.0,0.045])
		definitions.append([StringName(side+"_forearm"),prefix+"ForeArm",prefix+"Hand",StringName(side+"_upper_arm"),1.4,0.038])
		definitions.append([StringName(side+"_hand"),prefix+"Hand",prefix+"HandMiddle1",StringName(side+"_forearm"),0.5,0.034])
		definitions.append([StringName(side+"_thigh"),prefix+"UpLeg",prefix+"Leg",&"pelvis",5.0,0.065])
		definitions.append([StringName(side+"_shin"),prefix+"Leg",prefix+"Foot",StringName(side+"_thigh"),3.0,0.05])
		definitions.append([StringName(side+"_foot"),prefix+"Foot",prefix+"ToeBase",StringName(side+"_shin"),0.8,0.035])
	for definition in definitions:_make_part(definition)
	for name in part_order:_make_joint(name)
	modifier=HunterPhysicsModifier.new()
	modifier.name="PhysicalPose"
	modifier.rig=self
	skeleton.add_child(modifier)
	skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	initialized=true
	reset_pose()

func _make_part(definition: Array) -> void:
	var name: StringName=definition[0]
	var bone := skeleton.find_bone(definition[1])
	if bone<0:return
	var pose := skeleton.get_bone_global_pose(bone)
	var endpoint := skeleton.find_bone(definition[2]) if definition[2]!="" else -1
	var end := skeleton.get_bone_global_pose(endpoint).origin if endpoint>=0 else pose.origin+Vector3.UP*0.13
	if definition[1]=="Head":end=pose.origin+Vector3.UP*0.13
	var offset := pose.affine_inverse()*((pose.origin+end)*0.5)
	var length := maxf(0.05,pose.origin.distance_to(end))
	var body := RigidBody3D.new()
	body.name=String(name)
	add_child(body)
	body.top_level=true
	body.global_transform=skeleton.global_transform*pose*Transform3D(Basis.IDENTITY,offset)
	body.mass=definition[4]
	body.collision_layer=target.physical_hitbox_layer
	body.collision_mask=target.physical_collision_mask
	body.continuous_cd=true
	body.can_sleep=false
	body.linear_damp=0.4
	body.angular_damp=0.4
	body.contact_monitor=true
	body.max_contacts_reported=4
	body.set_meta("hunter_part",name)
	body.set_meta("hunter_target",target)
	body.add_to_group("hunter_hitboxes")
	var shape := CapsuleShape3D.new()
	shape.radius=definition[5]
	shape.height=maxf(length+float(definition[5]),2.0*shape.radius)
	var collision := CollisionShape3D.new()
	collision.shape=shape
	var direction := (pose.basis.inverse()*(end-pose.origin)).normalized()
	collision.basis=Basis(Quaternion(Vector3.UP,direction))
	body.add_child(collision)
	var debug := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius=shape.radius
	mesh.height=shape.height
	debug.mesh=mesh
	debug.basis=collision.basis
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(0.25,0.95,0.8,0.23)
	debug.material_override=material
	debug.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug.visible=debug_hitboxes
	body.add_child(debug)
	var torque_capacity := 30.0
	if name==&"torso":torque_capacity=220.0
	elif name==&"head":torque_capacity=25.0
	elif "upper_arm" in name:torque_capacity=70.0
	elif "hand" in name:torque_capacity=10.0
	elif "thigh" in name:torque_capacity=160.0
	elif "shin" in name:torque_capacity=90.0
	elif "foot" in name:torque_capacity=25.0
	parts[name]={"body":body,"bone":bone,"offset":offset,"axis":direction,"parent":definition[3],"goal":body.global_transform,
		"previous_goal":body.global_transform,"goal_velocity":Vector3.ZERO,"length":length,
		"max_torque":torque_capacity,"reaction_torque":Vector3.ZERO,"error":0.0,"load":0.0,"debug_mesh":debug,
		"contact_left":0.0,"contact_weight":0.0,"pose_weight":0.0}
	part_order.append(name)
	total_mass+=body.mass

func _make_joint(name: StringName) -> void:
	var part: Dictionary=parts[name]
	if not parts.has(part["parent"]):return
	var body: RigidBody3D=part["body"]
	var parent_part: Dictionary=parts[part["parent"]]
	var parent: RigidBody3D=parent_part["body"]
	# Joint zero is the anatomical REST pose, not whichever animation happened
	# to be playing when the character was loaded.
	var rest := skeleton.get_bone_global_rest(part["bone"])
	var parent_rest := skeleton.get_bone_global_rest(parent_part["bone"])
	var body_rest := rest*Transform3D(Basis.IDENTITY,part["offset"])
	var parent_body_rest := parent_rest*Transform3D(Basis.IDENTITY,parent_part["offset"])
	var frame := Basis.IDENTITY
	var lower := Vector3(-40,-35,-25)
	var upper := Vector3(40,35,25)
	var hinge := "forearm" in name or "shin" in name
	var shoulder := "upper_arm" in name
	if hinge:
		var axis := Vector3.RIGHT
		if "forearm" in name:
			var direction: Vector3=parent_rest.basis*parent_part["axis"]
			axis=direction.cross(Vector3.BACK).normalized()
		var x: Vector3=Vector3.DOWN if "shin" in name else (parent_rest.basis*parent_part["axis"]).normalized()
		x=(x-axis*x.dot(axis)).normalized()
		frame=Basis(x,axis.cross(x).normalized(),axis)
		lower=Vector3(0,0,0)
		upper=Vector3(0,0,145 if "forearm" in name else 150)
	elif shoulder:
		var axis: Vector3=(rest.basis*part["axis"]).normalized()
		var y := axis.cross(Vector3.BACK).normalized()
		frame=Basis(axis,y,axis.cross(y).normalized())
	elif name==&"head":
		lower=Vector3(-45,-65,-30);upper=Vector3(45,65,30)
	elif "thigh" in name:
		lower=Vector3(-115,-30,-15 if "right" in name else -50)
		upper=Vector3(30,30,50 if "right" in name else 15)
	elif "hand" in name:
		var along: Vector3=(parent_rest.basis*parent_part["axis"]).normalized()
		var flex := along.cross(Vector3.BACK).normalized()
		frame=Basis(flex,along,flex.cross(along).normalized())
		lower=Vector3(-65,-65,-25);upper=Vector3(65,65,25)
	elif "foot" in name:
		lower=Vector3(-40,-10,-18);upper=Vector3(25,10,18)
	var anchor := Transform3D(frame.orthonormalized(),rest.origin)
	var local_a := parent_body_rest.affine_inverse()*anchor
	var local_b := body_rest.affine_inverse()*anchor
	var joint: Joint3D=HingeJoint3D.new() if hinge else (ConeTwistJoint3D.new() if shoulder else Generic6DOFJoint3D.new())
	joint.name=String(name)+"_Joint"
	add_child(joint)
	joint.top_level=true
	joint.global_transform=skeleton.global_transform*anchor
	joint.node_a=joint.get_path_to(parent)
	joint.node_b=joint.get_path_to(body)
	var rid := joint.get_rid()
	if hinge:
		PhysicsServer3D.joint_make_hinge(rid,parent.get_rid(),local_a,body.get_rid(),local_b)
		PhysicsServer3D.hinge_joint_set_flag(rid,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
		# Godot joint limits use clockwise angles, opposite Basis rotations.
		PhysicsServer3D.hinge_joint_set_param(rid,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,deg_to_rad(-upper.z+4.0))
		PhysicsServer3D.hinge_joint_set_param(rid,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,deg_to_rad(-lower.z))
	elif shoulder:
		PhysicsServer3D.joint_make_cone_twist(rid,parent.get_rid(),local_a,body.get_rid(),local_b)
		PhysicsServer3D.cone_twist_joint_set_param(rid,PhysicsServer3D.CONE_TWIST_JOINT_SWING_SPAN,deg_to_rad(105))
		PhysicsServer3D.cone_twist_joint_set_param(rid,PhysicsServer3D.CONE_TWIST_JOINT_TWIST_SPAN,deg_to_rad(65))
	else:
		PhysicsServer3D.joint_make_generic_6dof(rid,parent.get_rid(),local_a,body.get_rid(),local_b)
		for axis in range(3):
			PhysicsServer3D.generic_6dof_joint_set_flag(rid,axis,PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT,true)
			PhysicsServer3D.generic_6dof_joint_set_flag(rid,axis,PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_ANGULAR_LIMIT,true)
			PhysicsServer3D.generic_6dof_joint_set_param(rid,axis,PhysicsServer3D.G6DOF_JOINT_LINEAR_LOWER_LIMIT,0.0)
			PhysicsServer3D.generic_6dof_joint_set_param(rid,axis,PhysicsServer3D.G6DOF_JOINT_LINEAR_UPPER_LIMIT,0.0)
			# Leave a small guard band for the solver's finite-step impact error.
			var guard: float=minf(5.0,(upper[axis]-lower[axis])*0.15)
			PhysicsServer3D.generic_6dof_joint_set_param(rid,axis,PhysicsServer3D.G6DOF_JOINT_ANGULAR_LOWER_LIMIT,deg_to_rad(-upper[axis]+guard))
			PhysicsServer3D.generic_6dof_joint_set_param(rid,axis,PhysicsServer3D.G6DOF_JOINT_ANGULAR_UPPER_LIMIT,deg_to_rad(-lower[axis]-guard))
	part["joint"]=joint
	part["joint_frame_a"]=local_a
	part["joint_frame_b"]=local_b
	part["joint_lower"]=lower*PI/180.0
	part["joint_upper"]=upper*PI/180.0
	PhysicsServer3D.joint_disable_collisions_between_bodies(rid,true)

func get_joint_state(name: StringName) -> Dictionary:
	if not parts.has(name) or not parts[name].has("joint"):return {}
	var part: Dictionary=parts[name]
	var parent: RigidBody3D=parts[part["parent"]]["body"]
	var body: RigidBody3D=part["body"]
	var a: Transform3D=parent.global_transform*part["joint_frame_a"]
	var b: Transform3D=body.global_transform*part["joint_frame_b"]
	var relative:=a.basis.inverse()*b.basis
	return {"angles":_swing_twist_angles(relative.get_rotation_quaternion()),"hinge_angle":atan2(relative.x.y,relative.x.x),
		"hinge_swing":acos(clampf(a.basis.z.dot(b.basis.z),-1.0,1.0)),"anchor_error":a.origin.distance_to(b.origin),
		"lower":part["joint_lower"],"upper":part["joint_upper"]}

func _swing_twist_angles(rotation: Quaternion) -> Vector3:
	var q:=rotation.normalized()
	if q.w<0.0:q=-q
	var twist:=Quaternion(q.x,0,0,q.w)
	twist=twist.normalized() if twist.length_squared()>0.00001 else Quaternion.IDENTITY
	var swing:=q*twist.inverse()
	if swing.w<0.0:swing=-swing
	return Vector3(wrapf(2.0*atan2(twist.x,twist.w),-PI,PI),2.0*atan2(swing.y,swing.w),2.0*atan2(swing.z,swing.w))

func clamp_joint_rotation(name: StringName, relative: Basis) -> Basis:
	var part: Dictionary=parts[name]
	if part["joint"] is HingeJoint3D:
		var angle:=clampf(atan2(relative.x.y,relative.x.x),part["joint_lower"].z,part["joint_upper"].z)
		return Basis(Vector3.BACK,angle)
	var angles:=_swing_twist_angles(relative.get_rotation_quaternion())
	if part["joint"] is ConeTwistJoint3D:
		var q:=relative.get_rotation_quaternion().normalized()
		var twist:=Quaternion(q.x,0,0,q.w)
		twist=twist.normalized() if twist.length_squared()>0.00001 else Quaternion.IDENTITY
		var swing:=q*twist.inverse()
		if swing.w<0.0:swing=-swing
		var swing_angle:=swing.get_angle()
		if swing_angle>deg_to_rad(105):swing=Quaternion.IDENTITY.slerp(swing,deg_to_rad(105)/swing_angle)
		return Basis(swing*Quaternion(Vector3.RIGHT,clampf(angles.x,-deg_to_rad(32.5),deg_to_rad(32.5))))
	angles=angles.clamp(part["joint_lower"],part["joint_upper"])
	var swing:=Quaternion(0,sin(angles.y*0.5)*cos(angles.z*0.5),cos(angles.y*0.5)*sin(angles.z*0.5),cos(angles.y*0.5)*cos(angles.z*0.5)).normalized()
	return Basis(swing*Quaternion(Vector3.RIGHT,angles.x))

func constrain_bone_pose(name: StringName, bone_world: Transform3D, parent_bone_world: Transform3D) -> Transform3D:
	var part: Dictionary=parts[name]
	if not part.has("joint"):return bone_world
	var parent_part: Dictionary=parts[part["parent"]]
	var a:=parent_bone_world*Transform3D(Basis.IDENTITY,parent_part["offset"])*(part["joint_frame_a"] as Transform3D)
	var body:=bone_world*Transform3D(Basis.IDENTITY,part["offset"])
	var b:=body*(part["joint_frame_b"] as Transform3D)
	var relative:=clamp_joint_rotation(name,a.basis.inverse()*b.basis)
	var frame_b: Transform3D=part["joint_frame_b"]
	body.basis=a.basis*relative*frame_b.basis.inverse()
	body.origin=a.origin-body.basis*frame_b.origin
	return body*Transform3D(Basis.IDENTITY,-part["offset"])

func _guard_joint_velocities(delta: float) -> void:
	for name in part_order:
		var part: Dictionary=parts[name]
		if not part.has("joint") or (ragdoll_weight<=0.0 and get_pose_weight(name)<0.01):continue
		var body: RigidBody3D=part["body"]
		var parent: RigidBody3D=parts[part["parent"]]["body"]
		var a:=parent.global_transform*(part["joint_frame_a"] as Transform3D)
		var b:=body.global_transform*(part["joint_frame_b"] as Transform3D)
		var relative:=a.basis.inverse()*b.basis
		var angular:=a.basis.inverse()*(body.angular_velocity-parent.angular_velocity)
		var predicted:=Basis(Quaternion(angular.normalized(),angular.length()*delta))*relative if angular.length()>0.0001 else relative
		var allowed:=clamp_joint_rotation(name,predicted)
		var correction: Quaternion=(allowed*predicted.inverse()).get_rotation_quaternion().normalized()
		if correction.w<0.0:correction=-correction
		if correction.get_angle()<0.0001:continue
		var velocity_change:=a.basis*correction.get_axis()*correction.get_angle()/delta
		var inverse_a:=body.get_inverse_inertia_tensor()
		var inverse_b:=parent.get_inverse_inertia_tensor()
		var inverse_inertia:=Basis(inverse_a.x+inverse_b.x,inverse_a.y+inverse_b.y,inverse_a.z+inverse_b.z)
		if absf(inverse_inertia.determinant())<0.000001:continue
		var impulse: Vector3=(inverse_inertia.inverse()*velocity_change).limit_length(8.0)
		body.apply_torque_impulse(impulse)
		parent.apply_torque_impulse(-impulse)

func submit_animation(poses: Dictionary) -> void:
	for part in parts.values():
		if not poses.has(part["bone"]):continue
		var pose: Transform3D=poses[part["bone"]]
		pose.basis=pose.basis.orthonormalized()
		part["goal"]=pose*Transform3D(Basis.IDENTITY,part["offset"])

func reset_pose() -> void:
	clear_grips()
	set_cutting(false)
	ragdoll_weight=0.0
	motor_scale=1.0
	cutting=false
	_balance_load_seconds=0.0
	_knockdown_cooldown=1.0
	_settle_frames=3
	for part in parts.values():
		var body: RigidBody3D=part["body"]
		var pose := skeleton.global_transform*skeleton.get_bone_global_pose(part["bone"])
		var goal := pose*Transform3D(Basis.IDENTITY,part["offset"])
		part["goal"]=goal
		part["previous_goal"]=goal
		part["goal_velocity"]=Vector3.ZERO
		part["contact_left"]=0.0
		part["contact_weight"]=0.0
		part["pose_weight"]=0.0
		body.global_transform=_bounded_initial_pose(part,goal)
		body.linear_velocity=Vector3.ZERO
		body.angular_velocity=Vector3.ZERO
		body.sleeping=false
	last_character_force=Vector3.ZERO
	last_external_force=Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not initialized or not enabled:return
	_knockdown_cooldown=maxf(0.0,_knockdown_cooldown-delta)
	if _settle_frames>0:
		_settle_frames-=1
		for part in parts.values():
			part["body"].global_transform=_bounded_initial_pose(part,part["goal"])
			part["body"].linear_velocity=Vector3.ZERO
		return
	_update_contacts(delta)
	for part in parts.values():
		part["body"].collision_mask=target.physical_collision_mask | (target.physical_hitbox_layer if ragdoll_weight>0.01 else 0)
	var strength := muscle_strength*motor_scale
	for part in parts.values():part["reaction_torque"]=Vector3.ZERO
	for part in parts.values():
		var body: RigidBody3D=part["body"]
		var goal: Transform3D=part["goal"]
		var previous: Transform3D=part["previous_goal"]
		part["goal_velocity"]=(goal.origin-previous.origin)/maxf(delta,0.001)
		part["previous_goal"]=goal
		part["error"]=body.global_position.distance_to(goal.origin)
		part["load"]=0.0
		if part["parent"]==&"":
			var force: Vector3 = (goal.origin-body.global_position)*2200.0+(part["goal_velocity"]-body.linear_velocity)*220.0+Vector3.UP*total_mass*9.8
			body.apply_central_force(force.limit_length(1900.0*strength))
		else:
			var parent_part: Dictionary=parts[part["parent"]]
			var parent: RigidBody3D=parent_part["body"]
			# A finite joint actuator tracks the animated relative position. Its reaction
			# is applied to the parent at the SAME world point, conserving the pair's
			# net force and moment. It cannot teleport a limb through a restraint.
			var expected := goal.origin
			var relative_velocity: Vector3=part["goal_velocity"]
			var joint_force: Vector3=((expected-body.global_position)*body.mass*900.0+(relative_velocity-body.linear_velocity)*body.mass*38.0+Vector3.UP*body.mass*9.8)/(1.0+38.0*delta+900.0*delta*delta)
			joint_force=joint_force.limit_length(body.mass*75.0*strength)
			body.apply_central_force(joint_force)
			parent.apply_force(-joint_force,body.global_position-parent.global_position)
			parent_part["reaction_torque"]+=(body.global_position-parent.global_position).cross(-joint_force)
	# Distal-to-proximal computed torque compensates known internal actuator
	# reactions. External grip/contact loads are NOT cancelled by this feed-forward.
	for i in range(part_order.size()-1,-1,-1):
		var part: Dictionary=parts[part_order[i]]
		var body: RigidBody3D=part["body"]
		var goal: Transform3D=part["goal"]
		if part["parent"]==&"":
			_drive_rotation(body,null,goal.basis,delta,2200.0,25.0,400.0*strength,true,-part["reaction_torque"])
		else:
			var parent_part: Dictionary=parts[part["parent"]]
			var parent: RigidBody3D=parent_part["body"]
			var torso: bool=part_order[i]==&"torso"
			var torque:=_drive_rotation(body,parent,goal.basis,delta,1000.0 if torso else 100.0*body.mass,18.0 if torso else 1.8*body.mass,float(part["max_torque"])*strength,true,-part["reaction_torque"])
			parent_part["reaction_torque"]-=torque
	_tick_grips(delta)
	_guard_joint_velocities(delta)
	# Sustained loss of balance can knock the character down as well as an impact.
	var off_balance := not grips.is_empty() and float(parts[&"pelvis"]["error"])>0.38 and last_character_force.length()>180.0
	_balance_load_seconds = _balance_load_seconds+delta if off_balance else maxf(0.0,_balance_load_seconds-delta*2.0)
	if _balance_load_seconds>0.65 and _knockdown_cooldown<=0.0:
		_knockdown_cooldown=4.0
		target.knock_down.call_deferred(last_character_force.normalized()*10.0)

func _bounded_initial_pose(part: Dictionary, goal: Transform3D) -> Transform3D:
	if not part.has("joint"):return goal
	var parent_part: Dictionary=parts[part["parent"]]
	var parent_bone: Transform3D=parent_part["body"].global_transform*Transform3D(Basis.IDENTITY,-parent_part["offset"])
	var bone:=goal*Transform3D(Basis.IDENTITY,-part["offset"])
	var name: StringName=part["body"].name
	return constrain_bone_pose(name,bone,parent_bone)*Transform3D(Basis.IDENTITY,part["offset"])

func _update_contacts(delta: float) -> void:
	for name in part_order:
		var part: Dictionary=parts[name]
		part["contact_left"]=maxf(0.0,float(part["contact_left"])-delta)
		if part["contact_left"]<=0.0:part["contact_weight"]=0.0
		var body: RigidBody3D=part["body"]
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state==null:continue
		for i in range(state.get_contact_count()):
			var collider := state.get_contact_collider_object(i)
			var point := state.get_contact_collider_position(i)
			# Normal planted feet must not switch the running pose to simulation.
			if collider is StaticBody3D and point.y<=target.global_position.y+0.12:continue
			var severable: bool=is_instance_valid(collider) and collider.get_meta("hunter_severable",false)
			if cutting and severable and ("right_" in name or name==&"torso"):continue
			activate_part(name,0.20,1.0)
			var impulse := state.get_contact_impulse(i).length()
			if impulse>18.0 and _knockdown_cooldown<=0.0:
				_knockdown_cooldown=4.0
				target.knock_down.call_deferred(state.get_contact_impulse(i))
	for grip in grips.values():activate_part(grip["part"],0.18,1.0)
	for name in part_order:
		var part: Dictionary=parts[name]
		var desired: float=part["contact_weight"] if part["contact_left"]>0.0 else 0.0
		part["pose_weight"]=move_toward(part["pose_weight"],desired,delta*(14.0 if desired>part["pose_weight"] else 5.0))

func activate_part(name: StringName, seconds: float = 0.35, weight: float = 1.0) -> void:
	if not parts.has(name):return
	var part: Dictionary=parts[name]
	part["contact_left"]=maxf(part["contact_left"],seconds)
	part["contact_weight"]=maxf(part["contact_weight"],weight)
	# Carry some load to the supporting joints; unrelated limbs retain animation.
	var parent: StringName=part["parent"]
	if parts.has(parent):activate_part(parent,seconds,weight*0.45)

func get_pose_weight(name: StringName) -> float:
	return maxf(ragdoll_weight,float(parts[name]["pose_weight"])) if parts.has(name) else 0.0

func set_cutting(value: bool) -> void:
	cutting=value
	if not value:
		for pair in _cut_exceptions:
			if is_instance_valid(pair[0]) and is_instance_valid(pair[1]):pair[0].remove_collision_exception_with(pair[1])
		_cut_exceptions.clear()
		return
	for source in get_tree().get_nodes_in_group("hunter_threats"):
		if not source.get_threat_data(target).get("severable",false) or not source.has_method("get_physics_anchor"):continue
		var external: Node3D=source.get_physics_anchor()
		if external is PhysicsBody3D:
			for name in [&"right_upper_arm",&"right_forearm",&"right_hand"]:
				var body := get_part_body(name)
				body.add_collision_exception_with(external)
				_cut_exceptions.append([body,external])

func _drive_rotation(body: RigidBody3D, parent: RigidBody3D, desired: Basis, delta: float, stiffness: float, damping: float, maximum: float, world_space: bool = false, feed_forward: Vector3 = Vector3.ZERO) -> Vector3:
	var frame := parent.global_basis if parent and not world_space else Basis.IDENTITY
	var current := frame.inverse()*body.global_basis
	var error := (desired*current.inverse()).get_rotation_quaternion().normalized()
	if error.w<0.0:error=-error
	var angle := error.get_angle()
	var axis := error.get_axis() if angle>0.00001 else Vector3.ZERO
	var angular := body.angular_velocity-(parent.angular_velocity if parent and not world_space else Vector3.ZERO)
	# Implicit spring damping keeps small hand/forearm inertia stable at 60 Hz.
	var inverse_tensor := body.get_inverse_inertia_tensor()
	var inverse_mean := (inverse_tensor.x.x+inverse_tensor.y.y+inverse_tensor.z.z)/3.0
	var inertia := 1.0/maxf(inverse_mean,0.1)
	var torque := ((frame*axis)*angle*stiffness-angular*damping)/(1.0+damping*delta/inertia+stiffness*delta*delta/inertia)
	torque=(torque+feed_forward).limit_length(maximum)
	body.apply_torque(torque)
	if parent:parent.apply_torque(-torque)
	return torque

func get_part_body(part: StringName) -> RigidBody3D:
	return parts[part]["body"] if parts.has(part) else null

func set_part_mass(part: StringName, kilograms: float) -> void:
	var body:=get_part_body(part)
	if body:
		total_mass-=body.mass
		body.mass=maxf(0.05,kilograms)
		total_mass+=body.mass

func get_part_position(part: StringName) -> Vector3:
	var body := get_part_body(part)
	return body.global_position if body else target.global_position

func apply_part_impulse(part: StringName, impulse: Vector3, world_point: Vector3 = Vector3.INF) -> void:
	var body := get_part_body(part)
	if body:
		activate_part(part,0.55)
		if world_point==Vector3.INF:body.apply_central_impulse(impulse)
		else:body.apply_impulse(impulse,world_point-body.global_position)
		if impulse.length()>18.0 and _knockdown_cooldown<=0.0:
			_knockdown_cooldown=4.0
			target.knock_down(impulse,part,false)

func attach_grip(part: StringName, external: Node3D, world_contact: Vector3, stiffness: float = 1400.0, damping: float = 55.0, max_force: float = 400.0, break_distance: float = 1.5) -> int:
	var body := get_part_body(part)
	if body==null or not is_instance_valid(external):return -1
	var id := _next_grip
	_next_grip+=1
	grips[id]={"part":part,"body":body,"external":external,"local_a":body.to_local(world_contact),
		"local_b":external.to_local(world_contact),"stiffness":stiffness,"damping":damping,
		"max_force":max_force,"break_distance":break_distance,"force":Vector3.ZERO,
		"previous_b":world_contact,"distance":0.0}
	activate_part(part)
	return id

func _tick_grips(delta: float) -> void:
	last_character_force=Vector3.ZERO
	last_external_force=Vector3.ZERO
	for id in grips.keys():
		var grip: Dictionary=grips[id]
		var external: Node3D=grip["external"]
		if not is_instance_valid(external):
			release_grip(id)
			continue
		var body: RigidBody3D=grip["body"]
		var a := body.to_global(grip["local_a"])
		var b := external.to_global(grip["local_b"])
		var arm := a-body.global_position
		var velocity_a := body.linear_velocity+body.angular_velocity.cross(arm)
		var velocity_b: Vector3=(b-grip["previous_b"])/maxf(delta,0.001)
		if external is RigidBody3D:
			velocity_b=external.linear_velocity+external.angular_velocity.cross(b-external.global_position)
		grip["previous_b"]=b
		grip["distance"]=a.distance_to(b)
		if grip["distance"]>grip["break_distance"]:
			release_grip(id)
			continue
		var force: Vector3=((b-a)*float(grip["stiffness"])+(velocity_b-velocity_a)*float(grip["damping"])).limit_length(grip["max_force"])
		grip["force"]=force
		body.apply_force(force,arm)
		# Equal-and-opposite contact force, including its torque about each body's COM.
		if external is RigidBody3D:external.apply_force(-force,b-external.global_position)
		elif external is PhysicalBone3D:external.apply_impulse(-force*delta,b-external.global_position)
		elif external.has_method("receive_contact_force"):external.receive_contact_force(-force,b,delta)
		last_character_force+=force
		last_external_force-=force
		parts[grip["part"]]["load"]+=force.length()
		grip_reaction.emit(id,force,a)

func release_grip(id: int) -> void:
	if grips.erase(id):grip_released.emit(id)

func clear_grips() -> void:
	for id in grips.keys():release_grip(id)

func release_grips_for(external: Node3D) -> void:
	for id in grips.keys():
		if grips[id]["external"]==external:release_grip(id)

func get_root_feedback_velocity() -> Vector3:
	if not initialized or not enabled or _settle_frames>0:return Vector3.ZERO
	if ragdoll_weight<=0.0 and grips.is_empty() and get_pose_weight(&"pelvis")<0.001:return Vector3.ZERO
	var part: Dictionary=parts[&"pelvis"]
	var offset: Vector3=part["body"].global_position-(part["goal"] as Transform3D).origin
	offset.y=0.0
	return (offset*7.0).limit_length(5.0)

func get_mobility(part: StringName) -> float:
	if not enabled or not parts.has(part):return 1.0
	if grips.is_empty() and ragdoll_weight<=0.0 and get_pose_weight(part)<=0.001:return 1.0
	var item: Dictionary=parts[part]
	var load_ratio := float(item["load"])/180.0
	var error: float=item["error"]
	return clampf(1.0-load_ratio*0.45-error*1.5,0.12,1.0)

func get_action_efficiency(kind: StringName) -> float:
	if grips.is_empty():return 1.0
	if kind==&"slash":return sqrt(get_mobility(&"right_forearm")*get_mobility(&"right_hand"))
	return maxf(get_mobility(&"left_forearm"),get_mobility(&"right_forearm"))

func get_snapshot() -> Dictionary:
	return {"parts":parts.size(),"mass_kg":total_mass,"grips":grips.size(),
		"force_on_character":last_character_force,"force_on_external":last_external_force,
		"right_arm_mobility":get_mobility(&"right_forearm"),"left_arm_mobility":get_mobility(&"left_forearm"),
		"root_feedback":get_root_feedback_velocity(),"ragdoll_weight":ragdoll_weight,
		"contact_blend":get_pose_weight(&"pelvis")}
