class_name HunterWeapon
extends Node3D
signal blade_swept(previous_base: Vector3, previous_tip: Vector3, current_base: Vector3, current_tip: Vector3)
## Local +Y points from the closed hand toward the tip of the blade.
var trail: MeshInstance3D
var trail_mesh := ImmediateMesh.new()
var samples: Array[Dictionary] = []
var swing_elapsed: float = -1.0
var swing_duration: float = 0.0
var _trail_material: StandardMaterial3D
const TRAIL_LIFE: float = 0.52
const TRAIL_HOLD: float = 0.10
const TRAIL_ALPHA: float = 0.28
const EDGE_ALPHA: float = 0.40
var _stroke_fades: Dictionary = {}
var _previous_base: Vector3
var _previous_tip: Vector3
var _pose: Transform3D
var _has_pose: bool = false
var _first_swing_sample: bool = true
var _stroke: int = 0

func _ready() -> void:
	name = "HandSword"
	_make_sword()
	trail = MeshInstance3D.new()
	add_child(trail)
	trail.top_level = true
	trail.global_transform = Transform3D.IDENTITY
	trail.mesh = trail_mesh
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.emission_enabled = true
	_trail_material.emission = Color("6ca5b3")
	_trail_material.emission_energy_multiplier = 0.35
	trail.material_override = _trail_material

