extends RefCounted
## Palette from the user's three portrait references. Recolor materials at load
## time so source models, animation, skinning and physics assets stay intact.

const HAIR_COLORS := [Color("45262b"), Color("f47f00"), Color("201d1d"), Color("ef7c2b")]
const IRIS_COLORS := [Color("ff2157"), Color("245fe7"), Color("9c12b7")]
const IRIS_DARK := [Color("48152d"), Color("201563"), Color("42104e")]
const IRIS_LIGHT := [Color("ff719a"), Color("71d8ef"), Color("b62ad0")]
const BLOUSE_COLOR := Color("ffd1df")
const RIBBON_COLOR := Color("ff2450")
const IRIS_SHADER = preload("res://assets/characters/iris_recolor.gdshader")
const LILY_EYE_SHADER = preload("res://assets/characters/lily_eyes.gdshader")
const OUTFIT_SHADER = preload("res://assets/characters/lily_outfit_recolor.gdshader")

static func prepare_mesh(character: int, source: Mesh) -> Mesh:
	if character != 0 or not source is ArrayMesh:
		return source
	var has_eyes := false
	for surface in range(source.get_surface_count()):
		var material := source.surface_get_material(surface)
		if material != null and material.resource_name == "aiToon9SG":
			has_eyes = true
	if not has_eyes:
		return source
	var result := ArrayMesh.new()
	result.resource_name = "LilyContinuousEyeCoordinates"
	for index in range(source.get_blend_shape_count()):
		result.add_blend_shape(source.get_blend_shape_name(index))
	result.blend_shape_mode = source.blend_shape_mode
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var material := source.surface_get_material(surface)
		if material != null and material.resource_name == "aiToon9SG":
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bounds := [AABB(), AABB()]
			var initialized := [false, false]
			for point in vertices:
				var eye := 0 if point.x < 0.0 else 1
				if initialized[eye]: bounds[eye] = bounds[eye].expand(point)
				else:
					bounds[eye] = AABB(point, Vector3.ZERO)
					initialized[eye] = true
			var coordinates := PackedVector2Array()
			for point in vertices:
				var eye := 0 if point.x < 0.0 else 1
				var bound: AABB = bounds[eye]
				var center := bound.get_center()
				center.y += bound.size.y * 0.05
				coordinates.append(Vector2((point.x - center.x) / (bound.size.x * 0.34),
					(center.y - point.y) / (bound.size.y * 0.62)))
			arrays[Mesh.ARRAY_TEX_UV2] = coordinates
		# Preserve every source position, normal, bone, weight, index and morph;
		# only the second UV channel on the eye surface is added.
		var flags: int = source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays,
			source.surface_get_blend_shape_arrays(surface), {}, flags)
		result.surface_set_material(surface, material)
	return result

static func material_for(character: int, original: StandardMaterial3D) -> ShaderMaterial:
	var material_name := original.resource_name
	var region := Vector4(0, 0, 1, 1)
	var iris := false
	if character == 0 and material_name == "aiToon9SG":
		iris = true
	elif character == 1 and material_name == "material_atlas_75340_1":
		# Rin's two iris islands share the clothing atlas; hair/skirt are tagged apart.
		region = Vector4(0.14, 0.525, 0.24, 0.615)
		iris = true
	elif character == 2 and "EyeIris" in material_name:
		iris = true
	if iris:
		var material := ShaderMaterial.new()
		material.resource_name = "ReferenceIris_%d" % (character + 1)
		material.shader = LILY_EYE_SHADER if character == 0 else IRIS_SHADER
		material.set_shader_parameter("source_texture", original.albedo_texture)
		if character != 0:
			material.set_shader_parameter("iris_rect", region)
		material.set_shader_parameter("iris_dark", IRIS_DARK[character])
		material.set_shader_parameter("iris_color", IRIS_COLORS[character])
		material.set_shader_parameter("iris_light", IRIS_LIGHT[character])
		return material
	if character == 0 and material_name == "aiToon15SG":
		var material := ShaderMaterial.new()
		material.resource_name = "ReferenceOutfit_1"
		material.shader = OUTFIT_SHADER
		material.set_shader_parameter("source_texture", original.albedo_texture)
		material.set_shader_parameter("blouse_color", BLOUSE_COLOR)
		material.set_shader_parameter("ribbon_color", RIBBON_COLOR)
		return material
	return null
