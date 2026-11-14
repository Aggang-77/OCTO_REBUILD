extends Node3D
## Test harness only. Delete this scene when integrating the reusable target.
const HUNTER_SCENE = preload("res://scenes/hunter_target.tscn")
const INK = Color("101923")
const MUTED = Color("9baebc")
const ACCENT = Color("7de4cf")
var hunter: HunterTarget
var threat: HunterThreat
var camera: Camera3D
var safe_zone: Node3D
var ring: MeshInstance3D
var direction_marker: MeshInstance3D
var threat_marker: Node3D
var _state_label: Label
var _explanation: Label
var _health: ProgressBar
var _stamina: ProgressBar
var _capture: ProgressBar
var _stats: Label
var _events: RichTextLabel
var _level_buttons: Array[Button] = []
var _threat_button: Button
var _chase_button: Button
var _result_label: Label
var _chasing: bool = false
var _follow: bool = true
var _paused: bool = false
var _camera_yaw: float = 0.25
var _camera_pitch: float = 0.23
var _camera_distance: float = 6.1
var _camera_focus := Vector3(0, 0.8, 0)
var _event_lines: Array[String] = []
var _time: float = 0.0
var _character_picker: OptionButton
var _strong_capture: CheckButton
var _capture_preview: CapturePreview
var _physics_demo: PhysicsGrabDemo
var _physics_stats: Label
var _mass_label: Label

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	_build_world()
	_build_interface()
	hunter.state_changed.connect(_state_changed)
	hunter.attack_landed.connect(_attack_landed)
	hunter.objective_completed.connect(_objective_completed)
	threat.severed.connect(func(_attacker: Node3D):
		_log("촉수 절단 · 위협 비활성화")
		_chasing = false
		_release_physics())
	threat.cut_received.connect(func(_damage: float, _attacker: Node3D):
		if not is_instance_valid(threat.physics_anchor):threat.position += (threat.position-hunter.position).normalized()*1.1)
	threat.escape_impulse.connect(func(_power: float, _target: Node3D):
		if not is_instance_valid(threat.physics_anchor):threat.position += (threat.position - hunter.position).normalized() * 1.5
		_log("엘보우 타격 · 구속 해제 시도"))
	_log("준비 완료 · 위협을 켜면 자율 판단을 시작합니다")
	if "--capture-preview" in OS.get_cmdline_user_args():
		_preview_capture()
	if "--capture-gallery" in OS.get_cmdline_user_args():
		_preview_gallery()
	if "--capture-hair" in OS.get_cmdline_user_args():
		_preview_hair()
	if "--capture-characters" in OS.get_cmdline_user_args():
		_preview_characters()
	if "--capture-physics" in OS.get_cmdline_user_args():
		_preview_physics()
	if "--capture-motion" in OS.get_cmdline_user_args():
		_preview_motion()
	if "--capture-trail" in OS.get_cmdline_user_args():
		_preview_trail()

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func _mesh(parent: Node3D, mesh: Mesh, point: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	instance.material_override = _material(color, glow)
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color, solid: bool = false) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(parent, box, point, color)
	if solid:
		var body := StaticBody3D.new()
		parent.add_child(body)
		body.position = point
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)

