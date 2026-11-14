extends Node3D
## The playable merge: native octopus, existing hunter AI, baked tidal arena.
const OCTOPUS = preload("res://scripts/octopus/octopus_controller.gd")
const SECRET_FIGHT = preload("res://scenes/hunter_fight_lab.tscn")
@onready var arena: TidalArena = $TidalColosseum
@onready var hunter: HunterTarget = $HunterTarget
@onready var camera: Camera3D = $Camera3D
var octopus: Node3D
var status: Label
var progress: ProgressBar
var result_label: Label
var character_picker: OptionButton
var level_picker: OptionButton
var pause_button: Button
var camera_yaw: float = 0.3
var camera_pitch: float = 0.65
var camera_distance: float = 9.0
var camera_focus := Vector3.ZERO
var follow_octopus: bool = false
var round_result: StringName = &""
var ready_for_round: bool = false
var _secret_fight: Node3D
var _secret_layer: CanvasLayer
var _secret_resume: Dictionary = {}
var _secret_opening: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -40
	for water_path in ["Terrain/ExposedTidalPools", "Terrain/CoastalWater"]:
		var water: MeshInstance3D = arena.get_node(water_path)
		var material := water.material_override.duplicate() as ShaderMaterial
		material.shader = load("res://assets/environment/tidal_game_water.gdshader")
		water.material_override = material
	_build_ui()
	hunter.arena_bounds = Rect2(-16, -16, 32, 32)
	hunter.objective_completed.connect(_on_result)
	octopus = OCTOPUS.new()
	octopus.name = "Octopus"
	octopus.arena = arena
	octopus.hunter = hunter
	octopus.camera = camera
	octopus.spawn = $Spawns/Octopus.global_position
	octopus.spawn.y = arena.terrain_height(octopus.spawn.x, octopus.spawn.z) + 0.65
	octopus.bridge_failed.connect(_on_bridge_failed)
	octopus.native_reset.connect(func(): ready_for_round = true)
	add_child(octopus)
	_reset_hunter()
	camera_focus = hunter.global_position.lerp(octopus.spawn, 0.55) + Vector3.UP * 0.6
	if "--capture-merged" in OS.get_cmdline_user_args():
		_capture_preview()

func _reset_hunter() -> void:
	var spawn: Vector3 = $Spawns/Hunter.global_position
	spawn.y = arena.terrain_height(spawn.x, spawn.z) + 0.04
	hunter.reset_target(spawn)

func reset_round() -> void:
	if not octopus.fault.is_empty():
		get_tree().reload_current_scene()
		return
	get_tree().paused = false
	round_result = &""
	ready_for_round = false
	octopus.suspended = false
	octopus.request_reset()
	_reset_hunter()
	hunter.process_mode = Node.PROCESS_MODE_DISABLED
	arena.reset_props()
	result_label.text = ""
	pause_button.text = "일시정지 · Esc"