func _part(mesh: Mesh, point: Vector3, color: Color, metallic: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.32
	instance.material_override = mat
	add_child(instance)

func _make_sword() -> void:
	var grip := CylinderMesh.new()
	grip.top_radius = 0.018
	grip.bottom_radius = 0.02
	grip.height = 0.14
	_part(grip,Vector3(0,-0.025,0),Color("273747"),0.25)
	var guard := BoxMesh.new()
	guard.size = Vector3(0.19,0.025,0.04)
	_part(guard,Vector3(0,0.055,0),Color("c8a66a"),0.75)
	var blade := ImmediateMesh.new()
	blade.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := [Vector3(-0.035,0.072,0),Vector3(0,0.072,0.009),Vector3(0.035,0.072,0),Vector3(0,0.072,-0.009)]
	var upper := [Vector3(-0.027,0.69,0),Vector3(0,0.69,0.006),Vector3(0.027,0.69,0),Vector3(0,0.69,-0.006)]
	var tip := Vector3(0,0.83,0)
	for i in range(4):
		var j := (i+1)%4
		var normal: Vector3 = (ring[j]-ring[i]).cross(upper[i]-ring[i]).normalized()
		for p in [ring[i],ring[j],upper[i],ring[j],upper[j],upper[i],upper[i],upper[j],tip]:
			blade.surface_set_normal(normal)
			blade.surface_add_vertex(p)
	blade.surface_end()
	_part(blade,Vector3.ZERO,Color("c6e1ed"),0.75)
	var pommel := SphereMesh.new()
	pommel.radius = 0.025
	pommel.height = 0.045
	_part(pommel,Vector3(0,-0.105,0),Color("c8a66a"),0.7)

func begin_swing(duration: float) -> void:
	swing_elapsed = 0.0
	swing_duration = duration
	_first_swing_sample=true
	_stroke+=1
	_stroke_fades[_stroke]=-1.0

func cancel_swing(clear_trail: bool = true) -> void:
	swing_elapsed = -1.0
	if clear_trail:
		samples.clear()
		_stroke_fades.clear()
		if trail_mesh: trail_mesh.clear_surfaces()
	elif _stroke_fades.has(_stroke):_stroke_fades[_stroke]=0.0

func blade_base() -> Vector3:
	return _pose*Vector3(0,0.09,0) if _has_pose else to_global(Vector3(0,0.09,0))

func blade_tip() -> Vector3:
	return _pose*Vector3(0,0.83,0) if _has_pose else to_global(Vector3(0,0.83,0))

func record_pose(pose: Transform3D, delta: float) -> void:
	_pose=pose
	_has_pose=true
	if swing_elapsed<0.0:return
	swing_elapsed+=delta
	var a := blade_base()
	var b := blade_tip()
	if _first_swing_sample:
		_previous_base=a
		_previous_tip=b
		_first_swing_sample=false
	var phase := swing_elapsed/maxf(swing_duration,0.001)
	if visible and phase>0.10 and phase<0.87:
		# Visual sheet extends slightly beyond the steel; hit tests use steel only.
		samples.append({"base":a,"tip":b+(b-a).normalized()*0.04,"age":0.0,"stroke":_stroke})
		blade_swept.emit(_previous_base,_previous_tip,a,b)
	_previous_base=a
	_previous_tip=b
	if phase>=0.87 and float(_stroke_fades.get(_stroke,-1.0))<0.0:_stroke_fades[_stroke]=0.0
	if swing_elapsed>=swing_duration:swing_elapsed=-1.0

func _process(delta: float) -> void:
	# One completed stroke is one effect: every point keeps the same opacity.
	for stroke in _stroke_fades.keys():
		if float(_stroke_fades[stroke])<0.0:continue
		_stroke_fades[stroke]+=delta
		if float(_stroke_fades[stroke])>TRAIL_HOLD+TRAIL_LIFE:_stroke_fades.erase(stroke)
	samples=samples.filter(func(sample: Dictionary): return _stroke_fades.has(sample["stroke"]))
	trail_mesh.clear_surfaces()
	if samples.size()<2:return
	var has_strip:=false
	for i in range(1,samples.size()):
		if samples[i-1]["stroke"]==samples[i]["stroke"] and samples[i-1]["tip"].distance_to(samples[i]["tip"])<=0.8:
			has_strip=true
			break
	if not has_strip:return
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,samples.size()):
		var a: Dictionary = samples[i-1]
		var b: Dictionary = samples[i]
		if a["stroke"]!=b["stroke"] or a["tip"].distance_to(b["tip"])>0.8:continue
		for pair in [[a,"base"],[a,"tip"],[b,"tip"],[a,"base"],[b,"tip"],[b,"base"]]:
			var sample: Dictionary = pair[0]
			var alpha := get_stroke_opacity(sample["stroke"])*TRAIL_ALPHA
			trail_mesh.surface_set_color(Color(0.38,0.70,0.80,alpha))
			trail_mesh.surface_add_vertex(sample[pair[1]])
		# A narrow, translucent edge keeps the arc readable without a white spike.
		for pair in [[a,0.965],[a,1.0],[b,1.0],[a,0.965],[b,1.0],[b,0.965]]:
			var sample: Dictionary=pair[0]
			var alpha := get_stroke_opacity(sample["stroke"])*EDGE_ALPHA
			trail_mesh.surface_set_color(Color(0.54,0.80,0.88,alpha))
			trail_mesh.surface_add_vertex((sample["base"] as Vector3).lerp(sample["tip"],pair[1]))
	trail_mesh.surface_end()

func get_stroke_opacity(stroke: int) -> float:
	if not _stroke_fades.has(stroke):return 0.0
	return 1.0-smoothstep(TRAIL_HOLD,TRAIL_HOLD+TRAIL_LIFE,float(_stroke_fades[stroke]))

func hit_spark(point: Vector3) -> void:
	var spark := MeshInstance3D.new()
	get_tree().current_scene.add_child(spark)
	spark.global_position = point
	var sphere := SphereMesh.new()
	sphere.radius = 0.075
	sphere.height = 0.15
	spark.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.58,0.85,0.92,0.55)
	spark.material_override = material
	var tween := spark.create_tween().set_parallel(true)
	tween.tween_property(spark,"scale",Vector3.ONE*1.8,0.20)
	tween.tween_property(material,"albedo_color:a",0.0,0.20)
	tween.chain().tween_callback(spark.queue_free)