func _torus(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.018
	torus.outer_radius = radius + 0.018
	torus.rings = 48
	torus.ring_segments = 8
	return _mesh(parent, torus, Vector3(0,0.025,0), color, 0.6)

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("15212d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c2d7e8")
	settings.ambient_light_energy = 0.4
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-32,0)
	sun.light_color = Color("ffe4c8")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30,140,0)
	fill.light_color = Color("9dcff5")
	fill.light_energy = 0.35
	add_child(fill)
	_box(self, Vector3(0,-0.15,0), Vector3(26,0.3,20),Color("283745"),true)
	for x in range(-13,14):
		_box(self,Vector3(x,0.004,0),Vector3(0.012,0.006,20),Color("354651"))
	for z in range(-10,11):
		_box(self,Vector3(0,0.005,z),Vector3(26,0.006,0.012),Color("354651"))
	for obstacle in [Vector3(3.7,0.6,-2.0),Vector3(-4.0,0.6,2.7),Vector3(0.5,0.6,-5.2)]:
		_box(self,obstacle,Vector3(1.8,1.2,1.5),Color("4d5e68"),true)
		_box(self,obstacle+Vector3(0,0.61,0),Vector3(1.82,0.025,1.52),Color("8a9b9a"))
	for wall in [Vector4(0,-10.15,26.6,0.3),Vector4(0,10.15,26.6,0.3),Vector4(-13.15,0,0.3,20.6),Vector4(13.15,0,0.3,20.6)]:
		_box(self,Vector3(wall.x,0.3,wall.y),Vector3(wall.z,0.6,wall.w),Color("475764"),true)
	safe_zone = Node3D.new()
	add_child(safe_zone)
	safe_zone.position = Vector3(10.0,0,6.0)
	_torus(safe_zone,1.55,ACCENT)
	_torus(safe_zone,1.4,Color("438c83"))
	var exit_label := Label3D.new()
	exit_label.text = "EXTRACTION"
	exit_label.font_size = 40
	exit_label.pixel_size = 0.008
	exit_label.modulate = ACCENT
	exit_label.position = Vector3(0,1.4,0)
	exit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	safe_zone.add_child(exit_label)
	hunter = HUNTER_SCENE.instantiate()
	add_child(hunter)
	hunter.safe_zone = safe_zone
	ring = _torus(self,0.53,ACCENT)
	var marker := SphereMesh.new()
	marker.radius = 0.07
	marker.height = 0.14
	direction_marker = _mesh(self,marker,Vector3.ZERO,ACCENT,1.0)
	threat = HunterThreat.new()
	threat.process_mode=Node.PROCESS_MODE_PAUSABLE
	threat.name = "VirtualTentacle"
	threat.active = false
	threat.health = 80.0
	threat.aim_offset=Vector3.UP*0.95
	add_child(threat)
	threat.position = Vector3(-3,0,0)
	threat_marker = Node3D.new()
	threat.add_child(threat_marker)
	_torus(threat_marker,0.42,Color("ffac75"))
	var orb := SphereMesh.new()
	orb.radius=0.13
	orb.height=0.26
	_mesh(threat_marker,orb,Vector3(0,0.75,0),Color("ffac75"),1.0)
	var label := Label3D.new()
	label.text="VIRTUAL THREAT"
	label.font_size=24
	label.position=Vector3(0,1.2,0)
	label.modulate=Color("ffac75")
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	threat_marker.add_child(label)
	_capture_preview = CapturePreview.new()
	_capture_preview.process_mode=Node.PROCESS_MODE_PAUSABLE
	_capture_preview.target = hunter
	_capture_preview.threat = threat
	add_child(_capture_preview)
	_physics_demo=PhysicsGrabDemo.new()
	_physics_demo.process_mode=Node.PROCESS_MODE_PAUSABLE
	_physics_demo.target=hunter
	add_child(_physics_demo)
	camera=Camera3D.new()
	camera.fov=45.0
	add_child(camera)
	camera.current=true