func _physics_process(_delta: float) -> void:
	if is_instance_valid(_secret_layer) or not is_instance_valid(octopus):
		return
	if ready_for_round and hunter.process_mode == Node.PROCESS_MODE_DISABLED and round_result == &"":
		hunter.process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	if is_instance_valid(_secret_layer) or not is_instance_valid(octopus):
		return
	var center: Vector3 = octopus.spawn
	if not octopus.current.is_empty():
		center = octopus.vec(octopus.current.animals[0].center)
	var focus := center if follow_octopus else center.lerp(hunter.global_position, 0.45)
	focus += Vector3.UP * 0.7
	camera_focus = camera_focus.lerp(focus, 1.0 - exp(-delta * 5.0))
	camera.global_position = camera_focus + Vector3(sin(camera_yaw) * cos(camera_pitch),
		sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.look_at(camera_focus)
	progress.value = hunter.objective.capture_progress * 100.0
	var elapsed := hunter.objective.capture_progress * 10.0
	if not octopus.fault.is_empty():
		status.text = octopus.fault
	elif not ready_for_round:
		status.text = "문어 물리 엔진 준비 중…"
	elif get_tree().paused:
		status.text = "일시정지  ·  Esc로 계속"
	elif round_result == &"captured":
		status.text = "10.0 / 10.0초  ·  포획 성공"
	elif is_instance_valid(hunter.capture_source):
		status.text = "붙잡는 중  %.1f / 10.0초" % elapsed
	elif not octopus.grips.is_empty():
		status.text = "촉수로 붙잡는 중…"
	else:
		status.text = "촉수로 미소녀를 붙잡으세요"

func _toggle_pause() -> void:
	if round_result != &"" or not octopus.fault.is_empty():
		return
	get_tree().paused = not get_tree().paused
	octopus.dragging = false
	pause_button.text = "계속 · Esc" if get_tree().paused else "일시정지 · Esc"

func _on_result(value: StringName, _score: int) -> void:
	if round_result != &"":
		return
	round_result = value
	octopus.suspended = true
	octopus.dragging = false
	hunter.process_mode = Node.PROCESS_MODE_DISABLED
	result_label.text = "문어 승리!  ·  연속 10초 포획 성공\nF5 또는 다시 시작" if value == &"captured" else "라운드 종료  ·  F5로 다시 시작"

func _on_bridge_failed(message: String) -> void:
	ready_for_round = false
	hunter.process_mode = Node.PROCESS_MODE_DISABLED
	result_label.text = message + "\n엔진을 확인한 뒤 F5로 다시 시도하세요."

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_secret_layer) or _secret_opening:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: _toggle_pause()
			KEY_F5: reset_round()
			KEY_C: follow_octopus = not follow_octopus
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				character_picker.select(int(event.keycode - KEY_F1))
				_select_character(character_picker.selected)
			KEY_1, KEY_2, KEY_3:
				level_picker.select(int(event.keycode - KEY_1))
				_select_level(level_picker.selected)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_yaw -= event.relative.x * 0.005
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.005, 0.18, 1.25)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(3.5, camera_distance - 0.75)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(24.0, camera_distance + 0.75)

func _input(event: InputEvent) -> void:
	# Deliberately omitted from the normal HUD and menus. Handle before GUI
	# focus so the chord also works after using a picker or pause button.
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key != KEY_F10 or not event.ctrl_pressed or not event.shift_pressed or event.alt_pressed:
		return
	get_viewport().set_input_as_handled()
	if is_instance_valid(_secret_layer):
		_close_secret_fight.call_deferred()
	elif not _secret_opening:
		_secret_opening = true
		_open_secret_fight.call_deferred()

func _open_secret_fight() -> void:
	_secret_opening = false
	if is_instance_valid(_secret_layer) or not is_instance_valid(octopus):
		return
	_secret_resume = {"paused": get_tree().paused, "suspended": octopus.suspended,
		"arena_mode": arena.process_mode, "hunter_mode": hunter.process_mode, "hud": [],
		"space": get_world_3d().space, "colliders": []}
	_secret_resume.space_active = PhysicsServer3D.space_is_active(_secret_resume.space)
	# Keep the native process and round alive, with no background stepping.
	octopus.suspended = true
	octopus.dragging = false
	octopus.inbox_lock.lock()
	octopus.auto_step = false
	octopus.latest_command = ""
	octopus.inbox_lock.unlock()
	# Preserve joints, body velocities and solver contacts instead of removing
	# the held character's articulated bodies from their physics space.
	for collider: CollisionObject3D in find_children("*", "CollisionObject3D", true, false):
		_secret_resume.colliders.append([collider, collider.disable_mode])
		collider.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	PhysicsServer3D.space_set_active(_secret_resume.space, false)
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	hunter.process_mode = Node.PROCESS_MODE_DISABLED
	for child in get_children():
		if child is CanvasLayer and child.visible:
			_secret_resume.hud.append(child)
			child.hide()
	get_tree().paused = false
	_secret_layer = CanvasLayer.new()
	_secret_layer.name = "SecretFight"
	_secret_layer.layer = 100
	add_child(_secret_layer)
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	_secret_layer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	_secret_fight = SECRET_FIGHT.instantiate()
	_secret_fight.entry_character_index = hunter.character_index
	_secret_fight.return_action = _close_secret_fight
	viewport.add_child(_secret_fight)

