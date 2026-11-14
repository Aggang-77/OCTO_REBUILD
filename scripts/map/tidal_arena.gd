class_name TidalArena
extends Node3D
## Reusable environment. Geometry is baked by tools/build_tidal_map.gd for editor visibility.
## Layers: environment 1, hunter 2, hitboxes 4, tentacles 8, movable props 16.

const WATER_LEVEL := -0.13
const ARENA_RADIUS := 18.6
const MAP_SEED := 731204
const UNDERWATER := "res://assets/environment/underwater/"
const NATURE := "res://assets/environment/nature/"
const POOLS := [Vector4(0.0, 0.0, 4.7, 3.6), Vector4(-8.0, 4.5, 3.0, 2.2),
	Vector4(7.5, -5.0, 3.6, 2.5), Vector4(-5.0, -9.0, 2.5, 2.2)]

@export_flags_3d_physics var prop_collision_layer: int = 16

var props: Array[RigidBody3D] = []
var _initial_transforms: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _ground_noise := FastNoiseLite.new()
var _stone_builder: SurfaceTool
var _stone_material: ShaderMaterial
var _stone_colors: Array[Color] = [Color("b6ab8c"), Color("a99c7f"), Color("c5b89a"),
	Color("918d73"), Color("bfb39a"), Color("a49c86")]
var _assets: Dictionary = {}

func _init() -> void:
	_ground_noise.seed = MAP_SEED
	_ground_noise.frequency = 0.25
	_ground_noise.fractal_octaves = 3

func _ready() -> void:
	for node in find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		body.collision_layer = prop_collision_layer
		props.append(body)
		_initial_transforms[body] = body.transform

func terrain_height(x: float, z: float) -> float:
	var radius := Vector2(x, z).length()
	var height := 0.11 + _ground_noise.get_noise_2d(x, z) * 0.15
	height += sin(x * 1.7 + z * 0.6) * 0.009
	for pool: Vector4 in POOLS:
		var distance := Vector2((x - pool.x) / pool.z, (z - pool.y) / pool.w).length()
		height -= exp(-pow(distance * 1.32, 4.0)) * 0.58
	var channel_x := sin(z * 0.24) * 3.2 + sin(z * 0.56) * 0.9
	var channel := exp(-pow((x - channel_x) / 0.75, 2.0))
	if radius < 18.7:
		height -= channel * 0.43
	if radius > 18.5:
		height = lerpf(height, 0.24, smoothstep(18.5, 20.0, radius))
	if radius > 25.0:
		height -= pow((radius - 25.0) / 3.5, 1.7) * 1.5
	return height

func reset_props() -> void:
	for body in props:
		if not is_instance_valid(body):
			continue
		body.freeze = true
		body.transform = _initial_transforms[body]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()
		body.freeze = false
		body.sleeping = false

func _physics_process(delta: float) -> void:
	for body in props:
		if not is_instance_valid(body):
			continue
		if body.position.y < -8.0 or Vector2(body.position.x, body.position.z).length() > 70.0:
			body.transform = _initial_transforms[body]
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.reset_physics_interpolation()
			continue
		if body.sleeping or body.freeze:
			continue
		var point := body.global_position
		var half_height: float = body.get_meta("half_height", 0.3)
		var water := WATER_LEVEL if Vector2(point.x, point.z).length() < ARENA_RADIUS else -0.42
		var submerged := clampf((water - point.y + half_height) / (half_height * 2.0), 0.0, 1.0)
		if submerged > 0.0:
			var flotation: float = body.get_meta("flotation", 0.2)
			body.apply_central_force(Vector3.UP * body.mass * 9.8 * submerged * flotation)
			body.apply_central_force(-body.linear_velocity * body.mass * submerged * 2.1)
			body.apply_torque(-body.angular_velocity * body.mass * submerged * 0.55)
		var floor_y := terrain_height(point.x, point.z)
		if point.y - half_height < floor_y + 0.09 and floor_y < 0.12:
			var horizontal := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
			body.apply_central_force(-horizontal * body.mass * 2.2)
			body.angular_velocity *= exp(-delta * 0.7)

func build_map() -> void:
	_rng.seed = MAP_SEED
	_build_lighting()
	_build_terrain()
	_build_colosseum()
	_build_set_dressing()
	_build_props()
	_build_markers()

func _container(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node

func _build_lighting() -> void:
	var lighting := _container("Lighting")
	var world := WorldEnvironment.new()
	world.name = "CoastalAtmosphere"
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("7faaa8")
	sky_material.sky_horizon_color = Color("d9d8bd")
	sky_material.ground_bottom_color = Color("8bada4")
	sky_material.ground_horizon_color = Color("d9d8bd")
	sky_material.sky_curve = 0.22
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5c9bf")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b6c9ba")
	environment.fog_light_energy = 0.75
	environment.fog_density = 0.0017
	world.environment = environment
	lighting.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	sun.rotation_degrees = Vector3(-32, -36, 0)
	sun.light_color = Color("ffe4b3")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.035
	lighting.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "SeaBounce"
	fill.rotation_degrees = Vector3(-60, 145, 0)
	fill.light_color = Color("8fb9bb")
	fill.light_energy = 0.18
	lighting.add_child(fill)

func _build_terrain() -> void:
	var terrain := _container("Terrain")
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 160
	var spacing := 57.0 / float(steps)
	for iz in range(steps):
		for ix in range(steps):
			var x := -28.5 + ix * spacing
			var z := -28.5 + iz * spacing
			if Vector2(x + spacing * 0.5, z + spacing * 0.5).length() > 28.0:
				continue
			var a := Vector3(x, terrain_height(x, z), z)
			var b := Vector3(x + spacing, terrain_height(x + spacing, z), z)
			var c := Vector3(x + spacing, terrain_height(x + spacing, z + spacing), z + spacing)
			var d := Vector3(x, terrain_height(x, z + spacing), z + spacing)
			for point: Vector3 in [a, b, c, a, c, d]:
				builder.set_uv(Vector2(point.x, point.z) * 0.1)
				builder.add_vertex(point)
	builder.generate_normals()
	builder.index()
	var ground_mesh := builder.commit()
	var mud := ShaderMaterial.new()
	mud.shader = load("res://assets/environment/mud.gdshader")
	ground_mesh.surface_set_material(0, mud)
	ResourceSaver.save(ground_mesh, "res://assets/environment/generated/mudflat.res")
	ground_mesh = load("res://assets/environment/generated/mudflat.res")
	var ground := MeshInstance3D.new()
	ground.name = "SculptedMudflat"
	ground.mesh = ground_mesh
	terrain.add_child(ground)
	var body := StaticBody3D.new()
	body.name = "MudflatCollision"
	body.collision_layer = 1
	body.collision_mask = 31
	body.add_to_group("tidal_ground", true)
	var physics := PhysicsMaterial.new()
	physics.friction = 0.95
	physics.bounce = 0.0
	body.physics_material_override = physics
	terrain.add_child(body)
	var collision := CollisionShape3D.new()
	collision.shape = ground_mesh.create_trimesh_shape()
	body.add_child(collision)
	var water_material := ShaderMaterial.new()
	water_material.shader = load("res://assets/environment/tidal_water.gdshader")
	var pools := MeshInstance3D.new()
	pools.name = "ExposedTidalPools"
	var disk := CylinderMesh.new()
	disk.top_radius = ARENA_RADIUS
	disk.bottom_radius = ARENA_RADIUS
	disk.height = 0.015
	disk.radial_segments = 160
	pools.mesh = disk
	pools.material_override = water_material
	pools.position.y = WATER_LEVEL
	terrain.add_child(pools)
	var ocean := MeshInstance3D.new()
	ocean.name = "CoastalWater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600, 1600)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	ocean.mesh = plane
	ocean.position.y = -0.42
	var ocean_material := water_material.duplicate() as ShaderMaterial
	ocean_material.set_shader_parameter("deep_color", Color("42615f"))
	ocean_material.set_shader_parameter("light_color", Color("6f8980"))
	ocean_material.set_shader_parameter("wave_strength", 0.025)
	ocean.material_override = ocean_material
	terrain.add_child(ocean)

