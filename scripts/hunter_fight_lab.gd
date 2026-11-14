extends Node3D
const ACTOR=preload("res://scenes/hunter_target.tscn")
const ACCENT=Color("82ddcc")
const CORAL=Color("efa58f")
var player: HunterTarget
var rival: HunterTarget
var camera: HunterFightCamera
var winner: HunterTarget
var _round_pending: bool=false
var _camera_button: Button
var _move_help: Label
var _player_health: ProgressBar
var _rival_health: ProgressBar
var _player_label: Label
var _rival_label: Label
var _motion_label: Label
var _contact_label: Label
var _result_label: Label
var _events: RichTextLabel
var _player_picker: OptionButton
var _rival_picker: OptionButton
var _ai_toggle: CheckButton
var _debug_toggle: CheckButton
var _lines: Array[String]=[]
var _yaw: float=0.55
var _pitch: float=0.30
var _distance: float=6.4
var _focus:=Vector3(0,0.85,0)
var _paused: bool=false
var _time: float=0.0
## Optional embedded entry point; standalone lab navigation keeps its defaults.
var entry_character_index: int=-1
var return_action: Callable

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	_build_world()
	_build_ui()
	player.fighter.strike_landed.connect(_landed)
	rival.fighter.strike_landed.connect(_landed)
	player.fighter.knocked_out.connect(_knockout)
	rival.fighter.knocked_out.connect(_knockout)
	player.fighter.defense_succeeded.connect(func(kind: StringName):_log("P1 "+("패링" if kind==&"parry" else "회피")+" 성공 · 다음 공격 선딜 감소"))
	rival.fighter.defense_succeeded.connect(func(kind: StringName):_log("CPU "+("패링" if kind==&"parry" else "회피")+" 성공 · 다음 공격 선딜 감소"))
	player.fighter.pressure_escaped.connect(func(kind: StringName):_log("P1 연타 탈출 · "+("패링" if kind==&"parry" else "회피")))
	player.fighter.reaction_started.connect(func(_clip: StringName, part: StringName):_log("P1 "+("머리" if part==&"head" else "몸통")+" 피격 반응"))
	rival.fighter.reaction_started.connect(func(_clip: StringName, part: StringName):_log("CPU "+("머리" if part==&"head" else "몸통")+" 피격 반응"))
	reset_fight()
	if "--preview-zero" in OS.get_cmdline_user_args():
		player.set_character(3)
		reset_fight()
		_ai_toggle.button_pressed=false
	if "--capture-fight" in OS.get_cmdline_user_args():_capture_fight()
	if "--capture-hit-reactions" in OS.get_cmdline_user_args():_capture_hit_reactions()
	if "--capture-defense" in OS.get_cmdline_user_args():_capture_defense()
	if "--capture-zero" in OS.get_cmdline_user_args():_capture_zero()
	if "--capture-combat-effects" in OS.get_cmdline_user_args():_capture_combat_effects()

func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=0.90
	return material

func _box(point: Vector3, size: Vector3, color: Color, solid: bool=true) -> void:
	var mesh:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=size
	mesh.mesh=box
	mesh.position=point
	mesh.material_override=_material(color)
	add_child(mesh)
	if solid:
		var body:=StaticBody3D.new()
		body.position=point
		add_child(body)
		var collision:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=size
		collision.shape=shape
		body.add_child(collision)