func _style(background: Color, border: Color = Color.TRANSPARENT, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=background
	style.border_color=border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=12
	style.content_margin_bottom=12
	return style

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var label:=Label.new()
	label.text=text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label

func _button(text: String, callable: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,40)
	button.add_theme_font_size_override("font_size",15)
	button.add_theme_stylebox_override("normal",_style(Color("233440"),Color("3d515d")))
	button.add_theme_stylebox_override("hover",_style(Color("344d57"),ACCENT))
	button.add_theme_stylebox_override("pressed",_style(Color("3a625e"),ACCENT))
	button.pressed.connect(callable)
	return button

func _bar(parent: VBoxContainer, text: String, color: Color) -> ProgressBar:
	parent.add_child(_label(text,12,MUTED))
	var bar:=ProgressBar.new()
	bar.custom_minimum_size.y=7
	bar.show_percentage=false
	bar.add_theme_stylebox_override("background",_style(Color("2d3e49"),Color.TRANSPARENT,0))
	bar.add_theme_stylebox_override("fill",_style(color,Color.TRANSPARENT,0))
	parent.add_child(bar)
	return bar

func _build_interface() -> void:
	var layer:=CanvasLayer.new()
	add_child(layer)
	var root:=Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var theme:=Theme.new()
	if ResourceLoader.exists("res://assets/ui/malgun.ttf"):
		theme.default_font=load("res://assets/ui/malgun.ttf")
	root.theme=theme
	var fight_button:=_button("F10   격투 모드",func():get_tree().paused=false;get_tree().change_scene_to_file("res://scenes/hunter_fight_lab.tscn"))
	fight_button.position=Vector2(342,28)
	root.add_child(fight_button)
	var heading:=VBoxContainer.new()
	heading.position=Vector2(32,24)
	root.add_child(heading)
	heading.add_child(_label("FIELD STUDY  /  001",12,ACCENT))
	heading.add_child(_label("HUNTER",38))
	heading.add_child(_label("Autonomous target laboratory",14,MUTED))
	var panel:=PanelContainer.new()
	panel.position=Vector2(28,142)
	panel.custom_minimum_size=Vector2(292,0)
	panel.add_theme_stylebox_override("panel",_style(Color(0.055,0.085,0.115,0.96),Color("364b58")))
	root.add_child(panel)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	column.add_child(_label("CHARACTER SELECT",12,ACCENT))
	_character_picker = OptionButton.new()
	_character_picker.custom_minimum_size = Vector2(250,36)
	_character_picker.add_theme_font_size_override("font_size",15)
	for index in HunterAnimation.SELECTION_ORDER:
		var character: Dictionary=HunterAnimation.CHARACTERS[index]
		_character_picker.add_item("%d · %s"%[character["number"],character["name"]],index)
	_character_picker.select(_character_picker.get_item_index(hunter.character_index))
	_character_picker.item_selected.connect(func(position: int):_select_character(_character_picker.get_item_id(position)))
	column.add_child(_character_picker)
	column.add_child(HSeparator.new())
	column.add_child(_label("BEHAVIOUR PROFILE",12,ACCENT))
	for i in range(3):
		var level:=i+1
		var button:=_button(["1   느리게 도망", "2   빠른 도주 + 엘보우", "3   촉수 검격 대응"][i],func(): _set_level(level))
		column.add_child(button)
		_level_buttons.append(button)
	_explanation=_label("",13,MUTED)
	_explanation.custom_minimum_size=Vector2(250,64)
	_explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_explanation)
	column.add_child(HSeparator.new())
	column.add_child(_label("SIMULATION",12,ACCENT))
	_threat_button=_button("T   가상 위협 켜기",_toggle_threat)
	column.add_child(_threat_button)
	_chase_button=_button("A   자동 접근 켜기",_toggle_chase)
	column.add_child(_chase_button)
	column.add_child(_button("G   포획 테스트",_capture_target))
	_strong_capture = CheckButton.new()
	_strong_capture.text = "H   강한 구속으로 테스트"
	_strong_capture.add_theme_font_size_override("font_size",13)
	column.add_child(_strong_capture)
	column.add_child(_button("U   구속 해제",_release_all))
	column.add_child(_button("R   초기화",_reset))
	var telemetry:=PanelContainer.new()
	telemetry.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	telemetry.position=Vector2(-278,28)
	telemetry.custom_minimum_size=Vector2(250,0)
	telemetry.add_theme_stylebox_override("panel",_style(Color(0.055,0.085,0.115,0.95),Color("364b58")))
	root.add_child(telemetry)
	var data:=VBoxContainer.new()
	data.add_theme_constant_override("separation",9)
	telemetry.add_child(data)
	data.add_child(_label("TARGET  /  FH–01",12,ACCENT))
	_state_label=_label("IDLE",23)
	data.add_child(_state_label)
	_health=_bar(data,"HEALTH",ACCENT)
	_stamina=_bar(data,"STAMINA",Color("a6c6f2"))
	_capture=_bar(data,"CAPTURE OBJECTIVE",Color("ffac75"))
	_stats=_label("",12,MUTED)
	data.add_child(_stats)
	var physics_panel:=PanelContainer.new()
	physics_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	physics_panel.position=Vector2(-278,392)
	physics_panel.custom_minimum_size=Vector2(250,0)
	physics_panel.add_theme_stylebox_override("panel",_style(Color(0.055,0.085,0.115,0.96),Color("364b58")))
	root.add_child(physics_panel)
	var controls:=VBoxContainer.new()
	controls.add_theme_constant_override("separation",5)
	physics_panel.add_child(controls)
	controls.add_child(_label("TWO-WAY PHYSICS",12,ACCENT))
	var arms:=HBoxContainer.new()
	controls.add_child(arms)
	arms.add_child(_button("J  오른팔",func(): _grab_arm(&"right_forearm")))
	arms.add_child(_button("K  왼팔",func(): _grab_arm(&"left_forearm")))
	var actions:=HBoxContainer.new()
	controls.add_child(actions)
	actions.add_child(_button("V  검격 시도",_attempt_physical_slash))
	actions.add_child(_button("P  충격",func(): _physics_demo.push_selected()))
	controls.add_child(_button("F  넘어짐 테스트",_test_fall))
	var height_picker:=OptionButton.new()
	for text in ["검격 높이: 낮음 (0.45 m)","검격 높이: 중간 (0.95 m)","검격 높이: 높음 (1.55 m)"]:height_picker.add_item(text)
	height_picker.select(1)
	height_picker.item_selected.connect(func(index: int): threat.aim_offset=Vector3.UP*[0.45,0.95,1.55][index])
	controls.add_child(height_picker)
	controls.add_child(_button("B  실제 히트박스 표시",_toggle_hitboxes))
	_mass_label=_label("촉수 말단 질량  8 kg",12,MUTED)
	controls.add_child(_mass_label)
	var mass:=HSlider.new()
	mass.min_value=2.0
	mass.max_value=40.0
	mass.step=1.0
	mass.value=8.0
	mass.value_changed.connect(func(value: float):
		_physics_demo.set_mass(value)
		_mass_label.text="촉수 말단 질량  %.0f kg" % value)
	controls.add_child(mass)
	_physics_stats=_label("",11,MUTED)
	controls.add_child(_physics_stats)
	var events_panel:=PanelContainer.new()
	events_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	events_panel.position=Vector2(-158,28)
	events_panel.custom_minimum_size=Vector2(316,150)
	events_panel.add_theme_stylebox_override("panel",_style(Color(0.055,0.085,0.115,0.92),Color("364b58")))
	root.add_child(events_panel)
	var events_column:=VBoxContainer.new()
	events_panel.add_child(events_column)
	events_column.add_child(_label("EVENT STREAM",12,ACCENT))
	_events=RichTextLabel.new()
	_events.custom_minimum_size=Vector2(280,112)
	_events.add_theme_font_size_override("normal_font_size",12)
	_events.add_theme_color_override("default_color",MUTED)
	_events.bbcode_enabled=true
	_events.scroll_active=false
	events_column.add_child(_events)
	var footer:=_label("좌클릭  위협 배치    ·    우드래그  시점 회전    ·    휠  확대    ·    C  추적 시점    ·    SPACE  일시정지",13,MUTED)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position=Vector2(32,-36)
	root.add_child(footer)
	_result_label=_label("",24,ACCENT)
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_result_label.position=Vector2(-240,32)
	root.add_child(_result_label)
	_update_level_ui()

func _physics_process(delta: float) -> void:
	if not _paused:_time+=delta
	if is_instance_valid(threat.physics_anchor):threat.global_position=threat.physics_anchor.global_position
	if _physics_stats and is_instance_valid(hunter.physics_rig):
		var physics:=hunter.physics_rig.get_snapshot()
		_physics_stats.text="팔 가동성  L %.0f%% / R %.0f%%\n반작용  %.1f N · 구속 %d곳\n방향키: 촉수 당기기 / U: 해제" % [physics.left_arm_mobility*100.0,physics.right_arm_mobility*100.0,physics.force_on_external.length(),physics.grips]
	if not _paused and _chasing and threat.active and hunter.objective.result==&"" and not is_instance_valid(hunter.capture_source):
		var offset:=hunter.position-threat.position
		if offset.length()>0.6:
			threat.position+=offset.normalized()*2.8*delta
		else:
			hunter.try_capture(threat,1.0)
	threat_marker.visible=false
	ring.position=hunter.position+Vector3(0,0.02,0)
	direction_marker.position=hunter.debug_destination+Vector3.UP*0.08
	direction_marker.visible=hunter.state==&"flee"
	if _follow:
		_camera_focus=_camera_focus.lerp(hunter.position+Vector3.UP*0.9,1.0-exp(-delta*5.0))
	camera.position=_camera_focus+Vector3(sin(_camera_yaw)*cos(_camera_pitch),sin(_camera_pitch),cos(_camera_yaw)*cos(_camera_pitch))*_camera_distance
	camera.look_at(_camera_focus)
	_state_label.text=String(hunter.state).to_upper()
	_health.value=hunter.objective.health
	_stamina.value=hunter.stamina/hunter.profile.max_stamina*100.0
	_capture.value=hunter.objective.capture_progress*100.0
	_stats.text="속도   %.1f m/s\n위협   %d개 · 촉수 HP %.0f\n포획   %.1f / %.0f초\n목표 점수   %d" % [Vector2(hunter.velocity.x,hunter.velocity.z).length(),hunter.perceived_threats.size(),threat.health,hunter.objective.capture_progress*hunter.profile.capture_seconds,hunter.profile.capture_seconds,hunter.objective.capture_score]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F10:
				get_tree().paused=false
				get_tree().change_scene_to_file("res://scenes/hunter_fight_lab.tscn")
			KEY_1: _set_level(1)
			KEY_2: _set_level(2)
			KEY_3: _set_level(3)
			KEY_F1: _select_character(0)
			KEY_F2: _select_character(1)
			KEY_F3: _select_character(2)
			KEY_0,KEY_F4: _select_character(3)
			KEY_T: _toggle_threat()
			KEY_A: _toggle_chase()
			KEY_G: _capture_target()
			KEY_H:
				_strong_capture.button_pressed = true
				_capture_target()
			KEY_U: _release_all()
			KEY_J: _grab_arm(&"right_forearm")
			KEY_K: _grab_arm(&"left_forearm")
			KEY_V: _attempt_physical_slash()
			KEY_P: _physics_demo.push_selected()
			KEY_F: _test_fall()
			KEY_B: _toggle_hitboxes()
			KEY_R: _reset()
			KEY_C: _follow=not _follow
			KEY_SPACE:
				_paused=not _paused
				get_tree().paused=_paused
				_log("일시정지" if _paused else "재개")
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_camera_yaw-=event.relative.x*0.006
		_camera_pitch=clampf(_camera_pitch+event.relative.y*0.004,0.12,1.2)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: _camera_distance=maxf(3.5,_camera_distance-0.6)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: _camera_distance=minf(24.0,_camera_distance+0.6)
		if event.button_index==MOUSE_BUTTON_LEFT:
			var origin:=camera.project_ray_origin(event.position)
			var ray:=camera.project_ray_normal(event.position)
			if absf(ray.y)>0.01:
				var point:=origin+ray*(-origin.y/ray.y)
				threat.position=Vector3(clampf(point.x,-12.5,12.5),0,clampf(point.z,-9.5,9.5))
				threat.active=true
				_sync_controls()

func _set_level(level: int) -> void:
	hunter.set_difficulty(level)
	_reset()
	_update_level_ui()
	_log("난이도 %d 적용" % level)

func _select_character(index: int) -> void:
	_release_all()
	hunter.set_character(index)
	_character_picker.select(_character_picker.get_item_index(index))
	_reset()
	_log("캐릭터 선택 · "+HunterAnimation.CHARACTERS[index]["name"])

func _update_level_ui() -> void:
	for i in range(3):
		_level_buttons[i].add_theme_color_override("font_color",ACCENT if i+1==hunter.profile.level else Color.WHITE)
	_explanation.text=["느린 속도로 안전 위치를 찾습니다.\n잡히면 공격 없이 포획됩니다.","빠르게 도망칩니다. 잡히면 엘보우로\n구속을 풀고 다시 도망칩니다.","다가오는 촉수를 향해 돌아서 검격.\n공격 후 거리를 확보합니다."][hunter.profile.level-1]

func _reset() -> void:
	_release_all()
	_chasing=false
	_paused=false
	get_tree().paused=false
	hunter.process_mode=Node.PROCESS_MODE_PAUSABLE
	hunter.reset_target(Vector3.ZERO)
	threat.position=Vector3(-3,0,0)
	threat.reset_threat()
	threat.severable=true
	threat.active=false
	_result_label.text=""
	_sync_controls()

func _toggle_threat() -> void:
	threat.active=not threat.active
	if threat.active and threat.health<=0: threat.reset_threat()
	_sync_controls()
	_log("가상 위협 활성화" if threat.active else "가상 위협 비활성화")

func _toggle_chase() -> void:
	_chasing=not _chasing
	if _chasing:
		threat.active=true
		if threat.health<=0: threat.reset_threat()
	_sync_controls()

func _capture_target() -> void:
	threat.active=true
	if threat.health<=0: threat.reset_threat()
	threat.position=hunter.position+Vector3(0,0,0.65)
	var strength := 3.0 if _strong_capture.button_pressed else 1.0
	var anchor:=_physics_demo.grab(&"torso",strength)
	threat.physics_anchor=anchor
	if hunter.try_capture(threat,strength): _log("촉수 포획 · "+("강한 구속" if strength>1.0 else "보통 구속"))
	_sync_controls()

func _grab_arm(part: StringName) -> void:
	var strength:=3.0 if _strong_capture.button_pressed else 1.0
	threat.physics_anchor=_physics_demo.grab(part,strength)
	threat.active=true
	threat.severable=false
	_log("물리 구속 · "+("오른팔" if part==&"right_forearm" else "왼팔"))
	_sync_controls()

func _attempt_physical_slash() -> void:
	if hunter.profile.level<3:
		_log("검격 테스트는 3단계에서 가능합니다")
		return
	if hunter._action_left<=0.0:hunter._start_action(&"slash",threat)

func _test_fall() -> void:
	if hunter.knock_down(hunter.visual.global_basis.x*16.0+Vector3(0,2,4)):_log("균형 상실 · 넘어짐 / 자동 기상")

func _toggle_hitboxes() -> void:
	if is_instance_valid(hunter.physics_rig):hunter.physics_rig.debug_hitboxes=not hunter.physics_rig.debug_hitboxes

func _release_physics() -> void:
	if is_instance_valid(_physics_demo):_physics_demo.release_all()
	if is_instance_valid(threat):threat.physics_anchor=null

func _release_all() -> void:
	if is_instance_valid(hunter):hunter.release_capture()
	_release_physics()

func _sync_controls() -> void:
	_threat_button.text="T   가상 위협 끄기" if threat.active else "T   가상 위협 켜기"
	_chase_button.text="A   자동 접근 끄기" if _chasing else "A   자동 접근 켜기"

func _state_changed(_previous: StringName, current: StringName) -> void:
	_log("상태 → "+String(current).to_upper())

func _attack_landed(kind: StringName, _source: Node3D, damage: float) -> void:
	_log(("엘보우" if kind==&"elbow" else "검격")+" 적중 · %.0f" % damage)

func _objective_completed(result: StringName, score: int) -> void:
	_result_label.text=("포획 목표 달성" if result==&"captured" else "타겟 탈출")+"  /  %d" % score
	_log(_result_label.text)

func _log(message: String) -> void:
	_event_lines.push_front("[color=#6b8797]%05.1f[/color]  %s" % [_time,message])
	if _event_lines.size()>5: _event_lines.resize(5)
	if _events: _events.text="\n".join(_event_lines)

func _preview_capture() -> void:
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("res://.tools/hunter_preview.png")
	get_tree().quit()

func _preview_gallery() -> void:
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("res://.tools/idle.png")
	for level in [1,2,3]:
		_set_level(level)
		threat.position=Vector3(0,0,1.8 if level==3 else 3.0)
		threat.active=true
		await get_tree().create_timer(0.8 if level==3 else 1.35).timeout
		get_viewport().get_texture().get_image().save_png("res://.tools/level_%d.png" % level)
	_set_level(2)
	_capture_target()
	await get_tree().create_timer(1.15).timeout
	get_viewport().get_texture().get_image().save_png("res://.tools/elbow.png")
	get_tree().quit()

func _preview_hair() -> void:
	_camera_distance=4.3
	_camera_yaw=0.22
	_camera_pitch=0.12
	await get_tree().create_timer(0.85).timeout
	get_viewport().get_texture().get_image().save_png("res://.tools/hair_idle.png")
	_set_level(2)
	threat.position=Vector3(0,0,3)
	threat.active=true
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png("res://.tools/hair_running.png")
	get_tree().quit()

func _preview_characters() -> void:
	_camera_distance=4.6
	_camera_yaw=0.2
	_camera_pitch=0.17
	for index in range(3):
		_select_character(index)
		await get_tree().create_timer(0.8).timeout
		threat.active=false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.tools/character_%d.png" % index)
	_set_level(3)
	threat.position=Vector3(0,0,1.8)
	threat.active=true
	for i in range(120):
		await get_tree().physics_frame
		if hunter.state==&"slash" and hunter._action_elapsed>0.25:break
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/sword_trail.png")
	_set_level(2)
	_strong_capture.button_pressed=true
	_capture_target()
	for i in range(28):await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/capture_wrap.png")
	get_tree().quit()

func _preview_physics() -> void:
	_camera_distance=4.7
	_camera_yaw=0.35
	_camera_pitch=0.16
	for index in range(3):
		_select_character(index)
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.tools/physics_hair_%d.png" % index)
	_set_level(3)
	_grab_arm(&"right_forearm")
	_physics_demo.anchors[&"right_forearm"]["goal"]+=Vector3(0.3,0.15,-0.2)
	for i in range(45):await get_tree().physics_frame
	_attempt_physical_slash()
	for i in range(25):await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/physics_grip.png")
	get_tree().quit()

func _capture_frame(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/"+file+".png")

func _preview_motion() -> void:
	_camera_distance=4.7
	_camera_yaw=0.35
	_camera_pitch=0.20
	for index in range(3):
		_select_character(index)
		await get_tree().create_timer(0.9).timeout
		await _capture_frame("revised_hair_%d"%index)
		_set_level(2)
		threat.position=Vector3(0,0,3)
		threat.active=true
		for i in range(80):await get_tree().physics_frame
		await _capture_frame("revised_run_%d"%index)
	_select_character(0)
	_set_level(3)
	for height in [0.45,0.95,1.55]:
		_reset()
		threat.aim_offset=Vector3.UP*height
		threat.global_position=Vector3(0,0,1.4)
		threat.active=true
		hunter._start_action(&"slash",threat)
		for i in range(23):await get_tree().physics_frame
		await _capture_frame("revised_slash_%.2f"%height)
	_reset()
	_test_fall()
	for i in range(55):await get_tree().physics_frame
	await _capture_frame("revised_fall")
	for i in range(95):await get_tree().physics_frame
	await _capture_frame("revised_get_up")
	for i in range(160):await get_tree().physics_frame
	await _capture_frame("revised_recovered")
	get_tree().quit()

func _preview_trail() -> void:
	_camera_distance=4.7
	_camera_yaw=0.35
	_camera_pitch=0.20
	await get_tree().create_timer(0.8).timeout
	_set_level(3)
	threat.global_position=Vector3(0,0,1.4)
	threat.aim_offset=Vector3.UP*0.95
	threat.active=true
	hunter._decision_left=10.0
	hunter._start_action(&"slash",threat)
	for i in range(35):await get_tree().physics_frame
	await _capture_frame("whole_trail_full")
	threat.active=false
	for i in range(15):await get_tree().physics_frame
	await _capture_frame("whole_trail_fading")
	for i in range(28):await get_tree().physics_frame
	await _capture_frame("whole_trail_gone")
	get_tree().quit()
