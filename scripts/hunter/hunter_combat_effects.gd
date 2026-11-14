class_name HunterCombatEffects
extends Node3D
## Cosmetic only: defense timing and damage stay in HunterFighter.
var fighter: HunterFighter
var surfaces: Array[Dictionary]=[]
var arm_shells: Array[Dictionary]=[]
var hit_left: float=0.0
var dodge_opacity: float=1.0
var _fading: bool=false
var _hit_material: ShaderMaterial
var _guard_material: ShaderMaterial
var _shader_cache: Dictionary={}

func setup(driver: HunterFighter) -> void:
	if is_instance_valid(fighter) and fighter.hit_received.is_connected(_on_hit):fighter.hit_received.disconnect(_on_hit)
	fighter=driver
	fighter.hit_received.connect(_on_hit)
	for child in get_children():child.queue_free()
	surfaces.clear();arm_shells.clear();hit_left=0.0;_fading=false
	_hit_material=ShaderMaterial.new()
	_hit_material.shader=preload("res://assets/characters/combat_hit_flash.gdshader")
	_guard_material=ShaderMaterial.new()
	_guard_material.shader=preload("res://assets/characters/combat_guard.gdshader")
	for mesh in fighter.actor.visual.get_node("Model").find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var source: Material=mesh.get_active_material(index)
			var fade: Material=source.duplicate()
			if fade is StandardMaterial3D:
				fade.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			elif fade is ShaderMaterial:
				var shader_source:=source as ShaderMaterial
				var code: String=shader_source.shader.code
				if not _shader_cache.has(code):
					var shader:=Shader.new()
					var start:=code.find("{",code.find("void fragment"))
					var depth:=1
					var end:=start+1
					while end<code.length() and depth>0:
						if code[end]=="{":depth+=1
						if code[end]=="}":depth-=1
						end+=1
					var body:=code.substr(0,start+1)+"\nALPHA=1.0;\n"+code.substr(start+1,end-start-2)+"\nALPHA*=dodge_opacity; ALPHA_SCISSOR_THRESHOLD=0.02;\n"+code.substr(end-1)
					shader.code=body.replace("shader_type spatial;","shader_type spatial;\nuniform float dodge_opacity=1.0;")
					_shader_cache[code]=shader
				fade.shader=_shader_cache[code]
				for uniform in shader_source.shader.get_shader_uniform_list():
					var name: StringName=uniform["name"]
					fade.set_shader_parameter(name,shader_source.get_shader_parameter(name))
				if source in fighter.actor.animation.skirt_materials:fighter.actor.animation.skirt_materials.append(fade)
			surfaces.append({"mesh":mesh,"surface":index,"source":source,"fade":fade,"color":source.albedo_color if source is StandardMaterial3D else Color.WHITE})
	for part in [&"left_forearm",&"right_forearm"]:
		var area: Area3D=fighter.boxes.hurtboxes[part]["area"]
		var shape: CapsuleShape3D=area.get_child(0).shape
		var shell:=MeshInstance3D.new()
		var capsule:=CapsuleMesh.new()
		capsule.radius=shape.radius+0.018
		capsule.height=shape.height+0.04
		shell.mesh=capsule
		shell.material_override=_guard_material
		shell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shell)
		shell.top_level=true
		shell.visible=false
		arm_shells.append({"mesh":shell,"area":area})

func _on_hit(_contact: Dictionary) -> void:hit_left=0.20

func reset_effects() -> void:
	hit_left=0.0
	_apply_fade(false,1.0)
	for entry in surfaces:
		if is_instance_valid(entry.mesh):entry.mesh.material_overlay=null
	for entry in arm_shells:entry.mesh.visible=false

func _process(delta: float) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(fighter.actor):return
	hit_left=maxf(0.0,hit_left-delta)
	_hit_material.set_shader_parameter("strength",0.24*pow(hit_left/0.20,0.65))
	for entry in surfaces:
		entry.mesh.material_overlay=_hit_material if hit_left>0.0 else null
	var parrying:=fighter.motion==&"parry" and not fighter.round_over
	var guard_strength:=smoothstep(0.0,0.06,fighter.elapsed)*(1.0-smoothstep(0.50,0.68,fighter.elapsed)) if parrying else 0.0
	_guard_material.set_shader_parameter("strength",guard_strength)
	for entry in arm_shells:
		entry.mesh.visible=guard_strength>0.001
		if entry.mesh.visible:entry.mesh.global_transform=entry.area.global_transform
	var dodging:=fighter.motion==&"dodge" and not fighter.round_over
	var opacity:=1.0
	if dodging:
		var envelope:=smoothstep(0.0,0.06,fighter.elapsed)*(1.0-smoothstep(0.38,0.50,fighter.elapsed))
		opacity=lerpf(1.0,0.46+0.23*sin(fighter.elapsed*TAU*9.0),envelope)
	_apply_fade(dodging,opacity)

func _apply_fade(active: bool, opacity: float) -> void:
	dodge_opacity=opacity
	for entry in surfaces:
		if not is_instance_valid(entry.mesh):continue
		if active!=_fading:entry.mesh.set_surface_override_material(entry.surface,entry.fade if active else entry.source)
		if active:
			if entry.fade is StandardMaterial3D:
				var color: Color=entry.color
				color.a*=opacity
				entry.fade.albedo_color=color
			else:entry.fade.set_shader_parameter("dodge_opacity",opacity)
	_fading=active
