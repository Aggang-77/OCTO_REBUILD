extends RefCounted
# GPU-deformed octopus skin wrapped around authoritative C++ rod nodes.
# This is deliberately *not* collision geometry.
const SHADER: Shader = preload("res://shaders/jelly_octopus.gdshader")
const RINGS_PER_SEGMENT := 2
const RADIAL_SIDES := 12

static func material_for(phase: float, strength: float, mantle: bool = false) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = SHADER
    mat.set_shader_parameter("arm_phase", phase)
    mat.set_shader_parameter("jelly_strength", strength)
    mat.set_shader_parameter("mantle_mode", mantle)
    mat.set_shader_parameter("recoil", 0.0)
    if mantle:
        mat.set_shader_parameter("gel_color", Color(0.66, 0.31, 0.38, 0.98))
    else:
        mat.set_shader_parameter("gel_color", Color(0.73, 0.38, 0.42, 0.98))
    return mat

static func location(nodes: Array, u: float) -> Vector3:
    var f := clampf(u, 0.0, 1.0) * float(nodes.size() - 1)
    var i := mini(int(f), nodes.size() - 2)
    var t := f - float(i)
    var p0 := Vector3(nodes[maxi(i - 1, 0)][0], nodes[maxi(i - 1, 0)][1], nodes[maxi(i - 1, 0)][2])
    var p1 := Vector3(nodes[i][0], nodes[i][1], nodes[i][2])
    var p2 := Vector3(nodes[i + 1][0], nodes[i + 1][1], nodes[i + 1][2])
    var p3 := Vector3(nodes[mini(i + 2, nodes.size() - 1)][0], nodes[mini(i + 2, nodes.size() - 1)][1], nodes[mini(i + 2, nodes.size() - 1)][2])
    return 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)

static func section_radius(radii: Array, u: float) -> Vector2:
    var f := clampf(u * float(radii.size()) - 0.5, 0.0, float(radii.size() - 1))
    var i := mini(int(f), radii.size() - 2)
    var t := f - float(i)
    return Vector2(
        lerpf(float(radii[i][0]), float(radii[i + 1][0]), t),
        lerpf(float(radii[i][1]), float(radii[i + 1][1]), t)
    )

static func build_arm_mesh(nodes: Array, radii: Array) -> ArrayMesh:
    var mesh := ArrayMesh.new()
    if nodes.size() < 3 or radii.size() != nodes.size() - 1:
        return mesh

    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    var uv2s := PackedVector2Array()
    var indices := PackedInt32Array()
    var ring_count := (nodes.size() - 1) * RINGS_PER_SEGMENT + 1
    var previous_axis := Vector3.ZERO

    for ring in range(ring_count):
        var u := float(ring) / float(ring_count - 1)
        var center := location(nodes, u)
        var ahead := location(nodes, minf(u + 0.006, 1.0))
        var behind := location(nodes, maxf(u - 0.006, 0.0))
        var tangent := (ahead - behind).normalized()
        if tangent.length_squared() < 0.000001:
            tangent = Vector3.FORWARD

        # Parallel transport avoids 180 degree flips in the tube frame.
        var side := previous_axis - tangent * previous_axis.dot(tangent)
        if side.length_squared() < 0.000001:
            side = tangent.cross(Vector3.UP)
            if side.length_squared() < 0.000001:
                side = tangent.cross(Vector3.RIGHT)
        side = side.normalized()
        var other := tangent.cross(side).normalized()
        previous_axis = side

        var r := section_radius(radii, u) * 1.15
        for slice in range(RADIAL_SIDES + 1):
            var theta := float(slice) / float(RADIAL_SIDES) * TAU
            var co := cos(theta)
            var si := sin(theta)
            var outward := (side * (co / maxf(r.x, 0.0001)) + other * (si / maxf(r.y, 0.0001))).normalized()
            var offset := side * co * r.x + other * si * r.y
            vertices.append(center + offset)
            normals.append(outward)
            uvs.append(Vector2(float(slice) / float(RADIAL_SIDES), u))
            uv2s.append(Vector2(minf(r.x, r.y), 0.0))

    var stride := RADIAL_SIDES + 1
    for ring in range(ring_count - 1):
        for slice in range(RADIAL_SIDES):
            var a := ring * stride + slice
            var b := (ring + 1) * stride + slice
            var c := a + 1
            var d := b + 1
            indices.append_array(PackedInt32Array([a, c, b, c, d, b]))

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_TEX_UV2] = uv2s
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh
