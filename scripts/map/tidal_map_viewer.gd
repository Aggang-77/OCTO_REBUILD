extends Node3D
## Orbit/ground-level map preview with a force-based rigid-body grabber.

@onready var arena: TidalArena = $TidalColosseum
var camera: Camera3D
var _focus := Vector3(0, 1.0, 0)
var _yaw := 0.65
var _pitch := 0.69
var _distance := 64.0
var _grabbed: RigidBody3D
var _grab_local := Vector3.ZERO
var _grab_distance := 10.0
var _hovered: RigidBody3D
var _hover_label: Label
var _status: Label
var _ui: Control
var _selection: MeshInstance3D
var _debug_bodies: Array[MeshInstance3D] = []
var _debug_visible := false
var _capture_frames := 0
var _capture_path := ""

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "MapPreviewCamera"
	camera.fov = 48.0
	camera.near = 0.08
	camera.far = 1000
	add_child(camera)
	camera.current = true
	_build_interface()
	_build_selection()
	_update_camera()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map-capture="):
			_capture_path = argument.trim_prefix("--map-capture=")
		if argument == "--map-ground":
			_set_view(2)
		if argument == "--map-detail":
			_set_view(3)

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.1, 0.09, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_interface() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MapPreviewHUD"
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	var theme := Theme.new()
	theme.default_font = load("res://assets/ui/malgun.ttf")
	_ui.theme = theme
	var heading := VBoxContainer.new()
	heading.position = Vector2(34, 28)
	heading.add_theme_constant_override("separation", 5)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(heading)
	heading.add_child(_label("O C T O P U S   /   E N V I R O N M E N T   0 1", 12, Color("e0e6cf")))
	heading.add_child(_label("밀물이 잊은 원형극장", 31, Color("fff5d9")))
	heading.add_child(_label("TIDAL COLOSSEUM     ·     갯벌과 폐허", 13, Color("e0e3cc")))
	var tide := VBoxContainer.new()
	tide.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tide.position = Vector2(-290, 33)
	tide.size.x = 255
	tide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(tide)
	var tide_label := _label("◌  LOW TIDE / 간조", 17, Color("fff5d9"))
	tide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tide.add_child(tide_label)
	var detail := _label("36개 아치 구간  ·  얕은 조수 웅덩이", 12, Color("e0e3cc"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tide.add_child(detail)
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(34, 145)
	toolbar.add_theme_constant_override("separation", 7)
	_ui.add_child(toolbar)
	for entry: Array in [["1  전체", 1], ["2  바닥", 2], ["3  소품", 3]]:
		var button := Button.new()
		button.text = entry[0]
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", Color("f5efda"))
		button.add_theme_stylebox_override("normal", _style(Color(0.12, 0.18, 0.16, 0.78), Color(0.8, 0.8, 0.66, 0.2)))
		button.add_theme_stylebox_override("hover", _style(Color(0.26, 0.34, 0.29, 0.95), Color("e2d6ae")))
		button.add_theme_stylebox_override("pressed", _style(Color("536855"), Color("e2d6ae")))
		var view: int = entry[1]
		button.pressed.connect(func(): _set_view(view))
		toolbar.add_child(button)
	var lab_button := Button.new()
	lab_button.text = "캐릭터 테스트 →"
	lab_button.add_theme_font_size_override("font_size", 13)
	lab_button.add_theme_stylebox_override("normal", _style(Color(0.12, 0.18, 0.16, 0.9), Color("d6d0a2")))
	lab_button.add_theme_stylebox_override("hover", _style(Color("536855"), Color("e2d6ae")))
	lab_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tidal_hunter_lab.tscn"))
	toolbar.add_child(lab_button)
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 24
	footer.offset_right = -24
	footer.offset_top = -77
	footer.offset_bottom = -20
	footer.add_theme_stylebox_override("panel", _style(Color(0.09, 0.15, 0.14, 0.88), Color(0.65, 0.73, 0.61, 0.22)))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(footer)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(row)
	var controls := _label("우드래그 회전   ·   휠 확대   ·   WASD 이동   ·   좌드래그 소품 집기   ·   Space 던지기", 13, Color("ecebd4"))
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(controls)
	row.add_child(_label("R 재배치   /   B 충돌체   /   Tab UI", 12, Color("b5c5b1")))
	_status = _label("중앙은 문어 배치 공간 · 소품 %d개 물리 적용" % arena.props.size(), 12, Color("eef0d9"))
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(35, -110)
	_ui.add_child(_status)
	_hover_label = _label("", 15, Color("fff2bd"))
	_ui.add_child(_hover_label)

func _build_selection() -> void:
	_selection = MeshInstance3D.new()
	_selection.name = "HoveredPropRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.52
	ring.outer_radius = 0.55
	ring.rings = 40
	ring.ring_segments = 6
	_selection.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f1d9a0")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection.material_override = material
	_selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection.visible = false
	add_child(_selection)

func _set_view(view: int) -> void:
	_release()
	match view:
		1:
			_focus = Vector3(0, 1.0, 0)
			_yaw = 0.65
			_pitch = 0.69
			_distance = 64
		2:
			_focus = Vector3(0, 1.5, -2.0)
			_yaw = 0.32
			_pitch = 0.15
			_distance = 17
		3:
			_focus = Vector3(-8.8, 0.55, -3.2)
			_yaw = 0.85
			_pitch = 0.48
			_distance = 9.5
	_update_camera()

func _update_camera() -> void:
	camera.position = _focus + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	camera.look_at(_focus)

func _raycast() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 180.0, 17)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _begin_grab() -> void:
	var hit := _raycast()
	if hit.is_empty() or not hit.collider is RigidBody3D:
		return
	var body: RigidBody3D = hit.collider
	if not body.is_in_group("tidal_props"):
		return
	_grabbed = body
	_grab_local = body.to_local(hit.position)
	_grab_distance = camera.global_position.distance_to(hit.position)
	body.sleeping = false
	_status.text = "%s · %.2f kg   /   드래그 이동 · 휠 거리 · Space 던지기" % [body.get_meta("display_name", "소품"), body.mass]

func _release(throw_body: bool = false) -> void:
	if is_instance_valid(_grabbed) and throw_body:
		_grabbed.apply_central_impulse(-camera.global_basis.z * _grabbed.mass * 8.0)
	_grabbed = null
	if is_instance_valid(_status):
		_status.text = "중앙은 문어 배치 공간 · 소품 %d개 물리 적용" % arena.props.size()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_grabbed):
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var target := origin + direction * _grab_distance
	# The held point cannot pass through scenery, even when the mouse points behind a wall.
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.position + hit.normal * 0.28
	var contact := _grabbed.to_global(_grab_local)
	var offset := contact - _grabbed.global_position
	var point_velocity := _grabbed.linear_velocity + _grabbed.angular_velocity.cross(offset)
	var force := (target - contact) * _grabbed.mass * 65.0 - point_velocity * _grabbed.mass * 12.0
	force = force.limit_length(_grabbed.mass * 190.0)
	_grabbed.sleeping = false
	_grabbed.apply_force(force, offset)

