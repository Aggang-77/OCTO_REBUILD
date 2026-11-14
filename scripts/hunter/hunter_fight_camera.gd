class_name HunterFightCamera
extends Camera3D
const MODES=["대결 시점","어깨 시점","측면 시점"]
var mode: int=0
var focus:=Vector3(0,0.8,0)
var yaw: float=0.55
var pitch: float=0.30
var distance: float=6.4
var initialized: bool=false
var side_sign: float=1.0

func cycle() -> void:
	mode=(mode+1)%MODES.size()
	if mode==2:side_sign=1.0

func follow(player: HunterTarget, rival: HunterTarget, winner: HunterTarget, orbit_yaw: float, orbit_pitch: float, zoom: float, delta: float) -> void:
	var middle:=player.global_position.lerp(rival.global_position,0.5)+Vector3.UP*0.85
	var target_yaw:=orbit_yaw
	var target_pitch:=orbit_pitch
	var target_distance:=maxf(zoom,player.global_position.distance_to(rival.global_position)*1.25+2.0)
	if mode==1:
		middle=player.global_position+Vector3.UP*1.05
		target_yaw=player.visual.rotation.y+PI+0.22
		target_pitch=0.20
		target_distance=maxf(3.4,zoom*0.62)
	elif mode==2:
		var line:=player.global_position.direction_to(rival.global_position)
		if Vector2(line.x,line.z).length()>0.05:
			var candidate:=atan2(line.x,line.z)+PI*0.5
			# Keep the camera in its current hemisphere when the fighters cross.
			if absf(angle_difference(yaw,candidate))>PI*0.5:candidate+=PI
			target_yaw=candidate
		target_pitch=0.22
	if is_instance_valid(winner):
		middle=winner.global_position+Vector3.UP*0.95
		target_distance=4.5
		target_pitch=0.20
	if not initialized:
		focus=middle
		yaw=target_yaw
		pitch=target_pitch
		distance=target_distance
		initialized=true
	focus=focus.lerp(middle,1.0-exp(-delta*4.0))
	yaw=rotate_toward(yaw,target_yaw,delta*1.8)
	pitch=move_toward(pitch,target_pitch,delta*0.45)
	distance=lerpf(distance,target_distance,1.0-exp(-delta*3.2))
	var offset:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	var desired:=focus+offset
	var ray:=PhysicsRayQueryParameters3D.create(focus,desired,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():desired=(hit["position"] as Vector3).move_toward(focus,0.18)
	global_position=desired
	look_at(focus)
