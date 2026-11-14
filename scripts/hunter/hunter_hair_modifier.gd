class_name HunterHairModifier
extends SkeletonModifier3D
## Independent front/side/back chains; the scalp and roots follow Head exactly.
var strands: Array[Dictionary]=[]
var _head: int=-1

func setup(index: int) -> void:
	var skeleton:=get_skeleton()
	_head=skeleton.find_bone("Head")
	var path:=String(HunterAnimation.CHARACTERS[index]["path"]).trim_suffix(".glb")+"_secondary.json"
	if not FileAccess.file_exists(path):return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var head_rest:=skeleton.get_bone_global_rest(_head)
	for entry in data.get("hair",[]):
		var bone:=skeleton.find_bone(entry["bone"])
		if bone<0:continue
		var rest:=skeleton.get_bone_global_rest(bone)
		var tail: Array=entry["end"]
		var endpoint:=Vector3(tail[0],tail[1],tail[2])
		strands.append({"bone":bone,"root":entry["bone"].ends_with("_0"),"rest":head_rest.affine_inverse()*rest,
			"axis":rest.affine_inverse()*endpoint,"maximum":float(entry["max_angle"]),"front":entry["front"],
			"tip":Vector3.ZERO,"previous":Vector3.ZERO,"initialized":false})

func reset_motion() -> void:
	for strand in strands:strand["initialized"]=false

func _process_modification_with_delta(delta: float) -> void:
	var skeleton:=get_skeleton()
	if skeleton==null or strands.is_empty():return
	var dt:=clampf(delta,0.001,1.0/30.0)
	var inverse:=skeleton.global_transform.affine_inverse()
	var head:=skeleton.global_transform*skeleton.get_bone_global_pose(_head)
	var skull_center:=head.origin+head.basis*(skeleton.get_bone_global_rest(_head).basis.inverse()*Vector3.UP*0.10)
	for strand in strands:
		var bone: int=strand["bone"]
		var pose: Transform3D=head*strand["rest"] if strand["root"] else skeleton.global_transform*skeleton.get_bone_global_pose(bone)
		if strand["root"]:skeleton.set_bone_global_pose(bone,inverse*pose)
		var rest_tip: Vector3=pose*strand["axis"]
		var tip: Vector3=strand["tip"]
		if not strand["initialized"] or tip.distance_to(rest_tip)>0.8:
			tip=rest_tip
			strand["previous"]=tip
			strand["initialized"]=true
		var velocity: Vector3=(tip-strand["previous"])*pow(0.76 if strand["front"] else 0.84,dt*60.0)
		strand["previous"]=tip
		tip+=velocity+(rest_tip-tip)*(260.0 if strand["front"] else 160.0)*dt*dt+Vector3.DOWN*0.7*dt*dt
		# Keep the fringe out of the face. Long rear strands also collide with the shoulders.
		var offset:=tip-skull_center
		if offset.length()<0.102 and offset.length()>0.001:tip=skull_center+offset.normalized()*0.102
		for side in ["Left","Right"]:
			var shoulder:=skeleton.find_bone(side+"Shoulder")
			if shoulder<0:continue
			var a:=skeleton.global_transform*skeleton.get_bone_global_pose(shoulder).origin
			var b:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Arm")).origin
			var contact:=Geometry3D.get_closest_point_to_segment(tip,a,b)
			var difference:=tip-contact
			if difference.length()<0.075 and difference.length()>0.001:tip=contact+difference.normalized()*0.075
		var original:=rest_tip-pose.origin
		var direction: Vector3=(tip-pose.origin).normalized()
		var angle:=original.normalized().angle_to(direction)
		if angle>float(strand["maximum"]):direction=original.normalized().slerp(direction,float(strand["maximum"])/angle)
		strand["tip"]=pose.origin+direction*original.length()
		pose.basis=Basis(Quaternion(original.normalized(),direction))*pose.basis
		skeleton.set_bone_global_pose(bone,inverse*pose)