func _process(delta: float) -> void:
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var movement := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): movement += forward
	if Input.is_physical_key_pressed(KEY_S): movement -= forward
	if Input.is_physical_key_pressed(KEY_D): movement += right
	if Input.is_physical_key_pressed(KEY_A): movement -= right
	if movement.length_squared() > 0:
		_focus += movement.normalized() * delta * (14.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0)
		_focus.x = clampf(_focus.x, -35, 35)
		_focus.z = clampf(_focus.z, -35, 35)
		_update_camera()
	_update_hover()
	if not _capture_path.is_empty():
		_capture_frames += 1
		if _capture_frames == 70:
			_capture.call_deferred()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(_capture_path)
	print("MAP_SCREENSHOT: ", _capture_path, " result=", result)
	get_tree().quit(0 if result == OK else 1)

func _update_hover() -> void:
	var hit := _raycast()
	_hovered = null
	if not hit.is_empty() and hit.collider is RigidBody3D and hit.collider.is_in_group("tidal_props"):
		_hovered = hit.collider
	var body: RigidBody3D = _grabbed if is_instance_valid(_grabbed) else _hovered
	_selection.visible = is_instance_valid(body)
	_hover_label.visible = is_instance_valid(body)
	if not is_instance_valid(body):
		return
	_selection.position = Vector3(body.global_position.x, arena.terrain_height(body.global_position.x, body.global_position.z) + 0.04, body.global_position.z)
	_hover_label.position = get_viewport().get_mouse_position() + Vector2(18, 18)
	_hover_label.text = "%s · %.2f kg" % [body.get_meta("display_name", "소품"), body.mass]

func _toggle_colliders() -> void:
	_debug_visible = not _debug_visible
	if _debug_bodies.is_empty():
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.4, 1.0, 0.72, 0.23)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		for body in arena.props:
			var collision := body.get_node("CollisionShape3D") as CollisionShape3D
			var display := MeshInstance3D.new()
			display.mesh = collision.shape.get_debug_mesh()
			display.material_override = material
			display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(display)
			_debug_bodies.append(display)
	for display in _debug_bodies:
		display.visible = _debug_visible

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_yaw -= event.relative.x * 0.005
			_pitch = clampf(_pitch + event.relative.y * 0.004, 0.055, 1.45)
			_update_camera()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var right := camera.global_basis.x
			var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
			_focus += (-right * event.relative.x + forward * event.relative.y) * _distance * 0.0012
			_update_camera()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin_grab()
			else: _release()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if is_instance_valid(_grabbed):
				_grab_distance = clampf(_grab_distance + direction * 0.7, 1.5, 100.0)
			else:
				_distance = clampf(_distance * (1.0 + direction * 0.08), 2.0, 105.0)
				_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_view(1)
			KEY_2: _set_view(2)
			KEY_3: _set_view(3)
			KEY_SPACE: _release(true)
			KEY_R:
				_release()
				arena.reset_props()
			KEY_TAB: _ui.visible = not _ui.visible
			KEY_B: _toggle_colliders()
			KEY_ESCAPE: _release()
			KEY_F:
				if is_instance_valid(_hovered):
					_focus = _hovered.global_position
					_distance = 4.0
					_update_camera()
