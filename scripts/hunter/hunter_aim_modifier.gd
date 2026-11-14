class_name HunterAimModifier
extends SkeletonModifier3D
## Aim is applied to the animation BEFORE physical restraints limit the actual arm.
var driver: HunterAnimation
var aim_source: Node3D
var duration: float = 0.0
var elapsed: float = -1.0
var pitch: float = 0.0
var yaw: float = 0.0
var last_target: Vector3

func begin(source: Node3D, seconds: float) -> void:
	aim_source=source
	duration=seconds
	elapsed=0.0

func stop() -> void:
	elapsed=-1.0
	aim_source=null

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton==null or not is_instance_valid(driver):return
	var desired_pitch:=0.0
	var desired_yaw:=0.0
	var active_swing := elapsed>=0.0 and is_instance_valid(aim_source)
	if active_swing:
		elapsed+=delta
		last_target=aim_source.get_cut_position() if aim_source.has_method("get_cut_position") else aim_source.global_position
		var chest := skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Spine2")).origin
		var local: Vector3=driver.get_parent().visual.global_basis.inverse()*(last_target-chest)
		desired_pitch=-clampf(atan2(local.y,maxf(Vector2(local.x,local.z).length(),0.25)),deg_to_rad(-48),deg_to_rad(42))
		desired_yaw=clampf(atan2(local.x,local.z),-0.5,0.5)
		if elapsed>duration:stop()
	pitch=lerpf(pitch,desired_pitch,1.0-exp(-delta*18.0))
	yaw=lerpf(yaw,desired_yaw,1.0-exp(-delta*18.0))
	var world_frame: Basis=driver.get_parent().visual.global_basis
	var inverse := skeleton.global_transform.affine_inverse()
	for entry in [["Spine",0.35],["Spine2",0.65]]:
		var bone := skeleton.find_bone(entry[0])
		if bone<0:continue
		var pose := skeleton.global_transform*skeleton.get_bone_global_pose(bone)
		pose.basis=Basis(world_frame.y,yaw*entry[1])*Basis(world_frame.x,pitch*entry[1])*pose.basis
		skeleton.set_bone_global_pose(bone,inverse*pose)
	if not active_swing:return
	# Preserve wind-up and follow-through. Guide the blade through the actual
	# contact point only around the strike, using the authored elbow bend plane.
	var phase := elapsed/maxf(duration,0.01)
	var weight := smoothstep(0.08,0.26,phase)*(1.0-smoothstep(0.60,0.84,phase))
	if weight<0.001:return
	var upper := skeleton.find_bone("RightArm")
	var forearm := skeleton.find_bone("RightForeArm")
	var hand := skeleton.find_bone("RightHand")
	var a := skeleton.global_transform*skeleton.get_bone_global_pose(upper)
	var b := skeleton.global_transform*skeleton.get_bone_global_pose(forearm)
	var c := skeleton.global_transform*skeleton.get_bone_global_pose(hand)
	var length_a := a.origin.distance_to(b.origin)
	var length_b := b.origin.distance_to(c.origin)
	var direction := (last_target-a.origin).normalized()
	# The tip sweeps across the target rather than remaining pointed at it.
	var arc := world_frame.x*lerpf(0.35,-0.35,clampf((phase-0.20)/0.40,0,1))
	var wrist := last_target-direction*0.56+arc
	wrist=c.origin.lerp(wrist,weight)
	var line := wrist-a.origin
	var distance := clampf(line.length(),0.025,(length_a+length_b)*0.985)
	var axis := line.normalized()
	var bend := (b.origin-a.origin)-axis*(b.origin-a.origin).dot(axis)
	if bend.length()<0.01:bend=world_frame.x
	bend=bend.normalized()
	var along := (length_a*length_a+distance*distance-length_b*length_b)/(2.0*distance)
	var elbow := a.origin+axis*along+bend*sqrt(maxf(0.0,length_a*length_a-along*along))
	var end := a.origin+axis*distance
	_rotate_toward(skeleton,upper,forearm,elbow,inverse)
	_rotate_toward(skeleton,forearm,hand,end,inverse)
	var pose := skeleton.global_transform*skeleton.get_bone_global_pose(hand)
	var blade_axis := pose.basis*driver.weapon.transform.basis.y
	var toward := (last_target+arc-pose.origin).normalized()
	var correction := Quaternion.IDENTITY.slerp(Quaternion(blade_axis.normalized(),toward),weight)
	pose.basis=Basis(correction)*pose.basis
	skeleton.set_bone_global_pose(hand,inverse*pose)

func _rotate_toward(skeleton: Skeleton3D, bone: int, child: int, point: Vector3, inverse: Transform3D) -> void:
	var pose := skeleton.global_transform*skeleton.get_bone_global_pose(bone)
	var endpoint := skeleton.global_transform*skeleton.get_bone_global_pose(child).origin
	pose.basis=Basis(Quaternion((endpoint-pose.origin).normalized(),(point-pose.origin).normalized()))*pose.basis
	skeleton.set_bone_global_pose(bone,inverse*pose)