func _build_world() -> void:
	var world:=WorldEnvironment.new()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("14222d")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c2d7e8")
	environment.ambient_light_energy=0.5
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	world.environment=environment
	add_child(world)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-30,0)
	sun.light_color=Color("ffe5cb")
	sun.light_energy=0.85
	sun.shadow_enabled=true
	add_child(sun)
	var fill:=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-25,145,0)
	fill.light_color=Color("a7cce6")
	fill.light_energy=0.35
	add_child(fill)
	_box(Vector3(0,-0.15,0),Vector3(15,0.3,13),Color("283c48"))
	for x in range(-7,8):_box(Vector3(x,0.004,0),Vector3(0.010,0.006,13),Color("374f5b"),false)
	for z in range(-6,7):_box(Vector3(0,0.004,z),Vector3(15,0.006,0.010),Color("374f5b"),false)
	for edge in [Vector4(0,-6.6,15.4,0.2),Vector4(0,6.6,15.4,0.2),Vector4(-7.6,0,0.2,13.4),Vector4(7.6,0,0.2,13.4)]:
		_box(Vector3(edge.x,0.4,edge.y),Vector3(edge.z,0.8,edge.w),Color("4b606a"))
	_box(Vector3(-4.4,1.10,0),Vector3(2.1,0.3,0.28),Color("687c84"))
	for x in [-5.35,-3.45]:_box(Vector3(x,0.55,0),Vector3(0.16,1.1,0.3),Color("687c84"))
	var label:=Label3D.new()
	label.text="SLIDE / SPACE"
	label.font_size=26
	label.pixel_size=0.008
	label.position=Vector3(-4.4,1.50,0)
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	player=ACTOR.instantiate()
	player.name="Player"
	if entry_character_index>=0:
		player.character_index=clampi(entry_character_index,0,HunterAnimation.CHARACTERS.size()-1)
	add_child(player)
	player.arena_bounds_enabled=false
	player.objective.target_id=&"fighter_player"
	player.enable_fighter(&"player",0)
	rival=ACTOR.instantiate()
	rival.name="SparringPartner"
	rival.character_index=2
	add_child(rival)
	rival.arena_bounds_enabled=false
	rival.objective.target_id=&"fighter_partner"
	rival.enable_fighter(&"sparring",1)
	player.fighter.opponent=rival
	rival.fighter.opponent=player
	camera=HunterFightCamera.new()
	camera.fov=47.0
	add_child(camera)
	camera.current=true
	player.fighter.camera=camera
	rival.fighter.camera=camera
	for actor in [player,rival]:
		var marker:=MeshInstance3D.new()
		var ring:=TorusMesh.new()
		ring.inner_radius=0.37
		ring.outer_radius=0.39
		ring.rings=48
		ring.ring_segments=8
		marker.mesh=ring
		marker.position.y=0.025
		marker.material_override=_material(ACCENT if actor==player else CORAL)
		actor.add_child(marker)

func _style() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.04,0.075,0.10,0.95)
	style.border_color=Color("3b5260")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left=14
	style.content_margin_right=14
	style.content_margin_top=12
	style.content_margin_bottom=12
	return style

