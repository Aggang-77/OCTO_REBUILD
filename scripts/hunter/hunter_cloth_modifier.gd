class_name HunterClothModifier
extends SkeletonModifier3D
## Waist-anchored, two-link skirt panels. Secondary motion follows the final body pose.
var panels: Array[Dictionary] = []
var actor: HunterTarget
var _hips: int
var materials: Array[ShaderMaterial]=[]
var leg_capsules: Array[Dictionary]=[]
const LEG_RADII=[Vector2(0.078,0.062),Vector2(0.062,0.050),Vector2(0.068,0.053),Vector2(0.095,0.064)]

func setup(value: HunterTarget, values: Array[ShaderMaterial]=[]) -> void:
	actor=value
	materials=values
	var skeleton := get_skeleton()
	_hips=skeleton.find_bone("Hips")
	var hips_rest := skeleton.get_bone_global_rest(_hips)
	for index in range(8):
		var mid := skeleton.find_bone("ClothPanel_%02d_Mid"%index)
		var hem := skeleton.find_bone("ClothPanel_%02d_Hem"%index)
		if mid<0 or hem<0:continue
		var a := skeleton.get_bone_global_rest(mid)
		var b := skeleton.get_bone_global_rest(hem)
		var direction := b.origin-a.origin
		for bone in [mid,hem]:
			var rest := skeleton.get_bone_global_rest(bone)
			panels.append({"bone":bone,"mid":bone==mid,"rest":hips_rest.affine_inverse()*rest,
				"axis":rest.basis.inverse()*direction,"tip":Vector3.ZERO,"previous":Vector3.ZERO,"initialized":false})
	if not panels.is_empty():
		for material in materials:material.set_shader_parameter("waist_height",(panels[0]["rest"] as Transform3D).origin.y)
	_update_collision_materials(skeleton, skeleton.global_transform*skeleton.get_bone_global_pose(_hips))

func reset_motion() -> void:
	for panel in panels:panel["initialized"]=false

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton==null or panels.is_empty():return
	var dt := clampf(delta,0.001,1.0/30.0)
	var hips := skeleton.global_transform*skeleton.get_bone_global_pose(_hips)
	var inverse := skeleton.global_transform.affine_inverse()
	_update_collision_materials(skeleton,hips)
	for panel in panels:
		var bone: int=panel["bone"]
		var goal: Transform3D=hips*panel["rest"] if panel["mid"] else skeleton.global_transform*skeleton.get_bone_global_pose(bone)
		if panel["mid"]:skeleton.set_bone_global_pose(bone,inverse*goal)
		var rest_tip: Vector3=goal*panel["axis"]
		var tip: Vector3=panel["tip"]
		if not panel["initialized"] or tip.distance_to(rest_tip)>0.85:
			tip=rest_tip
			panel["previous"]=tip
			panel["initialized"]=true
		var damping:=0.86 if actor.character_index==3 else (0.78 if actor.character_index>0 else 0.82)
		var velocity: Vector3=(tip-panel["previous"])*pow(damping,dt*60.0)
		panel["previous"]=tip
		var stiffness:=180.0 if panel["mid"] else 110.0
		if actor.character_index!=3:stiffness=240.0 if panel["mid"] else 170.0
		tip+=velocity+(rest_tip-tip)*stiffness*dt*dt+Vector3.DOWN*2.8*dt*dt
		var original := rest_tip-goal.origin
		var direction := (tip-goal.origin).normalized()
		var angle := original.normalized().angle_to(direction)
		var maximum := 0.30 if panel["mid"] else 0.48
		if actor.character_index>0:maximum=0.16 if panel["mid"] else 0.25
		if actor.character_index==3:maximum=0.28 if panel["mid"] else 0.42
		if angle>maximum:direction=original.normalized().slerp(direction,maximum/angle)
		# Lift a whole panel over a raised leg before the final per-vertex shell
		# correction. Do not stretch the fabric into a tube around the knee.
		var radial_local: Vector3=(panel["rest"] as Transform3D).origin
		radial_local.y=0.0
		var outward := (hips.basis*radial_local).normalized()
		var base_direction := direction
		var length := original.length()
		var best_clearance: float=-INF
		var best_direction:=direction
		for step in range(17):
			var candidate := base_direction.slerp(outward,float(step)/16.0*0.82)
			var endpoint := goal.origin+candidate*length
			var clear:=true
			var clearance: float=INF
			for capsule in leg_capsules:
				var start:=goal.origin.lerp(endpoint,0.18 if panel["mid"] else 0.0)
				var pair := Geometry3D.get_closest_points_between_segments(start,endpoint,capsule["start"],capsule["end"])
				clearance=minf(clearance,pair[0].distance_to(pair[1])-float(capsule["radius"])-0.010)
				if clearance<0.0:clear=false
			if clearance>best_clearance:
				best_clearance=clearance
				best_direction=candidate
			if clear:
				direction=candidate
				break
			if step==16:direction=best_direction
		tip=goal.origin+direction*original.length()
		panel["tip"]=tip
		var rotation := Quaternion(original.normalized(),direction)
		goal.basis=Basis(rotation)*goal.basis
		skeleton.set_bone_global_pose(bone,inverse*goal)

func _update_collision_materials(skeleton: Skeleton3D, hips: Transform3D) -> void:
	var starts:=PackedVector4Array()
	var ends:=PackedVector4Array()
	leg_capsules.clear()
	for side in ["Left","Right"]:
		var radii: Vector2=LEG_RADII[actor.character_index]
		for segment in [["UpLeg","Leg",radii.x],["Leg","Foot",radii.y]]:
			var a:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+segment[0])).origin
			var b:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+segment[1])).origin
			starts.append(Vector4(a.x,a.y,a.z,segment[2]))
			ends.append(Vector4(b.x,b.y,b.z,segment[2]))
			leg_capsules.append({"start":a,"end":b,"radius":segment[2]})
	for material in materials:
		material.set_shader_parameter("hips_world",hips)
		material.set_shader_parameter("hips_inverse",hips.affine_inverse())
		material.set_shader_parameter("leg_start",starts)
		material.set_shader_parameter("leg_end",ends)
		if actor.character_index==3:
			var chest:=skeleton.find_bone("Spine2")
			var chest_pose:=skeleton.global_transform*skeleton.get_bone_global_pose(chest)
			var back: Vector3=-(chest_pose.basis*skeleton.get_bone_global_rest(chest).basis.inverse()*Vector3.BACK).normalized()
			material.set_shader_parameter("garment_back",back)
