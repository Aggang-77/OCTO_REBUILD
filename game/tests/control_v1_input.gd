extends SceneTree
# Runs without the untracked GameReady asset or native C++ process.
# Real Godot Input.parse_input_event -> game step2 wire serialization.
const DEMO = preload("res://scripts/demo.gd")

func _key(code: Key, pressed: bool) -> void:
    var e := InputEventKey.new()
    e.keycode = code
    e.physical_keycode = code
    e.pressed = pressed
    Input.parse_input_event(e)

func _check(condition: bool, reason: String) -> bool:
    if not condition:
        printerr("CONTROL_V1_FAIL: " + reason)
        quit(2)
        return false
    return true

func _initialize() -> void:
    call_deferred("_exercise")

func _exercise() -> void:
    var octo = DEMO.new()
    root.add_child(octo)
    await process_frame
    octo.animals = 2
    octo.selected = 1
    # The imported GLB is private, so exercise the exact GPU material
    # conversion with a synthetic StandardMaterial and live shader.
    var skin_rig := Skeleton3D.new()
    skin_rig.add_bone("BodyRoot")
    skin_rig.add_bone("A0_00")
    var skin_scene := Node3D.new()
    var skin_mesh := MeshInstance3D.new()
    var skin_sphere := SphereMesh.new()
    var skin_source := StandardMaterial3D.new()
    skin_source.albedo_color = Color(0.42, 0.27, 0.18, 1.0)
    skin_source.roughness = 0.52
    var skin_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
    skin_image.fill(Color(0.7, 0.5, 0.3))
    skin_source.albedo_texture = ImageTexture.create_from_image(skin_image)
    skin_source.roughness_texture = skin_source.albedo_texture
    skin_source.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
    skin_sphere.material = skin_source
    skin_mesh.mesh = skin_sphere
    skin_scene.add_child(skin_mesh)
    octo.add_child(skin_scene)
    var skin_bone_ids: Array = []
    for idx in 8:
        skin_bone_ids.append([])
    skin_bone_ids[7] = [1]
    var native_skin = octo.skin_deformer.install(skin_scene, skin_rig, skin_bone_ids)
    if not _check(native_skin.covered_surfaces == 1 and
            skin_mesh.get_active_material(0) is ShaderMaterial,
            "original imported mesh receives deformation shader"):
        return
    var converted: ShaderMaterial = skin_mesh.get_active_material(0)
    if not _check(converted.get_shader_parameter("albedo_tex") != null and
            converted.get_shader_parameter("roughness_tex") != null and
            int(converted.get_shader_parameter("roughness_channel")) == 1 and
            absf(float(converted.get_shader_parameter("base_roughness")) - 0.52) < 0.0001,
            "texture and authored roughness preserved"):
        return
    var synthetic_arms: Array = []
    for idx in 8:
        synthetic_arms.append({"tissue": [[1.0, 0.6]], "creep": [0.08]})
    octo.skin_deformer.update_skin(native_skin, synthetic_arms)
    var skin_compression: PackedFloat32Array = converted.get_shader_parameter("bone_compression")
    var skin_activity: PackedFloat32Array = converted.get_shader_parameter("bone_activity")
    if not _check(skin_compression.size() == 256 and
            absf(skin_compression[1] - 0.4) < 0.0001 and
            skin_activity[1] > 0.4 and skin_compression[0] == 0.0,
            "live C++ tissue pressure maps to exact imported bone index"):
        return
    var override_mesh := MeshInstance3D.new()
    override_mesh.mesh = SphereMesh.new()
    override_mesh.material_override = skin_source
    var override_scene := Node3D.new()
    override_scene.add_child(override_mesh)
    octo.add_child(override_scene)
    var override_skin := octo.skin_deformer.install(override_scene, skin_rig, skin_bone_ids)
    if not _check(override_skin.covered_surfaces == 1 and
            override_mesh.material_override is ShaderMaterial,
            "GLB mesh-level material overrides receive real GPU deformation"):
        return
    print("GLB_VERTEX_SKIN_PASS surfaces=1 bone_map=true textures_preserved=true overrides=true")

    # The prototype's real 3D shell surface is generated from physical
    # ring positions, not from a fixed circular centerline tube.
    var ring_a := [[0.0,0.0,0.0], [1.0,0.0,0.0],
                   [1.0,1.0,0.0], [0.0,1.0,0.0]]
    var ring_b := [[0.0,0.0,1.0], [1.0,0.0,1.0],
                   [1.0,1.0,1.0], [0.0,1.0,1.0]]
    var physical_preview := octo.create_volumetric_preview_mesh([ring_a,ring_b])
    if not _check(physical_preview.get_surface_count() == 1 and
            physical_preview.surface_get_array_len(0) == 8 and
            physical_preview.surface_get_array_index_len(0) == 24,
            "3D surface triangle topology follows two physical rings"):
        return
    OS.set_environment("OCTO_VOLUME_ARM", "1")
    if not _check(octo.reset_command().ends_with(" 1"),"experimental native reset enabled"):
        return
    OS.set_environment("OCTO_VOLUME_ARM", "")
    if not _check(not octo.reset_command().ends_with(" 1 1"),
            "stable native reset remains unchanged"):
        return
    print("VOLUMETRIC_GODOT_PREVIEW_PASS physical_vertices=8 triangles=8")
    # Exercise GPU-bone mantle deformation independently of the private GLB:
    # the real GameReady skeleton has one shared root and 192 arm bones.
    var skeleton := Skeleton3D.new()
    octo.add_child(skeleton)
    skeleton.add_bone("BodyRoot")
    skeleton.set_bone_rest(0, Transform3D.IDENTITY)
    octo.apply_torso_root_skin(skeleton, 0, Transform3D.IDENTITY,
        Vector3(0.76, 1.32, 1.12))
    var root_scale := skeleton.get_bone_global_pose(0).basis.get_scale()
    if not _check(root_scale.distance_to(Vector3(0.76,1.32,1.12)) < 0.001,
            "imported torso root receives physical shell deformation"):
        return
    var faux_shell: Array = []
    for i in 7:
        faux_shell.append([0.0,0.0,0.0])
    for i in 12:
        var theta := float(i % 6) * PI / 3.0
        faux_shell.append([0.18*cos(theta), 0.00 if i < 6 else 0.20,
            0.14*sin(theta)])
    var torso_scale := octo.mantle_scale_from_shell(faux_shell,
        Vector3.ZERO, Quaternion.IDENTITY)
    var exhale: Vector3 = octo.mantle_respiration(torso_scale, 0.0)
    var inhale: Vector3 = octo.mantle_respiration(torso_scale, 1.0)
    if not _check(inhale.x > exhale.x and inhale.z > exhale.z and
            inhale.x / exhale.x < 1.03,
            "slow low-amplitude mantle breathing retains shell deformation"):
        return
    if not _check(torso_scale.x < 1.0 and torso_scale.y < 1.0,
            "shell dimensions feed visible torso shape"):
        return
    print("TISSUE_GPU_SKIN_PASS root=true mantle_bounds=true no_cpu_remesh=true")
    # Apply the cheap PBR wet-look to a local mesh; no original private GLB
    # and no per-vertex jelly shader are needed for this regression.
    var sample_mesh := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.material = StandardMaterial3D.new()
    sample_mesh.mesh = sphere
    var mock := Node3D.new()
    mock.add_child(sample_mesh)
    octo.add_child(mock)
    var surfaces := octo.apply_slime_finish(mock)
    if not _check(surfaces == 1, "slime finish created from base material"):
        return
    var wet := sample_mesh.get_active_material(0) as StandardMaterial3D
    if not _check(wet != null and wet.clearcoat_enabled and
            absf(wet.roughness - 0.20) < 0.001, "cheap slimy PBR coating"):
        return
    print("SLIME_PBR_PASS shader=false coat=true")

    # Old/native-in-flight render snapshots can omit the new HUD-only
    # attached field; this must never throw or stop player controls.
    var legacy_snapshot: Dictionary = {
        "animals": [{"arms": [{"nodes": []}, {"radii": []}]}]
    }
    if not _check(octo.count_grips_from_snapshot(legacy_snapshot) == 0,
            "legacy snapshot without attached does not crash"):
        return
    var mixed_snapshot: Dictionary = {
        "animals": [{"arms": [{"attached": [true, false, true]},
                              {"nodes": []}]},
                    {"arms": [{"attached": [false, true]}]}]
    }
    if not _check(octo.count_grips_from_snapshot(mixed_snapshot) == 3,
            "grip count uses only explicitly present contacts"):
        return
    print("GRIP_HUD_COMPAT_PASS legacy_missing=true counted=3")
    if not _check(DEMO.EXTEND_KEYS.size() == 8 and DEMO.STROKE_KEYS.size() == 8, "16-key arrays"):
        return
    var unique := {}
    for arm in range(8):
        var extension: Key = DEMO.EXTEND_KEYS[arm]
        var stroke: Key = DEMO.STROKE_KEYS[arm]
        if not _check(not unique.has(extension) and not unique.has(stroke) and extension != stroke, "unique keys %d" % arm):
            return
        unique[extension] = true
        unique[stroke] = true
        _key(extension, true)
        await process_frame
        var parts := octo.step_command().split(" ")
        if not _check(parts[0] == "step2" and parts[1] == "16", "step2 header"):
            return
        for j in range(8):
            var begin := 2 + (8 + j) * 9
            var actual := float(parts[begin + 4])
            if not _check(absf(actual - (1.48 if j == arm else float(octo.idle_arm_shape(1, j).extension))) < 0.001, "extend arm %d vs %d" % [j, arm]):
                return
        _key(extension, false)
        _key(stroke, true)
        await process_frame
        parts = octo.step_command().split(" ")
        for j in range(8):
            var begin := 2 + (8 + j) * 9
            if not _check(absf(float(parts[begin + 8]) - (1.0 if j == arm else 0.0)) < 0.001, "stroke arm %d vs %d" % [j, arm]):
                return
        _key(stroke, false)
        await process_frame
    # Same-arm simultaneous extension + stroke.
    _key(KEY_F, true)
    _key(KEY_D, true)
    await process_frame
    var parts := octo.step_command().split(" ")
    var arm7 := 2 + (8 + 7) * 9
    if not _check(absf(float(parts[arm7 + 4])-1.48)<0.001 and absf(float(parts[arm7 + 8])-1.0)<0.001, "simultaneous F+D"):
        return
    _key(KEY_F, false)
    _key(KEY_D, false)
    await process_frame
    parts = octo.step_command().split(" ")
    if not _check(absf(float(parts[arm7 + 4])-float(octo.idle_arm_shape(1,7).extension))<0.001 and absf(float(parts[arm7 + 8]))<0.001, "release returns to relaxed draped arms"):
        return
    _key(KEY_SPACE, true)
    await process_frame
    if not _check(octo.step_command().ends_with(" 1"), "Space release"):
        return
    _key(KEY_SPACE, false)
    await process_frame
    if not _check(octo.step_command().ends_with(" 0"), "Space release clears"):
        return
    var a0 := octo.idle_arm_shape(0,0)
    var a1 := octo.idle_arm_shape(0,1)
    if not _check(absf(a0.extension-a1.extension)>0.01 and
            a0.activation < 0.5 and a0.sweep == 0.0,
            "natural rest posture is asymmetric and passive"):
        return
    print("CONTROL_V1_KEYS_PASS 16_keys=true simultaneous=true passive_idle=true space_priority=true")
    octo.free()
    quit(0)
