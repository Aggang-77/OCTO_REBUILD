class_name CapturePreview
extends Node3D
## Visible stand-in for an octopus tentacle; the actual game uses HunterThreat.
var target: HunterTarget
var threat: HunterThreat
var tube: MeshInstance3D
var tube_mesh := ImmediateMesh.new()
var _hold_blend: float = 0.0
var _clock: float = 0.0
var _suckers: Array[MeshInstance3D] = []

func _ready() -> void:
	tube = MeshInstance3D.new()
	tube.mesh = tube_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8e74bd")
	material.roughness = 0.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tube.material_override = material
	add_child(tube)
	var sucker_material := StandardMaterial3D.new()
	sucker_material.albedo_color = Color("d1badf")
	sucker_material.roughness = 0.8
	var disc := SphereMesh.new()
	disc.radius = 0.034
	disc.height = 0.022
	for i in range(20):
		var sucker := MeshInstance3D.new()
		sucker.mesh = disc
		sucker.material_override = sucker_material
		add_child(sucker)
		_suckers.append(sucker)

func _process(delta: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(threat):return
	_clock += delta
	var physical_grips: Dictionary=target.physics_rig.grips if is_instance_valid(target.physics_rig) else {}
	var held := is_instance_valid(target.capture_source) or not physical_grips.is_empty()
	_hold_blend = move_toward(_hold_blend,1.0 if held else 0.0,delta*5.0)
	visible = threat.active or _hold_blend>0.01
	if not visible:return
	var center := target.global_position
	var base := center+Vector3(2.2,0.05,-1.8) if _hold_blend>0.01 else threat.global_position+Vector3(0,0,-1.0)
	var free_tip := threat.get_cut_position()
	var wrap_origin := center+Vector3.UP*0.92
	var wrap_axis := Vector3.UP
	var radius_x := 0.37
	var radius_z := 0.27
	var wrap_length := 0.28
	if is_instance_valid(threat.physics_anchor):
		free_tip=threat.physics_anchor.global_position
		base=threat.physics_anchor.get_meta("support_point",free_tip+Vector3(1.5,-0.7,-0.8))
	if not physical_grips.is_empty():
		var grip: Dictionary=physical_grips.values()[0]
		var part: Dictionary=target.physics_rig.parts[grip["part"]]
		var body: RigidBody3D=part["body"]
		wrap_origin=body.global_position
		wrap_axis=(body.global_basis*part["axis"]).normalized()
		if grip["part"]!=&"torso" and grip["part"]!=&"pelvis":
			radius_x=0.095
			radius_z=0.095
			wrap_length=0.16
		wrap_origin-=wrap_axis*wrap_length*0.5
	var u := wrap_axis.cross(Vector3.FORWARD).normalized()
	if u.length()<0.1:u=wrap_axis.cross(Vector3.RIGHT).normalized()
	var v := wrap_axis.cross(u).normalized()
	var start_wrap := wrap_origin+u*radius_x
	var endpoint := free_tip.lerp(start_wrap,_hold_blend)
	var points: Array[Vector3] = []
	for i in range(13):
		var t := float(i)/12.0
		var p := base.lerp(endpoint,t)
		p.y += sin(t*PI)*0.4
		points.append(p)
	if _hold_blend>0.01:
		for i in range(1,39):
			var t := float(i)/38.0
			var angle := t*TAU*1.55
			var p := wrap_origin+u*cos(angle)*radius_x+v*sin(angle)*radius_z+wrap_axis*t*wrap_length
			points.append(endpoint.lerp(p,_hold_blend))
	tube_mesh.clear_surfaces()
	tube_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[Array] = []
	var normals: Array[Array] = []
	var previous_across := Vector3.RIGHT
	for i in range(points.size()):
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
		var across := previous_across.slide(tangent).normalized()
		if across.length()<0.1:across=tangent.cross(Vector3.UP).normalized()
		if across.length()<0.1:across=tangent.cross(Vector3.RIGHT).normalized()
		previous_across=across
		var up := tangent.cross(across).normalized()
		var radius := lerpf(0.12,0.045,float(i)/points.size())
		var ring: Array[Vector3] = []
		var normal_ring: Array[Vector3] = []
		for j in range(10):
			var angle := TAU*float(j)/10.0
			var normal := across*cos(angle)+up*sin(angle)
			ring.append(points[i]+normal*radius)
			normal_ring.append(normal)
		rings.append(ring)
		normals.append(normal_ring)
	for i in range(1,points.size()):
		for j in range(10):
			var k := (j+1)%10
			for index_pair in [[i-1,j],[i-1,k],[i,j],[i-1,k],[i,k],[i,j]]:
				tube_mesh.surface_set_normal(normals[index_pair[0]][index_pair[1]])
				tube_mesh.surface_add_vertex(rings[index_pair[0]][index_pair[1]])
	tube_mesh.surface_end()
	for i in range(_suckers.size()):
		var index := clampi(int(float(i)/_suckers.size()*(points.size()-1)),0,points.size()-1)
		var p := points[index]
		_suckers[i].global_position = p+Vector3.UP*0.055
		_suckers[i].visible = true