func _build_colosseum() -> void:
	var ruins := _container("ColosseumRuins")
	_stone_builder = SurfaceTool.new()
	_stone_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	_stone_material = ShaderMaterial.new()
	_stone_material.shader = load("res://assets/environment/ancient_stone.gdshader")
	# Continuous stepped seating, with four radial entrances.
	for tier in range(5):
		var inner := 18.5 + tier * 0.68
		var top := 0.35 + tier * 0.38
		for segment in range(108):
			if segment % 27 in [0, 1, 26]:
				continue
			var angle := TAU * segment / 108.0
			_sector(inner, inner + 0.66, 0.05, top, angle + 0.003, angle + TAU / 108.0 - 0.003)
	# Two stacked arcades. The camera-facing wall has collapsed to reveal the arena.
	for bay in range(36):
		var angle := TAU * bay / 36.0
		var front := _angle_distance(angle, 0.65) < 0.82
		var ruined := bay in [8, 9, 17, 28, 29, 30]
		var radial := Vector3(sin(angle), 0, cos(angle))
		var frame := Basis(Vector3.UP, angle)
		var center := radial * 23.1
		if front:
			for course in range(1 + bay % 3):
				_stone_box(center + Vector3.UP * (0.28 + course * 0.43), Vector3(0.9, 0.41, 1.25), frame)
			continue
		for level in range(2):
			if level == 1 and ruined:
				continue
			var base_y := 0.24 + level * 3.75
			# Pier at the start of each bay; the arch spans to the next pier.
			for course in range(5):
				_stone_box(center + Vector3.UP * (base_y + 0.225 + course * 0.45), Vector3(0.88, 0.43, 1.42), frame)
			_stone_box(center + Vector3.UP * (base_y + 2.26), Vector3(1.04, 0.18, 1.56), frame)
			var mid_angle := angle + PI / 36.0
			var arch_frame := Basis(Vector3.UP, mid_angle)
			var arch_center := Vector3(sin(mid_angle), 0, cos(mid_angle)) * 23.1 + Vector3.UP * (base_y + 2.16)
			for wedge in range(9):
				if ruined and wedge > 4:
					continue
				_arch_wedge(arch_center, arch_frame, 1.48, 1.86, wedge * PI / 9.0 + 0.008, (wedge + 1) * PI / 9.0 - 0.008, 1.38)
			if not ruined:
				_stone_box(Vector3(sin(mid_angle), 0, cos(mid_angle)) * 23.1 + Vector3.UP * (base_y + 3.68), Vector3(4.05, 0.23, 1.68), arch_frame)
				if level == 1:
					for tooth in range(3):
						var tooth_angle := angle + (tooth + 0.5) * TAU / 108.0
						_stone_box(Vector3(sin(tooth_angle), 0, cos(tooth_angle)) * 23.1 + Vector3.UP * 8.1,
							Vector3(1.1, _rng.randf_range(0.22, 0.58), 1.35), Basis(Vector3.UP, tooth_angle))
	# Low inner retaining ring, broken at entrances.
	for bay in range(72):
		if bay % 18 in [0, 1, 17]:
			continue
		var a := TAU * bay / 72.0
		_sector(18.1, 18.46, 0.10, 0.53, a + 0.006, a + TAU / 72.0 - 0.006)
	# Half-buried fallen columns and stone slabs around the collapsed front.
	for i in range(44):
		var a := _rng.randf_range(-0.25, 1.48)
		var r := _rng.randf_range(19.2, 25.4)
		var position_3d := Vector3(sin(a) * r, 0.35, cos(a) * r)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, TAU), _rng.randf_range(-0.22, 0.22)))
		_stone_box(position_3d, Vector3(_rng.randf_range(0.6, 1.6), _rng.randf_range(0.3, 0.8), _rng.randf_range(0.5, 1.2)), basis)
	var stone_mesh := _stone_builder.commit()
	stone_mesh.surface_set_material(0, _stone_material)
	ResourceSaver.save(stone_mesh, "res://assets/environment/generated/colosseum.res")
	stone_mesh = load("res://assets/environment/generated/colosseum.res")
	var display := MeshInstance3D.new()
	display.name = "WeatheredLimestone"
	display.mesh = stone_mesh
	ruins.add_child(display)
	var collision_body := StaticBody3D.new()
	collision_body.name = "ArchesAndSeatingCollision"
	collision_body.collision_layer = 1
	collision_body.collision_mask = 31
	ruins.add_child(collision_body)
	var collision := CollisionShape3D.new()
	collision.shape = stone_mesh.create_trimesh_shape()
	collision_body.add_child(collision)
	_stone_builder = null

func _angle_distance(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))

func _stone_box(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append_stone(box, Transform3D(basis, center))

func _append_stone(mesh: Mesh, transform_3d: Transform3D) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var color := _stone_colors[_rng.randi_range(0, _stone_colors.size() - 1)].srgb_to_linear()
	for index in indices:
		_stone_builder.set_normal((transform_3d.basis * normals[index]).normalized())
		_stone_builder.set_color(color)
		_stone_builder.add_vertex(transform_3d * vertices[index])

func _sector(inner: float, outer: float, bottom: float, top: float, a: float, b: float) -> void:
	var corners: Array[Vector3] = []
	for y: float in [bottom, top]:
		for spec: Vector2 in [Vector2(inner, a), Vector2(outer, a), Vector2(outer, b), Vector2(inner, b)]:
			corners.append(Vector3(sin(spec.y) * spec.x, y, cos(spec.y) * spec.x))
	_hexahedron(corners)

func _arch_wedge(center: Vector3, basis: Basis, inner: float, outer: float, a: float, b: float, depth: float) -> void:
	var corners: Array[Vector3] = []
	for z: float in [-depth * 0.5, depth * 0.5]:
		for spec: Vector2 in [Vector2(inner, a), Vector2(outer, a), Vector2(outer, b), Vector2(inner, b)]:
			corners.append(center + basis * Vector3(cos(spec.y) * spec.x, sin(spec.y) * spec.x, z))
	_hexahedron(corners)

func _hexahedron(corners: Array[Vector3]) -> void:
	var color := _stone_colors[_rng.randi_range(0, _stone_colors.size() - 1)].srgb_to_linear()
	var center := Vector3.ZERO
	for p in corners:
		center += p / 8.0
	for face: Array in [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]:
		var normal := (corners[face[1]] - corners[face[0]]).cross(corners[face[2]] - corners[face[0]]).normalized()
		var face_center: Vector3 = (corners[face[0]] + corners[face[1]] + corners[face[2]] + corners[face[3]]) / 4.0
		# Godot uses clockwise front faces. Orient geometry and lighting outward.
		if normal.dot(face_center - center) < 0:
			normal = -normal
		else:
			face.reverse()
		for index: int in [face[0], face[1], face[2], face[0], face[2], face[3]]:
			_stone_builder.set_normal(normal)
			_stone_builder.set_color(color)
			_stone_builder.add_vertex(corners[index])

func _asset(asset_name: String, nature: bool = false) -> Node3D:
	var asset_path := (NATURE if nature else UNDERWATER) + asset_name + (".gltf" if nature else ".glb")
	if not _assets.has(asset_path):
		_assets[asset_path] = load(asset_path)
	var instance: Node3D = _assets[asset_path].instantiate()
	# Unpack imported model nodes when baking, so every decoration is editable.
	instance.scene_file_path = ""
	return instance

func _place(parent: Node3D, asset_name: String, x: float, z: float, size: float, nature: bool = false, solid: bool = false) -> Node3D:
	var instance := _asset(asset_name, nature)
	instance.name = asset_name
	instance.scale = Vector3.ONE * size
	instance.rotation.y = _rng.randf_range(0, TAU)
	instance.position = Vector3(x, terrain_height(x, z) - 0.025, z)
	parent.add_child(instance)
	if solid:
		for child in instance.find_children("*", "MeshInstance3D", true, false):
			child.create_trimesh_collision()
	return instance

func _build_set_dressing() -> void:
	var shoreline := _container("ShorelineRocks")
	var vegetation := _container("SaltmarshAndSeaweed")
	var relics := _container("SunkenRelics")
	for i in range(65):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(16.0, 19.0)
		_place(shoreline, "Rock_Medium_" + str(i % 3 + 1), sin(a) * r, cos(a) * r, _rng.randf_range(0.26, 0.65), true, true)
	for i in range(95):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(6.8, 18.0)
		_place(shoreline, "Pebble_Round_" + str(i % 3 + 1), sin(a) * r, cos(a) * r, _rng.randf_range(0.8, 2.0), true)
	# Small patches follow the wet/dry edge; the central five metres remain clear.
	for i in range(150):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(9.0, 22.0)
		var x := sin(a) * r
		var z := cos(a) * r
		var grass := "Grass_Wispy_Tall" if i % 4 == 0 else "Grass_Wispy_Short"
		_place(vegetation, grass, x, z, _rng.randf_range(0.35, 0.75), true)
	for i in range(30):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(17.0, 22.0)
		_place(vegetation, "Fern_1", sin(a) * r, cos(a) * r, _rng.randf_range(0.12, 0.20), true)
	for i in range(28):
		var pool: Vector4 = POOLS[i % POOLS.size()]
		var angle := _rng.randf_range(0, TAU)
		var x := pool.x + sin(angle) * pool.z * 0.85
		var z := pool.y + cos(angle) * pool.w * 0.85
		var seaweed := "seaweed_tall" if i % 2 == 0 else "seaweed_bush"
		_place(vegetation, seaweed, x, z, _rng.randf_range(0.32, 0.65))
	for spec: Vector3 in [Vector3(-15, 0, -11), Vector3(15.8, 0, -13), Vector3(-20, 0, 1)]:
		_place(vegetation, "DeadTree_1", spec.x, spec.z, _rng.randf_range(0.38, 0.55), true, true)
	var wreck := _place(relics, "shipwreck_hull", -10.8, -4.5, 1.25, false, true)
	wreck.rotation_degrees = Vector3(0, -32, -8)
	_place(relics, "sea_arch", 10.8, 6.3, 1.15, false, true)
	_place(relics, "sea_rock_big", 11.7, 7.0, 1.1, false, true)
	_place(relics, "coral_fan", -7.9, 5.7, 0.50)
	_place(relics, "coral_brain", 8.8, -5.5, 0.65)
	_place(relics, "coral_tube", -4.5, -8.5, 0.65)
	_place(relics, "sea_anemone", 6.1, -5.2, 0.85)
	# Sea marks cut into the abandoned entrance piers.
	for i in range(12):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(24.5, 26.8)
		_place(shoreline, "sea_rock_big", sin(a) * r, cos(a) * r, _rng.randf_range(0.7, 1.7), false, true)

func _bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var local_transform := node.global_transform.affine_inverse() * mesh.global_transform
		var bound := local_transform * mesh.get_aabb()
		result = bound if first else result.merge(bound)
		first = false
	return result

func _movable(parent: Node3D, asset_name: String, x: float, z: float, size: float, kilograms: float, label: String, nature: bool = false, flotation: float = 0.2) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = asset_name
	body.mass = kilograms
	body.collision_layer = 16
	body.collision_mask = 31
	body.continuous_cd = true
	body.linear_damp = 0.20
	body.angular_damp = 0.48
	body.add_to_group("tidal_props", true)
	body.set_meta("display_name", label)
	body.set_meta("flotation", flotation)
	var physics := PhysicsMaterial.new()
	physics.friction = 0.82
	physics.bounce = 0.08
	body.physics_material_override = physics
	parent.add_child(body, true)
	var visual := _asset(asset_name, nature)
	visual.scale = Vector3.ONE * size
	body.add_child(visual)
	var bounds := _bounds(body)
	# Center the collision and mass around the actual model, including offset pivots.
	visual.position -= bounds.get_center()
	body.set_meta("half_height", bounds.size.y * 0.5)
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		var relative := body.global_transform.affine_inverse() * mesh.global_transform
		for vertex: Vector3 in mesh.mesh.get_faces():
			points.append(relative * vertex)
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = hull
	body.add_child(collision)
	body.position = Vector3(x, maxf(terrain_height(x, z), WATER_LEVEL) + bounds.size.y * 0.5 + 0.12, z)
	body.rotation.y = _rng.randf_range(0, TAU)
	return body

func _build_props() -> void:
	var movables := _container("PhysicsProps")
	# Small archaeological clusters leave an open centre for the future octopus.
	for i in range(10):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(6.0, 13.6)
		_movable(movables, "amphora", sin(a) * r, cos(a) * r, _rng.randf_range(0.9, 1.3), 3.2, "오래된 항아리")
	for point: Vector2 in [Vector2(-7, -3), Vector2(-8.2, -2.1), Vector2(6.2, 5), Vector2(7.0, 5.7), Vector2(-4.2, 5.7)]:
		_movable(movables, "barrel", point.x, point.y, 1.12, 5.0, "나무통", false, 1.35)
	for i in range(15):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(5.3, 15.2)
		_movable(movables, "sea_rock_small", sin(a) * r, cos(a) * r, _rng.randf_range(0.65, 1.3), 2.8, "갯돌")
	for i in range(10):
		var a := _rng.randf_range(0, TAU)
		var r := _rng.randf_range(4.7, 12.4)
		var shell := "clam_shell" if i % 2 == 0 else "conch_shell"
		_movable(movables, shell, sin(a) * r, cos(a) * r, _rng.randf_range(0.55, 0.85), 0.65, "조개껍데기")
	_movable(movables, "treasure_chest", -11.0, -2.5, 1.0, 12.0, "잠긴 보물상자", false, 0.6)
	_movable(movables, "ship_anchor", -9.0, -5.0, 0.9, 18.0, "녹슨 닻")
	_movable(movables, "ship_wheel", -10.8, -6.0, 0.9, 3.0, "떠밀려 온 조타륜", false, 1.25)
	for point: Vector2 in [Vector2(4.7, 4.2), Vector2(-6.8, 6.7), Vector2(8.8, -1.0)]:
		_movable(movables, "starfish", point.x, point.y, 0.9, 0.25, "불가사리")
	for point: Vector2 in [Vector2(5.4, 3.8), Vector2(-7.1, 5.1)]:
		_movable(movables, "crab", point.x, point.y, 0.55, 0.8, "게 모형")

func _build_markers() -> void:
	var markers := _container("SpawnPoints")
	for spec: Array in [["OctopusSpawn", Vector3(0, 0.65, 0)], ["HunterSpawn", Vector3(-6, 0.3, 1.5)],
		["ExitSpawn", Vector3(0, 0.3, -19)], ["CameraFocus", Vector3(0, 1, 0)]]:
		var marker := Marker3D.new()
		marker.name = spec[0]
		marker.position = spec[1]
		marker.gizmo_extents = 1.5
		markers.add_child(marker)
		if marker.name == "OctopusSpawn":
			marker.add_to_group("octopus_spawn", true)
