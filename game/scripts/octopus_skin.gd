extends RefCounted
## Original GameReady skin surface deformation: GPU deformation on imported
## mesh vertices, with native per-section tissue compression via bone weights.
## Does not allocate a mesh or read back GPU data during simulation.
const SKIN_SHADER = preload("res://shaders/octopus_skin.gdshader")
const MAX_BONES = 256

func install(scene: Node3D, skel: Skeleton3D, ids: Array) -> Dictionary:
    var result := {"materials": [], "bone_ids": ids, "bone_count": skel.get_bone_count(),
        "covered_surfaces": 0, "rejected_surfaces": 0, "reason": ""}
    if skel.get_bone_count() > MAX_BONES:
        result.reason = "Imported skeleton exceeds the 256 shader bone capacity"
        return result
    for item in scene.find_children("*", "MeshInstance3D", true, false):
        var instance := item as MeshInstance3D
        if instance.mesh == null:
            continue
        for surface in range(instance.mesh.get_surface_count()):
            var original := instance.get_active_material(surface)
            # Preserve unsupported custom shaders / cutout-translucent
            # materials rather than overwriting eye or special effects.
            if not original is StandardMaterial3D:
                result.rejected_surfaces += 1
                continue
            var standard := original as StandardMaterial3D
            if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
                result.rejected_surfaces += 1
                continue
            var material := ShaderMaterial.new()
            material.shader = SKIN_SHADER
            material.set_shader_parameter("base_albedo", standard.albedo_color)
            material.set_shader_parameter("base_roughness", standard.roughness)
            material.set_shader_parameter("base_metallic", standard.metallic)
            material.set_shader_parameter("has_albedo_tex", standard.albedo_texture != null)
            if standard.albedo_texture != null:
                material.set_shader_parameter("albedo_tex", standard.albedo_texture)
            material.set_shader_parameter("has_normal_tex", standard.normal_texture != null)
            if standard.normal_texture != null:
                material.set_shader_parameter("normal_tex", standard.normal_texture)
                material.set_shader_parameter("normal_strength", standard.normal_scale)
            material.set_shader_parameter("bone_compression", _zeros())
            material.set_shader_parameter("bone_activity", _zeros())
            instance.set_surface_override_material(surface, material)
            result.materials.append(material)
            result.covered_surfaces += 1
    return result

func _zeros() -> PackedFloat32Array:
    var values := PackedFloat32Array()
    values.resize(MAX_BONES)
    values.fill(0.0)
    return values

func sample_fields(arms: Array, bone_ids: Array, bone_count: int) -> Dictionary:
    var compression := _zeros()
    var activity := _zeros()
    var coverage := 0
    for physical_arm in range(mini(8, arms.size())):
        var art: int = (7 - physical_arm) % 8
        if art >= bone_ids.size():
            continue
        var section_ids: Array = bone_ids[art]
        var state: Dictionary = arms[physical_arm]
        var tissue: Array = state.get("tissue", [])
        var creep: Array = state.get("creep", [])
        if tissue.is_empty():
            continue
        for section in range(section_ids.size()):
            var bone: int = section_ids[section]
            if bone < 0 or bone >= mini(bone_count, MAX_BONES):
                continue
            var idx: int = mini(int(float(section) * float(tissue.size()) /
                float(maxi(section_ids.size(), 1))), tissue.size() - 1)
            var transverse = tissue[idx]
            if not transverse is Array or transverse.size() < 2:
                continue
            var q := float(transverse[1])
            var pressure := clampf(1.0 - q, 0.0, 0.85)
            compression[bone] = pressure
            activity[bone] = clampf(pressure * 2.2 +
                (absf(float(creep[idx])) if idx < creep.size() else 0.0), 0.0, 1.0)
            coverage += 1
    return {"bone_compression": compression,
            "bone_activity": activity, "mapped": coverage}

func update_skin(config: Dictionary, arms: Array) -> void:
    if config.get("materials", []).is_empty():
        return
    var data := sample_fields(arms, config.bone_ids, int(config.bone_count))
    for material in config.materials:
        var shader_material := material as ShaderMaterial
        shader_material.set_shader_parameter("bone_compression", data.bone_compression)
        shader_material.set_shader_parameter("bone_activity", data.bone_activity)
