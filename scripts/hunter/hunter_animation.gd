class_name HunterAnimation
extends Node
## Blend locomotion by actual speed; full-body actions crossfade on top.
signal model_ready(index: int)
const APPEARANCE = preload("res://scripts/hunter/character_appearance.gd")
const CHARACTERS = [
	{"number":1,"name":"Lily", "source":"Character.zip", "path":"res://assets/characters/lily.glb", "portrait":"res://assets/ui/portraits/lily.png"},
	{"number":2,"name":"Rin", "source":"FBX_with_Atlas.zip", "path":"res://assets/characters/rin.glb", "portrait":"res://assets/ui/portraits/rin.png"},
	{"number":3,"name":"Aki", "source":"School_Girl_Aki.zip", "path":"res://assets/characters/aki.glb", "portrait":"res://assets/ui/portraits/aki.png"},
	{"number":0,"name":"Lily Orange", "source":"Lily_Orange_Restyle.zip", "path":"res://assets/characters/lily_orange.glb", "portrait":"res://assets/ui/portraits/lily_orange.png","preserve_materials":true}]
const SELECTION_ORDER=[3,0,1,2]
const HAIR_COLORS = APPEARANCE.HAIR_COLORS
var weapon: HunterWeapon
var weapon_socket: BoneAttachment3D
var character_index: int = 0
var _action_speed: float = 1.0
var player: AnimationPlayer
var tree: AnimationTree
var skeleton: Skeleton3D
var _action_node: AnimationNodeAnimation
var _clips: Dictionary = {}
var _mode: StringName = &""
var _weapon_visible: bool = false
var physics_rig: HunterPhysicsRig
var aim: HunterAimModifier
var cloth: HunterClothModifier
var hair_motion: HunterHairModifier
var skirt_materials: Array[ShaderMaterial]=[]
var _sampled_frame: int = -1
var _locomotion_idle: AnimationNodeAnimation
var combat_stance: bool=false

func _ready() -> void:
	_load_initial_character.call_deferred()
	get_parent().attack_landed.connect(_on_hit)

func _load_initial_character() -> void:
	# A character may already have been chosen during the scene's first frame.
	if tree==null:load_character(get_parent().character_index)

func load_character(index: int) -> void:
	character_index = clampi(index,0,CHARACTERS.size()-1)
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_sample_weapon):skeleton.skeleton_updated.disconnect(_sample_weapon)
	if tree:
		remove_child(tree)
		tree.queue_free()
		tree = null
	var visual: Node3D = get_parent().get_node("Visual")
	var old := visual.get_node_or_null("Model")
	if old:
		visual.remove_child(old)
		old.queue_free()
	var model: Node3D = load(CHARACTERS[character_index]["path"]).instantiate()
	model.name = "Model"
	visual.add_child(model)
	skirt_materials.clear()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.mesh = APPEARANCE.prepare_mesh(character_index, mesh.mesh)
		for surface in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.mesh.surface_get_material(surface)
			if original is StandardMaterial3D:
				var reference_material: ShaderMaterial = APPEARANCE.material_for(character_index, original)
				if reference_material != null:
					mesh.set_surface_override_material(surface, reference_material)
					continue
				if original.resource_name.begins_with("HunterSkirt_") or (character_index==3 and mesh.name=="Lily_Coat"):
					var skirt:=ShaderMaterial.new()
					skirt.shader=preload("res://assets/characters/skirt_collision.gdshader")
					skirt.set_shader_parameter("base_color",original.albedo_color)
					skirt.set_shader_parameter("has_texture",original.albedo_texture!=null)
					if character_index==3:
						skirt.set_shader_parameter("coat_ease",0.028)
						skirt.set_shader_parameter("coat_flare",0.048)
						skirt.set_shader_parameter("coat_back_ease",0.05)
						skirt.set_shader_parameter("coat_waist_ease",0.035)
					if original.albedo_texture:skirt.set_shader_parameter("source_texture",original.albedo_texture)
					mesh.set_surface_override_material(surface,skirt)
					mesh.extra_cull_margin=0.6
					skirt_materials.append(skirt)
					continue
				if original.resource_name.begins_with("HunterHair_") and not CHARACTERS[character_index].get("preserve_materials",false):
					var hair := ShaderMaterial.new()
					hair.shader = preload("res://assets/characters/hair_recolor.gdshader")
					hair.set_shader_parameter("hair_color", HAIR_COLORS[character_index])
					hair.set_shader_parameter("preserve_face_atlas", character_index == 1)
					hair.set_shader_parameter("has_texture", original.albedo_texture != null)
					if original.albedo_texture:hair.set_shader_parameter("source_texture",original.albedo_texture)
					mesh.set_surface_override_material(surface,hair)
					continue
				var material: StandardMaterial3D = original.duplicate()
				if character_index==3 and original.resource_name.begins_with("HunterHair_"):
					material.albedo_color*=Color(1.0,0.74,0.55,1.0)
				if not CHARACTERS[character_index].get("preserve_materials",false):
					material.emission_enabled = false
					material.metallic_specular = 0.12
					material.roughness = 0.95
				mesh.set_surface_override_material(surface,material)
	_clips.clear()
	_mode = &""
	player = _find_type(model, "AnimationPlayer") as AnimationPlayer
	skeleton = _find_type(model, "Skeleton3D") as Skeleton3D
	if player == null:
		push_error("Hunter model has no AnimationPlayer. Run tools/prepare_hunter.py first.")
		return
	for name in player.get_animation_list():
		var short_name := String(name).get_slice("/", String(name).get_slice_count("/") - 1)
		_clips[short_name] = name
	for key in ["idle", "jog", "sprint", "look", "captured", "combat_idle", "down_pose", "victory_pose"]:
		if _clips.has(key):
			player.get_animation(_clips[key]).loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	_setup_weapon()
	tree.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.advance(1.0/60.0)
	skeleton.force_update_all_bone_transforms()
	aim=HunterAimModifier.new()
	aim.name="StrikeAim"
	aim.driver=self
	skeleton.add_child(aim)
	var clinch:=HunterClinchModifier.new()
	clinch.name="ClinchHands"
	clinch.driver=self
	skeleton.add_child(clinch)
	physics_rig=HunterPhysicsRig.new()
	physics_rig.name="PhysicalHitboxes"
	skeleton.add_child(physics_rig)
	physics_rig.setup(skeleton,get_parent())
	get_parent().physics_rig=physics_rig
	cloth=HunterClothModifier.new()
	cloth.name="SkirtMidAndHem"
	skeleton.add_child(cloth)
	cloth.setup(get_parent(),skirt_materials)
	hair_motion=HunterHairModifier.new()
	hair_motion.name="HairFrontSidesBack"
	skeleton.add_child(hair_motion)
	hair_motion.setup(character_index)
	_sampled_frame=-1
	skeleton.skeleton_updated.connect(_sample_weapon)
	weapon.blade_swept.connect(get_parent()._on_blade_swept)
	set_weapon_visible(_weapon_visible)
	model_ready.emit(character_index)

func _build_tree() -> void:
	var blend := AnimationNodeBlendTree.new()
	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 5.5
	_locomotion_idle=_node("combat_idle" if combat_stance else "idle")
	locomotion.add_blend_point(_locomotion_idle, 0.0, -1, &"idle")
	locomotion.add_blend_point(_node("jog"), 2.0, -1, &"jog")
	locomotion.add_blend_point(_node("sprint"), 5.0, -1, &"sprint")
	blend.add_node("Locomotion", locomotion)
	var rate := AnimationNodeTimeScale.new()
	blend.add_node("Rate", rate)
	blend.connect_node("Rate", 0, "Locomotion")
	var mode := AnimationNodeTransition.new()
	mode.input_count = 4
	mode.xfade_time = 0.24
	for i in range(4):
		mode.set_input_name(i, ["locomotion", "look", "captured", "down"][i])
	blend.add_node("Mode", mode)
	blend.add_node("Look", _node("look"))
	blend.add_node("Captured", _node("captured"))
	blend.add_node("Down", _node("fall"))
	blend.connect_node("Mode", 0, "Rate")
	blend.connect_node("Mode", 1, "Look")
	blend.connect_node("Mode", 2, "Captured")
	blend.connect_node("Mode", 3, "Down")
	_action_node = _node("elbow")
	blend.add_node("Action", _action_node)
	blend.add_node("ActionRate", AnimationNodeTimeScale.new())
	blend.connect_node("ActionRate", 0, "Action")
	var shot := AnimationNodeOneShot.new()
	# Finish base-state transitions while an action fully covers them. Otherwise
	# the down -> locomotion crossfade freezes, then resumes at the get-up tail.
	shot.sync = true
	shot.fadein_time = 0.07
	shot.fadeout_time = 0.10
	blend.add_node("Strike", shot)
	blend.connect_node("Strike", 0, "Mode")
	blend.connect_node("Strike", 1, "ActionRate")
	blend.connect_node("output", 0, "Strike")
	tree = AnimationTree.new()
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = blend
	tree.active = true

