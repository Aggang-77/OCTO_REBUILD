extends RefCounted
# GPU-deformed octopus skin wrapped around authoritative C++ rod nodes.
# This is deliberately *not* collision geometry.
const SHADER: Shader = preload("res://shaders/jelly_octopus.gdshader")
const RINGS_PER_SEGMENT := 2
const RADIAL_SIDES := 12
const WEB_ROWS := 16
const WEB_COLUMNS := 12
const DEFAULT_THICKNESS := 1.50

static func material_for(phase: float, strength: float, mantle: bool = false, web: bool = false) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = SHADER
    mat.set_shader_parameter("arm_phase", phase)
    mat.set_shader_parameter("jelly_strength", strength)
    mat.set_shader_parameter("mantle_mode", mantle)
    mat.set_shader_parameter("web_mode", web)
    mat.set_shader_parameter("recoil", 0.0)
    if mantle:
        mat.set_shader_parameter("gel_color", Color(0.66, 0.31, 0.38, 0.98))
    elif web:
        mat.set_shader_parameter("gel_color", Color(0.76, 0.39, 0.44, 0.98))
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

static func arm_width(u: float, thickness: float) -> float:
    # Proximal flesh adds volume and the distal tip remains rounded.
    return thickness * (1.0 + 0.16 * pow(1.0 - clampf(u, 0.0, 1.0), 2.0))

static func build_arm_mesh(nodes: Array, radii: Array, thickness: float = DEFAULT_THICKNESS) -> ArrayMesh:
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

        var r := section_radius(radii, u) * arm_width(u, thickness)
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

# Eight membranes join adjacent physical arm indices, including 7 -> 0.
# All membrane boundaries are driven by C++ arm-node/section snapshots.
static func web_edge(nodes: Array, radii: Array, u: float, toward: Vector3, thickness: float) -> Vector3:
    var center := location(nodes, u)
    var a := location(nodes, maxf(0.0, u - 0.006))
    var b := location(nodes, minf(1.0, u + 0.006))
    var tangent := (b - a).normalized()
    if tangent.length_squared() < 0.000001:
        tangent = Vector3.FORWARD
    var direction := toward - tangent * toward.dot(tangent)
    if direction.length_squared() < 0.00000001:
        direction = tangent.cross(Vector3.UP)
        if direction.length_squared() < 0.00000001:
            direction = tangent.cross(Vector3.RIGHT)
    var section := section_radius(radii, u)
    var r := 0.5 * (section.x + section.y) * arm_width(u, thickness)
    return center + direction.normalized() * r * 0.99

static func build_web_mesh(
        nodes_a: Array, radii_a: Array, nodes_b: Array, radii_b: Array,
        thickness: float = DEFAULT_THICKNESS) -> ArrayMesh:
    var mesh := ArrayMesh.new()
    if nodes_a.size() < 3 or nodes_b.size() < 3:
        return mesh
    if radii_a.size() != nodes_a.size() - 1 or radii_b.size() != nodes_b.size() - 1:
        return mesh

    var points := PackedVector3Array()
    var texcoords := PackedVector2Array()
    var web_scales := PackedVector2Array()
    var stride := WEB_COLUMNS + 1
    var rows := WEB_ROWS + 1
    for row in range(rows):
        var radial := float(row) / float(WEB_ROWS)
        for col in range(stride):
            var across := float(col) / float(WEB_COLUMNS)
            var scallop := pow(maxf(sin(PI * across), 0.0), 1.25)
            # Concave web: 48% of arm length at side attachments, 24%
            # between the arms. This follows the real interbrachial contour.
            var u := radial * lerpf(0.48, 0.24, scallop)
            var pa := location(nodes_a, u)
            var pb := location(nodes_b, u)
            var bridge := pb - pa
            var a_edge := web_edge(nodes_a, radii_a, u, bridge, thickness)
            var b_edge := web_edge(nodes_b, radii_b, u, -bridge, thickness)
            var gap := (b_edge - a_edge).length()
            var sag := sin(PI * across) * radial * (0.028 + 0.17 * gap)
            points.append(a_edge.lerp(b_edge, across) - Vector3.UP * sag)
            texcoords.append(Vector2(across, radial))
            web_scales.append(Vector2(0.028 + 0.06 * gap, 0.0))

    var top_normals := PackedVector3Array()
    for row in range(rows):
        for col in range(stride):
            var before_r := points[maxi(row - 1, 0) * stride + col]
            var after_r := points[mini(row + 1, WEB_ROWS) * stride + col]
            var before_c := points[row * stride + maxi(col - 1, 0)]
            var after_c := points[row * stride + mini(col + 1, WEB_COLUMNS)]
            var normal := (after_c - before_c).cross(after_r - before_r).normalized()
            if normal.length_squared() < 0.000001:
                normal = Vector3.UP
            if normal.dot(Vector3.UP) < 0.0:
                normal = -normal
            top_normals.append(normal)

    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    var uv2s := PackedVector2Array()
    var indices := PackedInt32Array()
    var n := points.size()
    # Two sides with actual 0.6–1.6cm thickness; sealed perimeter.
    for layer in range(2):
        for row in range(rows):
            for col in range(stride):
                var id := row * stride + col
                var half_depth := 0.003 + 0.005 * (1.0 - float(row) / float(WEB_ROWS))
                var outward := top_normals[id] if layer == 0 else -top_normals[id]
                vertices.append(points[id] + outward * half_depth)
                normals.append(outward)
                uvs.append(texcoords[id])
                uv2s.append(web_scales[id])
    for row in range(WEB_ROWS):
        for col in range(WEB_COLUMNS):
            var a := row * stride + col
            var b := (row + 1) * stride + col
            var c := a + 1
            var d := b + 1
            indices.append_array(PackedInt32Array([a, c, b, c, d, b]))
            indices.append_array(PackedInt32Array([a + n, b + n, c + n, c + n, b + n, d + n]))
    var boundary := PackedInt32Array()
    for col in range(WEB_COLUMNS):
        boundary.append(col)
    for row in range(WEB_ROWS):
        boundary.append(row * stride + WEB_COLUMNS)
    for col in range(WEB_COLUMNS, 0, -1):
        boundary.append(WEB_ROWS * stride + col)
    for row in range(WEB_ROWS, 0, -1):
        boundary.append(row * stride)
    for i in range(boundary.size()):
        var a := boundary[i]
        var b := boundary[(i + 1) % boundary.size()]
        indices.append_array(PackedInt32Array([a, b, a + n, b, b + n, a + n]))

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_TEX_UV2] = uv2s
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh
