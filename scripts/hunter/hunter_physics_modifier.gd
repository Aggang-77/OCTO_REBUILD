class_name HunterPhysicsModifier
extends SkeletonModifier3D
## Animation is sampled before the simulation pose is applied. No pose feedback loop.
var rig: HunterPhysicsRig

func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(rig) or not rig.enabled:return
	var skeleton := get_skeleton()
	if skeleton == null:return
	var animation_pose: Dictionary = {}
	for part in rig.parts.values():
		animation_pose[part["bone"]] = skeleton.global_transform * skeleton.get_bone_global_pose(part["bone"])
	rig.submit_animation(animation_pose)
	if not rig.initialized:return
	var inverse := skeleton.global_transform.affine_inverse()
	# Parent-first so descendants inherit the simulated parent before being updated.
	for name in rig.part_order:
		var part: Dictionary = rig.parts[name]
		var weight := rig.get_pose_weight(name)
		if weight <= 0.0001:continue
		var body: RigidBody3D = part["body"]
		var bone_world := body.global_transform * Transform3D(Basis.IDENTITY,-part["offset"])
		if rig.parts.has(part["parent"]):
			var parent_bone: int=rig.parts[part["parent"]]["bone"]
			bone_world=rig.constrain_bone_pose(name,bone_world,skeleton.global_transform*skeleton.get_bone_global_pose(parent_bone))
		var inherited := skeleton.get_bone_global_pose(part["bone"])
		skeleton.set_bone_global_pose(part["bone"],inherited.interpolate_with(inverse * bone_world,weight))