func _node(key: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = _clips.get(key, _clips.get("idle", &""))
	return node

func play_state(state: StringName, speed: float) -> void:
	if tree == null or not tree.active:
		return
	var requested: StringName = &"locomotion"
	if state == &"alert":
		requested = &"look"
	elif state == &"captured":
		requested = &"captured"
	elif state == &"incapacitated" or state == &"captured_complete":
		requested = &"down"
	if requested != _mode:
		_mode = requested
		tree.set("parameters/Mode/transition_request", requested)
	tree.set("parameters/Locomotion/blend_position", speed)
	# Cycles remain tied to displacement while changing gait.
	tree.set("parameters/Rate/scale", clampf(speed / (2.0 if speed < 2.8 else 5.0), 0.75, 1.25) if speed > 0.1 else 1.0)

func play_action(kind: StringName, source: Node3D = null) -> float:
	if player == null or tree == null:
		return 1.0
	var key := "get_up" if kind==&"get_up" else ("elbow" if kind==&"elbow" else "slash")
	var efficiency := physics_rig.get_action_efficiency(kind) if is_instance_valid(physics_rig) else 1.0
	_action_speed = (1.35 if kind == &"elbow" else 2.6)*lerpf(0.55,1.0,efficiency)
	if kind==&"get_up":_action_speed=1.25
	var duration:=play_clip(key,_action_speed)
	if kind == &"slash" and weapon:
		weapon.begin_swing(duration)
		if aim:aim.begin(source,duration)
		if physics_rig:physics_rig.set_cutting(true)
	return duration

func play_clip(key: String, rate: float = 1.0) -> float:
	if player==null or tree==null or not _clips.has(key):return 0.0
	var clip: StringName=_clips[key]
	# Process the abort before firing again. An interrupted fighter's reaction
	# must start at frame zero, even if its previous attack OneShot was active.
	tree.set("parameters/Strike/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.advance(0.0)
	_action_node.animation=clip
	_action_speed=rate
	tree.set("parameters/ActionRate/scale", _action_speed)
	tree.set("parameters/Strike/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return player.get_animation(clip).length/maxf(rate,0.01)

func set_combat_stance(value: bool) -> void:
	combat_stance=value
	if _locomotion_idle:_locomotion_idle.animation=_clips.get("combat_idle" if value else "idle",_clips.get("idle",&""))

func set_action_rate(value: float) -> void:
	_action_speed=maxf(0.1,value)
	if tree:tree.set("parameters/ActionRate/scale",_action_speed)

func action_hit_time(kind: StringName) -> float:
	return (0.42 if kind == &"elbow" else 0.48)/maxf(_action_speed,0.01)

func cancel_action() -> void:
	if tree != null and tree.active:
		tree.set("parameters/Strike/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	if is_instance_valid(weapon): weapon.cancel_swing()
	if is_instance_valid(aim):aim.stop()
	if is_instance_valid(physics_rig):physics_rig.set_cutting(false)

func fade_action() -> void:
	if tree!=null and tree.active:tree.set("parameters/Strike/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	if is_instance_valid(weapon):weapon.cancel_swing()
	if is_instance_valid(aim):aim.stop()
	if is_instance_valid(physics_rig):physics_rig.set_cutting(false)

func finish_strike() -> void:
	if is_instance_valid(physics_rig):physics_rig.set_cutting(false)

func _sample_weapon() -> void:
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree():return
	if not is_instance_valid(weapon) or not weapon.is_inside_tree():return
	var frame := Engine.get_physics_frames()
	if frame==_sampled_frame or not is_instance_valid(weapon):return
	_sampled_frame=frame
	var hand := skeleton.find_bone("RightHand")
	weapon.record_pose(skeleton.global_transform*skeleton.get_bone_global_pose(hand)*weapon.transform,get_physics_process_delta_time())

func set_weapon_visible(value: bool) -> void:
	_weapon_visible = value
	if is_instance_valid(weapon): weapon.visible = value

func _setup_weapon() -> void:
	var hand := skeleton.find_bone("RightHand")
	if hand < 0:
		push_error("Character needs a RightHand bone")
		return
	weapon_socket = BoneAttachment3D.new()
	weapon_socket.name = "RightHandWeaponSocket"
	weapon_socket.bone_idx = hand
	skeleton.add_child(weapon_socket)
	weapon = HunterWeapon.new()
	weapon_socket.add_child(weapon)
	var rest := skeleton.get_bone_global_rest(hand)
	var middle := skeleton.find_bone("RightHandMiddle1")
	var palm := skeleton.get_bone_global_rest(middle).origin-rest.origin if middle>=0 else rest.basis.y*0.07
	var along := (rest.basis.inverse()*palm).normalized()
	var across := along.cross(Vector3(0,0,1)).normalized()
	if across.length()<0.1: across = along.cross(Vector3.RIGHT).normalized()
	weapon.transform = Transform3D(Basis(across,along,across.cross(along).normalized()).orthonormalized(),rest.basis.inverse()*palm*0.72)

func _on_hit(kind: StringName, source: Node3D, _damage: float) -> void:
	if kind == &"slash" and weapon and get_tree().current_scene:
		weapon.hit_spark(source.get_cut_position() if source.has_method("get_cut_position") else source.global_position)

func _find_type(root: Node, type: String) -> Node:
	if root.is_class(type):
		return root
	for child in root.get_children():
		var found := _find_type(child, type)
		if found:
			return found
	return null
