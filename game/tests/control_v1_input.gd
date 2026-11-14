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
    # Apply the cheap PBR wet-look to a local mesh; no original private GLB
    # and no per-vertex jelly shader are needed for this regression.
    var sample_mesh := MeshInstance3D.new()
    sample_mesh.mesh = SphereMesh.new()
    sample_mesh.material_override = StandardMaterial3D.new()
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
            if not _check(absf(actual - (1.48 if j == arm else 0.58)) < 0.001, "extend arm %d vs %d" % [j, arm]):
                return
        _key(extension, false)
        _key(stroke, true)
        await process_frame
        parts = octo.step_command().split(" ")
        for j in range(8):
            var begin := 2 + (8 + j) * 9
            if not _check(absf(float(parts[begin + 8]) - (1.0 if j == arm else -1.0)) < 0.001, "stroke arm %d vs %d" % [j, arm]):
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
    if not _check(absf(float(parts[arm7 + 4])-0.58)<0.001 and absf(float(parts[arm7 + 8])+1.0)<0.001, "release returns"):
        return
    _key(KEY_SPACE, true)
    await process_frame
    if not _check(octo.step_command().ends_with(" 1"), "Space release"):
        return
    _key(KEY_SPACE, false)
    await process_frame
    if not _check(octo.step_command().ends_with(" 0"), "Space release clears"):
        return
    print("CONTROL_V1_KEYS_PASS 16_keys=true simultaneous=true release_return=true space_priority=true")
    octo.free()
    quit(0)