func _close_secret_fight() -> void:
	if not is_instance_valid(_secret_layer):
		return
	_secret_layer.hide()
	_secret_layer.queue_free()
	_secret_layer = null
	_secret_fight = null
	get_tree().paused = bool(_secret_resume.paused)
	arena.process_mode = int(_secret_resume.arena_mode)
	hunter.process_mode = int(_secret_resume.hunter_mode) if octopus.fault.is_empty() else Node.PROCESS_MODE_DISABLED
	for state in _secret_resume.colliders:
		if is_instance_valid(state[0]):
			state[0].disable_mode = int(state[1])
	PhysicsServer3D.space_set_active(_secret_resume.space, bool(_secret_resume.space_active))
	# Start the next native step on a fresh slot, without catching up time spent
	# in the fight using an old contact/force sample.
	octopus.inbox_lock.lock()
	octopus.next_due_usec = Time.get_ticks_usec() + 16667
	octopus.inbox_lock.unlock()
	octopus.suspended = bool(_secret_resume.suspended)
	for layer in _secret_resume.hud:
		if is_instance_valid(layer):
			layer.show()
	_secret_resume.clear()

func _select_character(index: int) -> void:
	octopus.release_grips()
	hunter.set_character(index)
	reset_round()

func _select_level(index: int) -> void:
	octopus.release_grips()
	hunter.set_difficulty(index + 1)
	reset_round()

func _label(text: String, size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.position = Vector2(20, 20)
	margin.custom_minimum_size = Vector2(385, 0)
	layer.add_child(margin)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.08, 0.10, 0.90)
	style.border_color = Color("397979")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label("O C T O  /  갯벌 추격전", 25, Color("dcf1e8")))
	box.add_child(_label("목표 · 미소녀를 붙잡고 연속 10초 유지", 17, Color("9fe4ce")))
	status = _label("문어 물리 엔진 준비 중…", 15, Color("ffffff"))
	box.add_child(status)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 20)
	progress.show_percentage = false
	box.add_child(progress)
	box.add_child(_label("놓치면 진행 시간이 0초로 초기화됩니다", 13, Color("a5b9ba")))
	var row := HBoxContainer.new()
	box.add_child(row)
	character_picker = OptionButton.new()
	for text in ["1 · Lily  [F1]", "2 · Rin  [F2]", "3 · Aki  [F3]", "0 · Lily Orange  [F4]"]:
		character_picker.add_item(text)
	character_picker.item_selected.connect(_select_character)
	row.add_child(character_picker)
	level_picker = OptionButton.new()
	for text in ["1 · 도주", "2 · 엘보우", "3 · 검격"]:
		level_picker.add_item(text)
	level_picker.item_selected.connect(_select_level)
	row.add_child(level_picker)
	box.add_child(HSeparator.new())
	box.add_child(_label("촉수 조작  ·  뻗기 / 뒤로 젓기", 16, Color("dcf1e8")))
	box.add_child(_label("왼쪽 앞    F / D       오른쪽 앞    J / K\n왼쪽 옆앞  S / A       오른쪽 옆앞  L / ;\n왼쪽 옆뒤  R / E       오른쪽 옆뒤  U / I\n왼쪽 뒤    W / Q       오른쪽 뒤    O / P", 15, Color("d2dddd")))
	box.add_child(_label("키를 놓으면 촉수 회수 / 앞쪽으로 복귀\nSpace · 모든 잡기 해제 (누르는 동안 잡기 금지)\n문어 좌드래그 · 힘으로 당기기\n우드래그 / 휠 · 시점 회전 / 확대\nC · 문어 / 둘 다 추적    1·2·3 · 난이도", 14, Color("a5b9ba")))
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var restart := Button.new()
	restart.text = "다시 시작 · F5"
	restart.pressed.connect(reset_round)
	buttons.add_child(restart)
	pause_button = Button.new()
	pause_button.text = "일시정지 · Esc"
	pause_button.pressed.connect(_toggle_pause)
	buttons.add_child(pause_button)
	result_label = _label("", 26, Color("ffdc94"))
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	result_label.offset_left = 430
	result_label.offset_right = -24
	result_label.offset_top = 36
	result_label.offset_bottom = 140
	layer.add_child(result_label)

func _capture_preview() -> void:
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/octopus_merged.png")
	get_tree().quit()