func _label(text: String, size: int=14, color: Color=Color("b4c4ce")) -> Label:
	var label:=Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _button(text: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.focus_mode=Control.FOCUS_NONE
	button.custom_minimum_size.y=34
	button.pressed.connect(action)
	return button

func _health_panel(root: Control, right: bool) -> Array:
	var panel:=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
	panel.position=Vector2(-454,24) if right else Vector2(24,24)
	panel.custom_minimum_size=Vector2(430,0)
	panel.add_theme_stylebox_override("panel",_style())
	root.add_child(panel)
	var column:=VBoxContainer.new()
	panel.add_child(column)
	var label:=_label("",17,CORAL if right else ACCENT)
	column.add_child(label)
	var bar:=ProgressBar.new()
	bar.custom_minimum_size.y=18
	bar.show_percentage=false
	var fill:=StyleBoxFlat.new()
	fill.bg_color=CORAL if right else ACCENT
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill",fill)
	column.add_child(bar)
	return [label,bar]

func _build_ui() -> void:
	var layer:=CanvasLayer.new()
	add_child(layer)
	var root:=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var theme:=Theme.new()
	theme.default_font=load("res://assets/ui/malgun.ttf")
	theme.default_font_size=14
	root.theme=theme
	var left:=_health_panel(root,false)
	_player_label=left[0]
	_player_health=left[1]
	var right:=_health_panel(root,true)
	_rival_label=right[0]
	_rival_health=right[1]
	var title:=_label("FIGHT LAB",24,Color.WHITE)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position=Vector2(-76,30)
	root.add_child(title)
	_camera_button=_button("C   시점: 대결",_cycle_camera)
	_camera_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_camera_button.position=Vector2(-90,76)
	root.add_child(_camera_button)
	var panel:=PanelContainer.new()
	panel.position=Vector2(24,142)
	panel.custom_minimum_size=Vector2(246,0)
	panel.add_theme_stylebox_override("panel",_style())
	root.add_child(panel)
	var controls:=VBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	panel.add_child(controls)
	controls.add_child(_label("PLAYER / 0 · F1 · F2 · F3",12,ACCENT))
	_player_picker=OptionButton.new()
	_rival_picker=OptionButton.new()
	for index in HunterAnimation.SELECTION_ORDER:
		var character: Dictionary=HunterAnimation.CHARACTERS[index]
		var label:="%d · %s"%[character["number"],character["name"]]
		_player_picker.add_item(label,index)
		_rival_picker.add_item(label,index)
	_player_picker.item_selected.connect(func(position: int):player.set_character(_player_picker.get_item_id(position));reset_fight())
	_rival_picker.item_selected.connect(func(position: int):rival.set_character(_rival_picker.get_item_id(position));reset_fight())
	controls.add_child(_player_picker)
	controls.add_child(_label("SPARRING PARTNER",12,CORAL))
	_rival_picker.select(_rival_picker.get_item_index(2))
	controls.add_child(_rival_picker)
	controls.add_child(HSeparator.new())
	_move_help=_label("",14,Color("d5e1e7"))
	controls.add_child(_move_help)
	_ai_toggle=CheckButton.new()
	_ai_toggle.text="O   상대 스파링 AI"
	_ai_toggle.button_pressed=true
	_ai_toggle.toggled.connect(func(value: bool):rival.fighter.control=&"sparring" if value else &"dummy")
	controls.add_child(_ai_toggle)
	_debug_toggle=CheckButton.new()
	_debug_toggle.text="B   공격 / 피격 박스"
	_debug_toggle.toggled.connect(func(value: bool):player.fighter.set_debug(value);rival.fighter.set_debug(value))
	controls.add_child(_debug_toggle)
	controls.add_child(_button("R   체력 / 위치 초기화",reset_fight))
	controls.add_child(_button("P   일시정지",_toggle_pause))
	controls.add_child(_button("F10   추격전으로 돌아가기" if return_action.is_valid() else "F10   문어 AI 실험실",_open_ai_lab))
	var events_panel:=PanelContainer.new()
	events_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	events_panel.position=Vector2(-400,-254)
	events_panel.custom_minimum_size=Vector2(376,170)
	events_panel.add_theme_stylebox_override("panel",_style())
	root.add_child(events_panel)
	var events_column:=VBoxContainer.new()
	events_panel.add_child(events_column)
	events_column.add_child(_label("CONTACT / 공격 부위 → 피격 부위",12,ACCENT))
	_events=RichTextLabel.new()
	_events.custom_minimum_size=Vector2(344,128)
	_events.scroll_active=false
	events_column.add_child(_events)
	_motion_label=_label("",14,ACCENT)
	_motion_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_motion_label.position=Vector2(28,-145)
	root.add_child(_motion_label)
	_contact_label=_label("실제 공격 박스와 피격 박스의 접촉으로 판정합니다.",13)
	_contact_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_contact_label.position=Vector2(28,-92)
	root.add_child(_contact_label)
	var footer:=_label("우드래그  카메라 회전    ·    휠  확대    ·    P / Esc  일시정지    ·    R  라운드 초기화",13)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position=Vector2(28,-36)
	root.add_child(footer)
	_result_label=_label("",30,ACCENT)
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_result_label.position=Vector2(-160,124)
	root.add_child(_result_label)

func reset_fight() -> void:
	get_tree().paused=false
	_paused=false
	winner=null
	_round_pending=false
	player.reset_target(Vector3(0,0,1.0))
	rival.reset_target(Vector3(0,0,-0.45))
	player.visual.rotation.y=PI
	rival.visual.rotation.y=0.0
	if _player_picker:_player_picker.select(_player_picker.get_item_index(player.character_index))
	if _rival_picker:_rival_picker.select(_rival_picker.get_item_index(rival.character_index))
	if _result_label:_result_label.text=""
	_focus=Vector3(0,0.85,0.25)
	_log("라운드 준비 · J 펀치 / K 킥 / Space 슬라이딩")

func _physics_process(delta: float) -> void:
	if not _paused:_time+=delta
	camera.follow(player,rival,winner,_yaw,_pitch,_distance,delta)
	_player_health.value=player.objective.health/player.objective.max_health*100.0
	_rival_health.value=rival.objective.health/rival.objective.max_health*100.0
	_player_label.text="PLAYER · %s   %.0f / %.0f"%[HunterAnimation.CHARACTERS[player.character_index]["name"],player.objective.health,player.objective.max_health]
	_rival_label.text="PARTNER · %s   %.0f / %.0f"%[HunterAnimation.CHARACTERS[rival.character_index]["name"],rival.objective.health,rival.objective.max_health]
	var windows:=player.fighter.active_windows()
	var active:=String(HunterCombatMoves.PART_LABELS.get(windows[0]["part"],windows[0]["part"])) if not windows.is_empty() else "대기"
	_motion_label.text="%s   /   스태미나 %.0f   /   공격 판정: %s\n상대: %s%s"%[_state_text(player.state),player.stamina,active,_state_text(rival.state),"   ·   반격 준비: 선딜 감소" if player.fighter.counter_left>0.0 else ""]
	if player.fighter.can_pressure_escape():_motion_label.text+="   ·   연타 탈출: Q / E"
	var elbow_cooldown: float=player.fighter.cooldowns.get(&"elbow_strike",0.0)
	if elbow_cooldown>0.0:_motion_label.text+="   ·   U 대기 %.1f초"%elbow_cooldown
	var special: StringName=HunterCombatMoves.SPECIALS[player.character_index]
	_move_help.text="WASD 이동 / Shift 달리기\nJ 펀치 / K 캐릭터별 킥\nL 무릎 / U 엘보우\nI "+String(HunterCombatMoves.MOVES[special]["label"])+"\nQ 패링 / E 방향 회피\n2연속 피격 뒤 Q/E 탈출\nSpace 슬라이딩 태클"

func _state_text(state: StringName) -> String:
	if HunterCombatMoves.MOVES.has(state):return HunterCombatMoves.MOVES[state]["label"]
	return {&"fight_idle":"준비 자세",&"fight_move":"이동",&"turning":"방향 전환",&"sliding":"슬라이딩",&"hit_head":"머리 피격",&"hit_body":"몸통 피격",&"falling":"넘어지는 중",&"down":"넘어짐",&"getting_up":"일어서는 중",&"knocked_out":"KO",&"parrying":"패링",&"dodging":"회피",&"parried":"패링당함",&"clinched":"얼굴 잡힘",&"celebrating":"승리 세리머니"}.get(state,String(state))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		match key:
			KEY_J:if not _paused:player.fighter.request(&"punch")
			KEY_K:if not _paused:player.fighter.request(&"kick")
			KEY_L:if not _paused:player.fighter.request(&"knee")
			KEY_I:if not _paused:player.fighter.request(&"special")
			KEY_U:if not _paused:player.fighter.request(&"elbow_strike")
			KEY_Q:if not _paused:player.fighter.request(&"parry")
			KEY_E:if not _paused:player.fighter.request(&"dodge")
			KEY_C:_cycle_camera()
			KEY_SPACE:if not _paused:player.fighter.request(&"slide")
			KEY_R:reset_fight()
			KEY_O:_ai_toggle.button_pressed=not _ai_toggle.button_pressed
			KEY_B:_debug_toggle.button_pressed=not _debug_toggle.button_pressed
			KEY_P,KEY_ESCAPE:_toggle_pause()
			KEY_F10:_open_ai_lab()
			KEY_F1,KEY_F2,KEY_F3:
				var index:=key-KEY_F1
				player.set_character(index)
				reset_fight()
			KEY_0,KEY_F4:
				player.set_character(3)
				reset_fight()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera.mode=0
		_yaw-=event.relative.x*0.006
		_pitch=clampf(_pitch+event.relative.y*0.004,0.15,1.0)
		_camera_button.text="C   "+HunterFightCamera.MODES[camera.mode]
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:_distance=maxf(4.0,_distance-0.5)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:_distance=minf(14.0,_distance+0.5)

func _toggle_pause() -> void:
	_paused=not _paused
	get_tree().paused=_paused

func _cycle_camera() -> void:
	camera.cycle()
	_camera_button.text="C   "+HunterFightCamera.MODES[camera.mode]

func _open_ai_lab() -> void:
	get_tree().paused=false
	if return_action.is_valid():
		return_action.call_deferred()
		return
	get_tree().change_scene_to_file("res://scenes/tidal_hunter_lab.tscn")

func _landed(contact: Dictionary) -> void:
	var attacker: HunterTarget=contact["attacker"]
	var label: String=HunterCombatMoves.MOVES[contact["move"]]["label"]
	var attack: String=HunterCombatMoves.PART_LABELS.get(contact["attack_part"],contact["attack_part"])
	var hurt: String=HunterCombatMoves.PART_LABELS.get(contact["hurt_part"],contact["hurt_part"])
	var text:="%s %s · %s → %s · %.1f"%["P1" if attacker==player else "CPU",label,attack,hurt,contact["damage"]]
	if contact.get("parried",false):text="패링 성공 · "+text
	if contact.get("trip",false):text+=" · 넘어뜨림"
	_contact_label.text=text
	_log(text)
	var marker:=MeshInstance3D.new()
	var sphere:=SphereMesh.new()
	sphere.radius=0.045
	sphere.height=0.09
	marker.mesh=sphere
	marker.material_override=_material(Color("bcbd9a"))
	add_child(marker)
	marker.global_position=contact["position"]
	var tween:=marker.create_tween()
	tween.tween_property(marker,"scale",Vector3.ONE*0.05,0.16)
	tween.tween_callback(marker.queue_free)

func _knockout(_attacker: HunterTarget) -> void:
	if _round_pending:return
	_round_pending=true
	_finish_round.call_deferred()

func _finish_round() -> void:
	if not _round_pending:return
	_round_pending=false
	player.fighter.round_over=true
	rival.fighter.round_over=true
	player.fighter.boxes.deactivate_attacks()
	rival.fighter.boxes.deactivate_attacks()
	if player.incapacitated and rival.incapacitated:
		_result_label.text="동시 KO · 무승부"
	else:
		winner=rival if player.incapacitated else player
		winner.fighter.start_celebration()
		_result_label.text="PLAYER 승리 · KO" if winner==player else "PARTNER 승리 · KO"
	_log(_result_label.text+" / R 재시작")

func _log(text: String) -> void:
	_lines.push_front("%05.1f  %s"%[_time,text])
	if _lines.size()>5:_lines.resize(5)
	if _events:_events.text="\n".join(_lines)

func _capture_fight() -> void:
	_ai_toggle.button_pressed=false
	await get_tree().create_timer(1.0).timeout
	await _capture_frame("fight_idle")
	player.global_position=Vector3(0,0,0.50)
	rival.global_position=Vector3(0,0,-0.25)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	player.fighter.request_move(&"punch_cross")
	for i in range(28):await get_tree().physics_frame
	await _capture_frame("fight_punch")
	await get_tree().create_timer(0.7).timeout
	player.fighter.request_move(&"kick_a")
	for i in range(25):await get_tree().physics_frame
	await _capture_frame("fight_kick")
	await get_tree().create_timer(1.0).timeout
	reset_fight()
	player.fighter.request(&"slide")
	for i in range(30):await get_tree().physics_frame
	await _capture_frame("fight_slide")
	await get_tree().create_timer(1.0).timeout
	_debug_toggle.button_pressed=true
	await _capture_frame("fight_boxes")
	get_tree().quit()

func _capture_frame(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/"+file+".png")

func _capture_hit_reactions() -> void:
	_ai_toggle.button_pressed=false
	_yaw=1.10
	_distance=4.9
	await get_tree().create_timer(1.0).timeout
	player.global_position=Vector3(0,0,0.375)
	rival.global_position=Vector3(0,0,-0.375)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	for i in range(15):await get_tree().physics_frame
	player.fighter.request_move(&"punch_jab")
	for i in range(60):
		await get_tree().physics_frame
		if rival.fighter.motion==&"reaction":break
	for i in range(8):await get_tree().physics_frame
	await _capture_frame("fight_body_reaction")
	reset_fight()
	player.global_position=Vector3(0,0,0.55)
	rival.global_position=Vector3(0,0,-0.55)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	for part in rival.fighter.boxes.hurtboxes:
		if part!=&"head":rival.fighter.boxes.hurtboxes[part]["area"].collision_layer=0
	for i in range(15):await get_tree().physics_frame
	player.fighter.request_move(&"kick_a")
	for i in range(60):
		await get_tree().physics_frame
		if rival.fighter.last_reaction.begins_with("hit_head"):break
	for i in range(7):await get_tree().physics_frame
	await _capture_frame("fight_head_reaction")
	for i in range(50):await get_tree().physics_frame
	await _capture_frame("fight_head_knockdown")
	get_tree().quit()

func _capture_defense() -> void:
	_ai_toggle.button_pressed=false
	_yaw=1.05
	_distance=4.9
	await get_tree().create_timer(1.0).timeout
	player.set_character(1)
	reset_fight()
	player.global_position=Vector3(0,0,0.325)
	rival.global_position=Vector3(0,0,-0.325)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	player.fighter.request(&"special")
	for i in range(17):await get_tree().physics_frame
	await _capture_frame("fight_clinch")
	for i in range(14):await get_tree().physics_frame
	await _capture_frame("fight_clinch_knee")
	await get_tree().create_timer(0.8).timeout
	reset_fight()
	player.global_position=Vector3(0,0,0.375)
	rival.global_position=Vector3(0,0,-0.375)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	rival.fighter.request_move(&"punch_jab")
	for i in range(5):await get_tree().physics_frame
	player.fighter.request(&"parry")
	for i in range(12):await get_tree().physics_frame
	await _capture_frame("fight_parry")
	await get_tree().create_timer(0.7).timeout
	reset_fight()
	player.global_position=Vector3(0,0,0.35)
	rival.global_position=Vector3(0,0,-0.35)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	rival.objective.health=1.0
	player.fighter.request_move(&"punch_jab")
	await get_tree().create_timer(1.4).timeout
	await _capture_frame("fight_victory")
	await get_tree().create_timer(2.0).timeout
	await _capture_frame("fight_victory_pose")
	player.set_character(2)
	reset_fight()
	player.global_position=Vector3(0,0,0.325)
	rival.global_position=Vector3(0,0,-0.325)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	player.fighter.request(&"special")
	for i in range(84):await get_tree().physics_frame
	await _capture_frame("fight_uppercut")
	get_tree().quit()

func _capture_zero() -> void:
	_ai_toggle.button_pressed=false
	_yaw=1.05
	_distance=4.8
	player.set_character(3)
	reset_fight()
	await get_tree().create_timer(1.0).timeout
	await _capture_frame("zero_character_idle")
	camera.mode=1
	await get_tree().create_timer(1.3).timeout
	await _capture_frame("zero_coat_back")
	camera.mode=0
	await get_tree().create_timer(0.4).timeout
	player.global_position=Vector3(0,0,0.4)
	rival.global_position=Vector3(0,0,-0.4)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	player.fighter.request(&"special")
	for i in range(25):await get_tree().physics_frame
	await _capture_frame("zero_character_special")
	await get_tree().create_timer(1.0).timeout
	reset_fight()
	player.global_position=Vector3(0,0,0.4)
	rival.global_position=Vector3(0,0,-0.4)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	player.fighter.request(&"kick")
	for i in range(25):await get_tree().physics_frame
	await _capture_frame("zero_character_kick")
	await get_tree().create_timer(1.0).timeout
	player.set_character(0)
	reset_fight()
	player.global_position=Vector3(0,0,0.55)
	rival.global_position=Vector3(0,0,-0.55)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	player.fighter.request(&"special")
	for i in range(29):await get_tree().physics_frame
	await _capture_frame("special_armada")
	for i in range(41):await get_tree().physics_frame
	await _capture_frame("special_martelo_ground")
	for i in range(30):await get_tree().physics_frame
	await _capture_frame("special_capoeira_recovery")
	get_tree().quit()

func _capture_combat_effects() -> void:
	_ai_toggle.button_pressed=false
	_yaw=0.55
	_distance=4.6
	player.set_character(3)
	reset_fight()
	await get_tree().create_timer(1.0).timeout
	player.fighter.request(&"parry")
	for i in range(21):await get_tree().physics_frame
	await _capture_frame("combat_guard_shells")
	await get_tree().create_timer(0.6).timeout
	player.fighter.request(&"dodge")
	for i in range(8):await get_tree().physics_frame
	await _capture_frame("combat_dodge_fade")
	await get_tree().create_timer(0.7).timeout
	reset_fight()
	player.global_position=Vector3(0,0,0.325)
	rival.global_position=Vector3(0,0,-0.325)
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	await get_tree().create_timer(0.3).timeout
	rival.fighter.request_move(&"punch_jab")
	for i in range(40):
		await get_tree().physics_frame
		if player.objective.health<100.0:break
	for i in range(2):await get_tree().physics_frame
	await _capture_frame("combat_red_hit_flash")
	get_tree().quit()
