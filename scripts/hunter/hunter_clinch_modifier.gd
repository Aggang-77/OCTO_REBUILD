class_name HunterClinchModifier
extends SkeletonModifier3D
## Guide the palms to the cheeks before physical restraints are applied.
## Arm lengths stay fixed; a distant opponent cannot be pulled into a grab.
var driver: HunterAnimation

func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(driver):return
	var actor: HunterTarget=driver.get_parent()
	var fighter:=actor.fighter
	if not is_instance_valid(fighter):return
	if fighter.motion==&"clinched" and is_instance_valid(fighter.clinch_holder):
		var skeleton:=get_skeleton()
		for name in ["Spine","Spine2"]:
			var bone:=skeleton.find_bone(name)
			var pose:=skeleton.global_transform*skeleton.get_bone_global_pose(bone)
			pose.basis=Basis(actor.visual.global_basis.x,0.14)*pose.basis
			skeleton.set_bone_global_pose(bone,skeleton.global_transform.affine_inverse()*pose)
		return
	if fighter.motion!=&"attack" or fighter.move!=&"special_clinch":return
	var victim: HunterTarget=fighter.clinch_victim if is_instance_valid(fighter.clinch_victim) else fighter.opponent
	if not is_instance_valid(victim) or not is_instance_valid(victim.fighter) or not is_instance_valid(victim.fighter.boxes):return
	if actor.global_position.distance_to(victim.global_position)>1.10:return
	var head: Area3D=victim.fighter.boxes.hurtboxes[&"head"]["area"]
	var weight:=smoothstep(0.0,0.13,fighter.source_time)
	var point:=head.global_position
	if is_instance_valid(fighter.clinch_victim):point.y-=0.10*smoothstep(1.0,1.55,fighter.source_time)
	for side in ["Left","Right"]:
		var cheek:=point+actor.visual.global_basis.x*(-0.08 if side=="Left" else 0.08)
		cheek-=actor.visual.global_basis.z*0.035
		_reach(side,cheek,weight,actor.visual.global_basis.x)
	if is_instance_valid(fighter.clinch_victim):
		var knee_weight:=smoothstep(1.54,1.84,fighter.source_time)*(1.0-smoothstep(2.04,2.23,fighter.source_time))
		if knee_weight>0.001:
			var skeleton:=get_skeleton()
			var upper:=skeleton.find_bone("LeftUpLeg")
			var knee:=skeleton.find_bone("LeftLeg")
			var foot:=skeleton.find_bone("LeftFoot")
			var a:=skeleton.global_transform*skeleton.get_bone_global_pose(upper)
			var b:=skeleton.global_transform*skeleton.get_bone_global_pose(knee)
			var torso: Area3D=victim.fighter.boxes.hurtboxes[&"torso"]["area"]
			var target:=torso.global_position-actor.visual.global_basis.z*0.10
			_rotate(upper,knee,b.origin.lerp(target,knee_weight))
			var end:=skeleton.global_transform*skeleton.get_bone_global_pose(knee)
			# The lower leg folds down behind the rising knee, within hinge limits.
			_rotate(knee,foot,end.origin-Vector3.UP*0.30-actor.visual.global_basis.z*0.15)

func _reach(side: String, point: Vector3, weight: float, fallback: Vector3) -> void:
	var skeleton:=get_skeleton()
	var upper:=skeleton.find_bone(side+"Arm")
	var forearm:=skeleton.find_bone(side+"ForeArm")
	var hand:=skeleton.find_bone(side+"Hand")
	var a:=skeleton.global_transform*skeleton.get_bone_global_pose(upper)
	var b:=skeleton.global_transform*skeleton.get_bone_global_pose(forearm)
	var c:=skeleton.global_transform*skeleton.get_bone_global_pose(hand)
	var length_a:=a.origin.distance_to(b.origin)
	var length_b:=b.origin.distance_to(c.origin)
	var wrist:=c.origin.lerp(point,weight)
	var axis: Vector3=(wrist-a.origin).normalized()
	var distance:=clampf(wrist.distance_to(a.origin),0.04,(length_a+length_b)*0.985)
	var bend: Vector3=(b.origin-a.origin)-axis*(b.origin-a.origin).dot(axis)
	if bend.length()<0.01:bend=fallback
	var along: float=(length_a*length_a+distance*distance-length_b*length_b)/(2.0*distance)
	var elbow: Vector3=a.origin+axis*along+bend.normalized()*sqrt(maxf(0.0,length_a*length_a-along*along))
	_rotate(upper,forearm,elbow)
	_rotate(forearm,hand,a.origin+axis*distance)

func _rotate(bone: int, child: int, point: Vector3) -> void:
	var skeleton:=get_skeleton()
	var pose:=skeleton.global_transform*skeleton.get_bone_global_pose(bone)
	var endpoint:=skeleton.global_transform*skeleton.get_bone_global_pose(child).origin
	pose.basis=Basis(Quaternion((endpoint-pose.origin).normalized(),(point-pose.origin).normalized()))*pose.basis
	skeleton.set_bone_global_pose(bone,skeleton.global_transform.affine_inverse()*pose)
