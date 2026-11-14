extends "res://scripts/hunter_lab.gd"
## Environment adapter. Keep the original lab controls; project test threats onto
## the actual mudflat instead of the old laboratory's y=0 plane.

var arena: TidalArena

func _ready() -> void:
	super._ready()
	_reset()
	_camera_distance = 7.8
	_camera_pitch = 0.26
	_camera_yaw = 0.25
	_camera_focus = hunter.position + Vector3.UP * 0.9
	_add_map_link()
	if "--capture-tidal-lab" in OS.get_cmdline_user_args():
		_capture_tidal_lab()

func _build_world() -> void:
	arena = get_node("TidalColosseum") as TidalArena
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	super._build_world()
	# Replace only the old lab's generated floor, grid, blocks, walls and lights.
	# Its target, threat, capture preview, physics demo, camera and indicators remain.
	for child in get_children():
		if child == ring or child == direction_marker:
			continue
		if child is WorldEnvironment or child is DirectionalLight3D or child is StaticBody3D or child is MeshInstance3D:
			remove_child(child)
			child.free()
	safe_zone.position.y = arena.terrain_height(safe_zone.position.x, safe_zone.position.z) + 0.02

func _reset() -> void:
	super._reset()
	if not is_instance_valid(arena):
		return
	var marker: Marker3D = arena.get_node("SpawnPoints/HunterSpawn")
	var spawn := marker.global_position
	spawn.y = arena.terrain_height(spawn.x, spawn.z) + 0.035
	hunter.reset_target(spawn)
	threat.position = spawn + Vector3(-3, 0, 0)
	_ground_virtual_threat()
	arena.reset_props()

func _ground_virtual_threat() -> void:
	if not is_instance_valid(threat) or is_instance_valid(threat.physics_anchor):
		return
	threat.position.y = arena.terrain_height(threat.position.x, threat.position.z) + 0.025

func _physics_process(delta: float) -> void:
	# The inherited chase moves horizontally/vertically; keep a free tip on the
	# local ground both before sensing and after its movement. Real grips keep
	# their physical anchor and must never be terrain-snapped.
	_ground_virtual_threat()
	super._physics_process(delta)
	_ground_virtual_threat()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var origin := camera.project_ray_origin(event.position)
		var query := PhysicsRayQueryParameters3D.create(origin,
			origin + camera.project_ray_normal(event.position) * 250.0, 1)
		var ground := get_world_3d().direct_space_state.intersect_ray(query)
		if not ground.is_empty():
			threat.position = Vector3(clampf(ground.position.x, -12.5, 12.5), ground.position.y,
				clampf(ground.position.z, -9.5, 9.5))
			_ground_virtual_threat()
			threat.active = true
			_sync_controls()
		return
	super._unhandled_input(event)

func _add_map_link() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MapNavigation"
	add_child(layer)
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(control)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	row.position = Vector2(-158, 190)
	control.add_child(row)
	var overview := _button("갯벌 맵 둘러보기", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/tidal_colosseum.tscn"))
	row.add_child(overview)
	var original := _button("기존 실험실", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/hunter_lab.tscn"))
	row.add_child(original)

func _capture_tidal_lab() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/tidal_hunter_lab.png")
	_set_level(3)
	_strong_capture.button_pressed = true
	_grab_arm(&"right_forearm")
	_attempt_physical_slash()
	for i in range(22):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tools/tidal_hunter_grip.png")
	get_tree().quit()
