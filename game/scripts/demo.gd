extends Node3D
const MODEL = "res://assets/Octopus_GameReady_v5.glb"
const OCTOPUS_SKIN = preload("res://scripts/octopus_skin.gd")
# Solver arms 0..7 go around the body: right-front, right-side-front,
# right-side-rear, right-rear, left-rear, left-side-rear,
# left-side-front, left-front. Heading is torso-local +Z.
const ARM_CONTROLS = preload("res://scripts/arm_controls.gd")
const ARM_KEYS = ARM_CONTROLS.KEYS
var arm_controllers: Array = []
const MODEL_SCALE = 1.35 / 2.3
const MODEL_YAW = -PI / 8.0
var child := {}
var pipe: FileAccess
var buffer := PackedByteArray()
var reader := Thread.new()
var inbox_lock := Mutex.new()
var inbox: Array[String] = []
var inbox_times: Array[float] = []
var stop_reader := false
var reader_phase := "starting"
var reader_available := -1
var auto_step := false
var latest_command := ""
var reset_requested := false
var next_due_usec := 0
var last_response_id := 0
var pending := false
var request_id := 0
var sent_at := 0
var last_progress_usec := 0
var current := {}
var views: Array = []
var skin_deformer = OCTOPUS_SKIN.new()
var props: Array = []
var selected := 0
var animals := 2
var smoke := false
var benchmark_ticks := 60
var test_actuation := false
var test_all_active := false
var test_reset := false
var test_kill_native := false
var test_input := false
var test_crawl := false
var crawl_started := false
var crawl_released := false
var crawl_origin := Vector3.ZERO
var crawl_phases := {}
var crawl_grips := 0
var input_phase := 0
var input_arm_seen := false
var input_drag_seen := false
var input_arm_delta := 0.0
var input_center_delta := 0.0
var input_arm_baseline := 0.0
var input_center_baseline := Vector3.ZERO
var killed_native := false
var reset_issued := false
var reset_observed := false
var dense_scene := false
var screenshot := ""
var label: Label
var camera: Camera3D
var yaw := 0.35
var pitch := 0.85
var distance := 8.0
var target_kind := 0 # 0 none, 1 another octopus, 2 physics prop
var target_index := -1
var target_hit := Vector3.ZERO
var target_previous_center := Vector3.ZERO
var target_marker: Node3D
var dragging := false
var drag_kind := 0
var drag_index := 0
var drag_target := Vector3.ZERO
var drag_plane: Plane
var frame_sum := 0.0
var frame_count := 0
var rpc_ms := 0.0
var parse_ms := 0.0
var skin_ms := 0.0
var command_ms := 0.0
var quitting := false
var first_tick_usec := 0
var frame_wall_ms: Array[float] = []

func _ready() -> void:
    # Synthetic key-map test exercises Input with a real in-tree Viewport,
    # but has no private GameReady GLB or running native server.
    if "--keymap-test" in OS.get_cmdline_user_args():
        return
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--animals="): animals = int(arg.get_slice("=", 1))
        if arg == "--benchmark": smoke = true
        if arg.begins_with("--benchmark-ticks="): benchmark_ticks = maxi(60,int(arg.get_slice("=",1))); smoke = true
        if arg == "--test-actuation": test_actuation = true
        if arg == "--test-all-active": test_all_active = true
        if arg == "--test-reset": test_reset = true
        if arg == "--test-kill-native": test_kill_native = true; smoke = true
        if arg == "--test-input": test_input = true; smoke = true
        if arg == "--test-crawl": test_crawl = true; smoke = true
        if arg == "--dense": dense_scene = true
        if arg.begins_with("--screenshot="): screenshot = arg.substr(13); smoke = true
    if animals not in [1, 2, 5, 10]: fail("Choose --animals=1, 2, 5 or 10"); return
    make_stage()
    var packed := load(MODEL) as PackedScene
    if packed == null: fail("GameReady model missing: " + MODEL); return
    for i in animals:
        var scene := packed.instantiate() as Node3D
        add_child(scene)
        # Import the untouched GameReady GLB before installing physical
        # mesh-space skin. The legacy PBR mode is opt-in as a fallback.
        scene.scale = Vector3.ONE * MODEL_SCALE
        scene.rotation.y = MODEL_YAW
        var skels := scene.find_children("*", "Skeleton3D", true, false)
        if skels.is_empty(): fail("Model skeleton missing"); return
        var skel: Skeleton3D = skels[0]
        var bone_ids := []
        var bone_rests := []
        for arm in 8:
            var ids := []
            var rests := []
            for j in 24:
                var id := skel.find_bone("A%d_%02d" % [arm, j])
                if id < 0: fail("Model arm bone missing"); return
                ids.append(id)
                rests.append(skel.get_bone_global_rest(id))
            bone_ids.append(ids)
            bone_rests.append(rests)
        var skin_config := {}
        if OS.get_environment("OCTO_SKIN_MODE") != "legacy":
            skin_config = skin_deformer.install(scene, skel, bone_ids)
            print("NATIVE_MESH_SKIN animal=%d covered=%d skipped=%d reason=%s" % [
                i, skin_config.covered_surfaces,
                skin_config.rejected_surfaces, skin_config.reason])
        else:
            var coated_surfaces := apply_slime_finish(scene)
            print("SLIME_FINISH_LEGACY animal=%d surfaces=%d" % [i,coated_surfaces])
        # Optional imported independent mantle mesh: preserve its original
        # material and vertex data, deform only its object transform from
        # the low-resolution physical shell. Never deform a combined arm mesh.
        var mantles: Array = []
        for mesh_node in scene.find_children("*", "MeshInstance3D", true, false):
            var mesh_part := mesh_node as MeshInstance3D
            var lower := String(mesh_part.name).to_lower()
            if lower.contains("mantle") or lower.contains("head") or lower.contains("hood"):
                mantles.append({"node": mesh_part, "rest": mesh_part.transform})
        # GameReady has 193 bones (192 arm segments + one shared torso
        # root). Its body can therefore be deformed even when every part
        # of the GLB is one combined skin surface: root-weighted vertices
        # follow this bone, while arm bones are re-targeted below.
        var torso_root: int = skel.get_bone_parent(bone_ids[0][0])
        var torso_rest := skel.get_bone_global_rest(torso_root) if torso_root >= 0 else Transform3D.IDENTITY
        var volume_preview: MeshInstance3D = null
        var web := MeshInstance3D.new()
        web.mesh = ImmediateMesh.new()
        var web_material := StandardMaterial3D.new()
        web_material.albedo_color = Color(0.43, 0.21, 0.16)
        web_material.roughness = 0.32
        web_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        web.material_override = web_material
        web.name = "InterarmWeb"
        add_child(web)
        var key_labels: Array = []
        for k in 8:
            var key_label := Label3D.new()
            key_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            key_label.font_size = 28
            key_label.pixel_size = 0.006
            add_child(key_label)
            key_labels.append(key_label)
        if OS.get_environment("OCTO_VOLUME_ARM") == "1":
            volume_preview = MeshInstance3D.new()
            volume_preview.name = "PhysicalArmShellPreview"
            var preview_material := StandardMaterial3D.new()
            preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
            preview_material.albedo_color = Color(0.15, 0.9, 0.7, 0.35)
            volume_preview.material_override = preview_material
            add_child(volume_preview)
        views.append({"skin_config": skin_config, "volume_preview": volume_preview,
            "scene": scene, "skel": skel, "bone_ids": bone_ids,
            "bone_rests": bone_rests, "mantles": mantles,
            "torso_root": torso_root, "torso_rest": torso_rest,
            "mantle_rest_shell": [], "web": web, "key_labels": key_labels})
        print("TISSUE_MANTLE_SKIN animal=%d independent_meshes=%d torso_root=%d" % [i,mantles.size(),torso_root])
    print("MODEL_LOADED animals=%d skeleton_bones=%d arm_bones=192" % [animals, views[0].skel.get_bone_count()])
    var server := OS.get_environment("OCTO_SERVER")
    if server.is_empty(): fail("Set OCTO_SERVER to the octo_server executable"); return
    child = OS.execute_with_pipe(server, [], false)
    if child.is_empty(): fail("Could not start native server: " + server); return
    pipe = child.stdio
    reader.start(read_pipe)
    send(reset_command())

func reset_command() -> String:
    # The fifth field enables low, gravity-settled rest physics.
    # Keep the tetrahedral arm prototype separate and opt-in.
    var volume_arm := 1 if OS.get_environment("OCTO_VOLUME_ARM") == "1" else 0
    var grounded := 0 if OS.get_environment("OCTO_REST_MODE") == "legacy" else 1
    return "reset %d %f 1 %d %d" % [animals,
        1.0 if dense_scene else 2.2, volume_arm, grounded]

func read_pipe() -> void:
    # Drain the pipe independently of render frames. Only complete lines cross
    # to the main thread; physics and scene nodes remain on the main thread.
    var pending_bytes := PackedByteArray()
    while not stop_reader:
        reader_phase = "checking_child"
        if child.has("pid") and not OS.is_process_running(child.pid):
            break
        reader_phase = "checking_output"
        var available := pipe.get_length()
        reader_available = available
        if available <= 0:
            reader_phase = "waiting_output"
            OS.delay_msec(1)
            continue
        reader_phase = "reading_output"
        pending_bytes.append_array(pipe.get_buffer(mini(available, 1048576)))
        if pending_bytes.size() > 4194304:
            inbox_lock.lock()
            inbox.append("OVERSIZE")
            inbox_lock.unlock()
            pending_bytes.clear()
            continue
        var newline := pending_bytes.find(10)
        while newline >= 0:
            var complete := pending_bytes.slice(0, newline).get_string_from_utf8()
            pending_bytes = pending_bytes.slice(newline+1)
            inbox_lock.lock()
            inbox.append(complete)
            inbox_times.append(float(Time.get_ticks_usec()-sent_at)/1000.0)
            var continuing := auto_step and complete.contains('"ok":true') and not stop_reader
            inbox_lock.unlock()
            if continuing:
                reader_phase = "waiting_due"
                while not stop_reader and Time.get_ticks_usec() < next_due_usec:
                    if next_due_usec-Time.get_ticks_usec() > 1500:
                        OS.delay_msec(1)
                inbox_lock.lock()
                var command := reset_command() if reset_requested else latest_command
                reset_requested = false
                if not command.is_empty() and not stop_reader:
                    request_id += 1
                    pending = true
                    sent_at = Time.get_ticks_usec()
                    next_due_usec = maxi(next_due_usec + 16667, sent_at)
                    reader_phase = "writing_request"
                    pipe.store_string("1 %d %s\n" % [request_id,command])
                    pipe.flush()
                    reader_phase = "request_written"
                inbox_lock.unlock()
            newline = pending_bytes.find(10)

func apply_slime_finish(scene: Node3D) -> int:
    var applied := 0
    for node in scene.find_children("*", "MeshInstance3D", true, false):
        var instance := node as MeshInstance3D
        if instance.mesh == null:
            continue
        for surface in range(instance.mesh.get_surface_count()):
            var original := instance.get_active_material(surface)
            if original is StandardMaterial3D:
                # Duplicating avoids global/shared material mutations;
                # imported albedo/normal/roughness textures stay bound.
                var wet := original.duplicate() as StandardMaterial3D
                wet.roughness = 0.20
                wet.clearcoat_enabled = true
                wet.clearcoat = 0.68
                wet.clearcoat_roughness = 0.10
                instance.set_surface_override_material(surface, wet)
                applied += 1
    return applied

func make_stage() -> void:
    var env := WorldEnvironment.new(); var e := Environment.new()
    e.background_mode = Environment.BG_COLOR; e.background_color = Color("101e2b")
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color("a3c2cf"); e.ambient_light_energy = 0.8
    env.environment = e; add_child(env)
    var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-50, -30, 0); light.light_energy = 1.5; add_child(light)
    var floor_node := MeshInstance3D.new(); var floor_mesh := PlaneMesh.new(); floor_mesh.size = Vector2(30,30); floor_node.mesh = floor_mesh
    var mat := StandardMaterial3D.new(); mat.albedo_color = Color("304953"); mat.roughness = 0.9; floor_node.material_override = mat; add_child(floor_node)
    camera = Camera3D.new(); camera.fov = 48; add_child(camera)
    distance = 7.0 + maxf(0, animals - 2) * 0.7
    update_camera()
    target_marker = Node3D.new()
    target_marker.visible = false
    add_child(target_marker)
    var beacon := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.09
    sphere.height = 0.18
    beacon.mesh = sphere
    var beacon_mat := StandardMaterial3D.new()
    beacon_mat.albedo_color = Color(1.0, 0.68, 0.08)
    beacon_mat.emission_enabled = true
    beacon_mat.emission = Color(1.0, 0.52, 0.02)
    beacon_mat.emission_energy_multiplier = 2.5
    beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beacon.material_override = beacon_mat
    target_marker.add_child(beacon)
    var stem := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.012
    cylinder.bottom_radius = 0.012
    cylinder.height = 0.22
    stem.mesh = cylinder
    stem.position.y = -0.16
    stem.material_override = beacon_mat
    target_marker.add_child(stem)
    var layer := CanvasLayer.new(); add_child(layer)
    var panel := PanelContainer.new(); panel.position = Vector2(20,20); panel.custom_minimum_size = Vector2(450,0); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; layer.add_child(panel)
    var box := VBoxContainer.new(); box.mouse_filter = Control.MOUSE_FILTER_IGNORE; panel.add_child(box)
    var title := Label.new(); title.mouse_filter = Control.MOUSE_FILTER_IGNORE; title.text = "O C T O  /  SHARED WORLD"; title.add_theme_font_size_override("font_size", 22); box.add_child(title)
    label = Label.new(); label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.text = "Starting C++ world..."; label.add_theme_font_size_override("font_size", 15); box.add_child(label)
    var help := Label.new(); help.mouse_filter = Control.MOUSE_FILTER_IGNORE; help.text = "U I O P / Q W E R: independent arm controls\\nHold arm: reach > contact > pull > release\\nLeft click: choose target (gold marker)\\nShift + arm: attack targeted object and wrap\\nCtrl + arm: release that arm   Ctrl alone: release all\\nSpace + arm: enable sucker adhesion\\nComma / Period + arm: twist\\nMouse wheel: zoom   Right drag: orbit\\nAlt + left drag: force   Tab: select octopus   F5: reset"; help.add_theme_font_size_override("font_size", 14); box.add_child(help)

func update_camera() -> void:
    var center := Vector3.ZERO
    var states: Array = current.get("animals", [])
    if not states.is_empty():
        center = vec(states[clampi(selected, 0, states.size() - 1)].center)
    camera.position = center + Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))*distance
    camera.look_at(center, Vector3.UP)

func target_center() -> Vector3:
    if current.is_empty():
        return target_hit
    if target_kind == 1 and target_index >= 0 and target_index < current.animals.size():
        return vec(current.animals[target_index].center)
    if target_kind == 2 and target_index >= 0 and target_index < current.rigids.size():
        return vec(current.rigids[target_index].center)
    return target_hit

func update_target_marker() -> void:
    if target_marker == null:
        return
    target_marker.visible = target_kind != 0
    if not target_marker.visible:
        return
    var base := target_center()
    target_hit += base - target_previous_center
    target_previous_center = base
    target_marker.position = base + Vector3.UP * (0.52 if target_kind == 1 else 0.40)

func select_mouse_target(screen_point: Vector2) -> void:
    if camera == null or current.is_empty():
        return
    var origin := camera.project_ray_origin(screen_point)
    var direction := camera.project_ray_normal(screen_point)
    var closest := INF
    var kind := 0
    var index := -1
    var point := Vector3.ZERO
    for i in current.animals.size():
        if i == selected:
            continue
        var center := vec(current.animals[i].center)
        var hit = AABB(center - Vector3(.48, .38, .48),
            Vector3(.96, .76, .96)).intersects_ray(origin, direction)
        if hit != null and origin.distance_to(hit) < closest:
            closest = origin.distance_to(hit)
            kind = 1
            index = i
            point = hit
    for i in current.rigids.size():
        var center := vec(current.rigids[i].center)
        var dimensions := Vector3.ONE * .36
        var hit = AABB(center - dimensions, dimensions * 2).intersects_ray(origin, direction)
        if hit != null and origin.distance_to(hit) < closest:
            closest = origin.distance_to(hit)
            kind = 2
            index = i
            point = hit
    target_kind = kind
    target_index = index
    target_hit = point
    target_previous_center = target_center()
    update_target_marker()

func send(command: String) -> void:
    if pending or pipe == null: return
    inbox_lock.lock()
    request_id += 1; pending = true; sent_at = Time.get_ticks_usec()
    next_due_usec = sent_at + 16667
    pipe.store_string("1 %d %s\n" % [request_id, command]); pipe.flush()
    inbox_lock.unlock()

func poll() -> void:
    if pipe == null: return
    inbox_lock.lock()
    var line: String = inbox.pop_front() if not inbox.is_empty() else ""
    var line_rpc_ms: float = inbox_times.pop_front() if not inbox_times.is_empty() else 0.0
    inbox_lock.unlock()
    if not line.is_empty():
        if line == "OVERSIZE": fail("Bridge response exceeded limit"); return
        var parse_start := Time.get_ticks_usec()
        var parsed = JSON.parse_string(line)
        parse_ms = float(Time.get_ticks_usec()-parse_start)/1000.0
        if not parsed is Dictionary or int(parsed.get("id", -1)) != last_response_id+1 or int(parsed.get("version", 0)) != 1: fail("Invalid or stale bridge response"); return
        last_response_id += 1
        last_progress_usec = Time.get_ticks_usec()
        inbox_lock.lock()
        pending = request_id > last_response_id
        inbox_lock.unlock()
        rpc_ms = line_rpc_ms
        if not parsed.get("ok", false):
            var bridge_error := str(parsed.get("error", "unknown"))
            if bridge_error == "bad_operation":
                fail("C++ server does not support targeted step3 commands. Rebuild the native server with tools/build.ps1 and relaunch PLAY_DEMO.cmd. Server: " + OS.get_environment("OCTO_SERVER"))
            else:
                fail("Bridge: " + bridge_error)
            return
        if parsed.has("snapshot"):
            current = parsed.snapshot
            if current.tick == 0 and reset_issued: reset_observed = true
            if current.tick == 1:
                first_tick_usec = Time.get_ticks_usec()
                frame_wall_ms.clear()
            var skin_start := Time.get_ticks_usec()
            update_scene()
            skin_ms = float(Time.get_ticks_usec()-skin_start)/1000.0
    if auto_step and last_progress_usec > 0 and Time.get_ticks_usec()-last_progress_usec > 15000000:
        fail("Native solver stopped responding for 15 seconds (tick=%d, request=%d, response=%d, pending=%s, reader=%s, child=%s, phase=%s, available=%d)" % [int(current.get("tick", -1)),request_id,last_response_id,str(pending),str(reader.is_alive()),str(OS.is_process_running(child.pid)),reader_phase,reader_available]); return
    if not auto_step and pending and Time.get_ticks_usec()-sent_at > 15000000:
        fail("Native solver timed out during reset"); return
    if child.has("pid") and not OS.is_process_running(child.pid) and not quitting: fail("Native solver exited")

func vec(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])
func quat(a: Array) -> Quaternion: return Quaternion(a[0],a[1],a[2],a[3])
func point(nodes: Array, u: float) -> Vector3:
    var f := u * float(nodes.size()-1); var i := mini(int(f),nodes.size()-2)
    return vec(nodes[i]).lerp(vec(nodes[i+1]), f-i)

func mantle_scale_from_shell(nodes: Array, center: Vector3, inverse: Quaternion) -> Vector3:
    # Only snapshot data: 7 internal cage nodes + 12 collision shell nodes.
    if nodes.size() < 19:
        return Vector3.ONE
    var minimum := Vector3(INF, INF, INF)
    var maximum := Vector3(-INF, -INF, -INF)
    for n in range(7, 19):
        var local_point := inverse * (vec(nodes[n]) - center)
        minimum = minimum.min(local_point)
        maximum = maximum.max(local_point)
    var span := maximum - minimum
    var shape := Vector3(clampf(span.x / 0.44, 0.85, 1.20),
        clampf(span.y / 0.25, 0.85, 1.20),
        clampf(span.z / 0.38, 0.85, 1.20))
    # Scaling the three axes independently previously destroyed visible
    # volume, on top of the shell shader deformation. Keep determinant one.
    return shape / pow(shape.x * shape.y * shape.z, 1.0 / 3.0)

func mantle_respiration(shape: Vector3, elapsed: float) -> Vector3:
    # Slow physiological mantle pumping (~0.25 Hz), not oscillating arm
    # stiffness. Preserve the large shape deformation from the C++ shell.
    return shape

func apply_torso_root_skin(skel: Skeleton3D, root_id: int, rest: Transform3D, size: Vector3) -> void:
    if root_id < 0:
        return
    var parent_id := skel.get_bone_parent(root_id)
    var parent_rest := skel.get_bone_global_rest(parent_id) if parent_id >= 0 else Transform3D.IDENTITY
    var global_target := Transform3D(rest.basis * Basis.from_scale(size), rest.origin)
    skel.set_bone_pose(root_id, parent_rest.affine_inverse() * global_target)

func create_volumetric_preview_mesh(rings: Array) -> ArrayMesh:
    # Explicit experimental 36-vertex physical surface visualizer.
    # Only the *one-arm prototype* uses this compact per-tick mesh;
    # the production GameReady model still uses GPU skeleton skinning.
    var mesh := ArrayMesh.new()
    if rings.size() < 2:
        return mesh
    var vertices := PackedVector3Array()
    for ring in rings:
        if not ring is Array or ring.size() != 4:
            return mesh
        for vertex in ring:
            vertices.append(vec(vertex))
    var indices := PackedInt32Array()
    for j in range(rings.size() - 1):
        for k in 4:
            var a := j * 4 + k
            var b := j * 4 + (k + 1) % 4
            var c := (j + 1) * 4 + k
            var d := (j + 1) * 4 + (k + 1) % 4
            indices.append_array(PackedInt32Array([a, b, d, a, d, c]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func update_scene() -> void:
    for i in current.animals.size():
        var a: Dictionary = current.animals[i]; var view: Dictionary = views[i]
        var scene: Node3D = view.scene; var skel: Skeleton3D = view.skel
        var center := vec(a.center); var orientation := quat(a.orientation)
        update_web(view.web, a.arms)
        scene.position = center - orientation * Quaternion(Vector3.UP,MODEL_YAW) * (Vector3(0,.15,.1)*MODEL_SCALE)
        scene.quaternion = orientation * Quaternion(Vector3.UP,MODEL_YAW)
        var inverse := Quaternion(Vector3.UP,-MODEL_YAW) * orientation.inverse()
        # A physical shell of 12 particles controls the gross mantle
        # flattening/stretching if the GLB exposes a separate mantle mesh.
        # GPU keeps its original vertices; no per-frame mesh allocations.
        var tissue_nodes: Array = a.get("body_nodes", [])
        if tissue_nodes.size() >= 19:
            var shell_rest: Array = view.mantle_rest_shell
            if shell_rest.is_empty() or int(current.tick) == 0:
                shell_rest = []
                for n in range(7, 19):
                    shell_rest.append(inverse * (vec(tissue_nodes[n]) - center) / MODEL_SCALE)
                views[i]["mantle_rest_shell"] = shell_rest
            var offsets := PackedVector3Array()
            for n in range(7, 19):
                var local_shell := inverse * (vec(tissue_nodes[n]) - center) / MODEL_SCALE
                offsets.append((local_shell - shell_rest[n - 7]).limit_length(0.045))
            if not view.skin_config.is_empty():
                skin_deformer.update_mantle(view.skin_config, offsets)
            var shape_scale := mantle_respiration(
                mantle_scale_from_shell(tissue_nodes, center, inverse),
                float(current.get("time", 0.0)))
            var root_id: int = view.torso_root
            if root_id >= 0:
                apply_torso_root_skin(skel, root_id, view.torso_rest, shape_scale)
            if root_id < 0:
                for mantle_entry in view.mantles:
                    var mantle: MeshInstance3D = mantle_entry.node
                    var rest_transform: Transform3D = mantle_entry.rest
                    mantle.transform = Transform3D(
                        rest_transform.basis * Basis.from_scale(shape_scale),
                        rest_transform.origin)
        if not view.skin_config.is_empty():
            skin_deformer.update_skin(view.skin_config, a.arms)
        for arm in 8:
            var nodes: Array = a.arms[arm].nodes
            var key_label: Label3D = view.key_labels[arm]
            key_label.visible = i == selected
            key_label.position = point(nodes, 0.70) + Vector3.UP * 0.10
            var phase := "rest"
            if i < arm_controllers.size() and not arm_controllers[i].phases.is_empty():
                phase = arm_controllers[i].phases[arm]
            key_label.text = OS.get_keycode_string(ARM_KEYS[arm])
            key_label.modulate = Color("e7d29a") if phase != "rest" else Color("adbfc8")
            var material_roll: Array = a.arms[arm].roll
            var radii: Array = a.arms[arm].radii
            if nodes.size() < 2: continue
            var globals := {}
            var torso_root: int = view.torso_root
            if torso_root >= 0 and tissue_nodes.size() >= 19:
                # Seed the parent transform with the physically deformed
                # torso root so arm targets stay world-space correct.
                globals[torso_root] = skel.get_bone_global_pose(torso_root)
            var art := (7-arm)%8
            var ids: Array = view.bone_ids[art]
            var rests: Array = view.bone_rests[art]
            for j in 24:
                var id: int = ids[j]
                var rest: Transform3D = rests[j]
                var j0 := maxi(j-1,0); var j1 := mini(j+1,23)
                var rest0: Vector3 = rests[j0].origin
                var rest1: Vector3 = rests[j1].origin
                var tangent := inverse * (point(nodes,float(j1)/23.0)-point(nodes,float(j0)/23.0)).normalized()
                var swing := Quaternion.IDENTITY
                if (rest1-rest0).length_squared() > 0.000001 and tangent.length_squared() > 0.000001: swing = Quaternion((rest1-rest0).normalized(), tangent)
                var roll_index := mini(int(float(j)*material_roll.size()/24.0),material_roll.size()-1)
                var material_rotation := Quaternion(tangent, float(material_roll[roll_index])) * swing
                var base_radius := .036 * (1.0-.8*float(roll_index)/float(material_roll.size()))
                var cross_section := Vector3(clampf(float(radii[roll_index][0])/base_radius,.40,2.5),1.0,clampf(float(radii[roll_index][1])/base_radius,.40,2.5))
                var target := Transform3D(Basis(material_rotation)*rest.basis*Basis.from_scale(cross_section), Vector3(0,.15,.1)+inverse*(point(nodes,float(j)/23.0)-center)/MODEL_SCALE)
                var parent := skel.get_bone_parent(id)
                var parent_global: Transform3D = globals.get(parent, skel.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY)
                skel.set_bone_pose(id,parent_global.affine_inverse()*target); globals[id] = target
    while props.size() < current.rigids.size():
        var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); var mat := StandardMaterial3D.new(); mat.albedo_color = Color("42a4c4"); mat.roughness = 0.4; mesh.material_override = mat; add_child(mesh); props.append(mesh)
    if OS.get_environment("OCTO_VOLUME_ARM") == "1":
        for i in current.animals.size():
            var candidate: MeshInstance3D = views[i].volume_preview
            if candidate != null:
                candidate.mesh = create_volumetric_preview_mesh(
                    current.animals[i].arms[0].get("volume_rings", []))
    for i in current.rigids.size():
        var r: Dictionary = current.rigids[i]; props[i].position = vec(r.center); props[i].quaternion = quat(r.orientation); props[i].scale = vec(r.half_extents)*2.0
    if current.tick == 0 or current.tick == 1: print("SNAPSHOT tick=%d animals=%d arms=%d first_node=%s" % [current.tick,current.animals.size(),current.animals[0].arms.size(),str(current.animals[0].arms[0].nodes[0])])

func update_web(web: MeshInstance3D, arms: Array) -> void:
    var mesh := web.mesh as ImmediateMesh
    mesh.clear_surfaces()
    var hub := Vector3.ZERO
    for arm in arms:
        hub += vec(arm.nodes[0]) / 8.0
    var outline: Array[Vector3] = []
    for k in 8:
        var a := point(arms[k].nodes, 0.25)
        var b := point(arms[(k + 1) % 8].nodes, 0.25)
        outline.append(a)
        # Scalloped edge leaves the outer three quarters of every arm free.
        outline.append(hub.lerp((a + b) * 0.5, 0.78))
    mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
    for k in range(outline.size()):
        var a := outline[k]
        var b := outline[(k + 1) % outline.size()]
        var normal := (a - hub).cross(b - hub).normalized()
        for vertex in [hub, a, b]:
            mesh.surface_set_normal(normal)
            mesh.surface_add_vertex(vertex)
    mesh.surface_end()

func idle_arm_shape(animal: int, arm: int) -> Dictionary:
    # Mirror-symmetric radial rest target. The C++ motor is weak and
    # yields to collision/gravity, so limbs do not rigidly snap home.
    return {"extension": 1.04,
            "curvature": 0.0,
            "activation": 0.0,
            "sweep": 0.0}

func measure_skin_floor() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var minimum := INF
    for view in views:
        view.skel.force_update_all_bone_transforms()
        for child_node in view.scene.find_children("*", "MeshInstance3D", true, false):
            var mesh_node := child_node as MeshInstance3D
            if mesh_node.mesh == null or mesh_node.skin == null:
                continue
            var baked := mesh_node.bake_mesh_from_current_skeleton_pose()
            if baked == null:
                continue
            var part_min := INF
            for surface in range(baked.get_surface_count()):
                var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
                for vertex in vertices:
                    minimum = minf(minimum, (mesh_node.global_transform * vertex).y)
                    part_min = minf(part_min, (mesh_node.global_transform * vertex).y)
            if part_min < -0.01:
                print("SKIN_FLOOR_PART name=%s min_y=%.5f" % [mesh_node.name,part_min])
    print("SKIN_FLOOR min_baked_vertex_y_m=%.6f (shader displacement excluded)" % minimum)

func step_command() -> String:
    while arm_controllers.size() < animals:
        arm_controllers.append(ARM_CONTROLS.new())
    var time := float(current.get("time", 0.0))
    var suction_on := Input.is_physical_key_pressed(KEY_SPACE)
    var ctrl_on := Input.is_physical_key_pressed(KEY_CTRL)
    var any_arm_pressed := false
    for key in ARM_KEYS:
        any_arm_pressed = any_arm_pressed or Input.is_physical_key_pressed(key)
    var out := "step3 %d" % (animals * 8)
    for i in animals:
        for arm in 8:
            var manual := i == selected and Input.is_physical_key_pressed(ARM_KEYS[arm])
            var release_grab := i == selected and ctrl_on and (manual or not any_arm_pressed)
            var grab_nearest := manual and Input.is_physical_key_pressed(KEY_SHIFT) and not release_grab and target_kind != 0
            var held := (manual and not release_grab) or test_all_active or (test_actuation and i == 0 and arm == 0)
            var attached := false
            if not current.is_empty():
                for grip in current.animals[i].arms[arm].get("attached", []):
                    attached = attached or bool(grip)
            var sign := 1.0
            var cmd: Dictionary = arm_controllers[i].sample(arm, time, held,
                false, false, false, attached and suction_on, sign, suction_on)
            if grab_nearest:
                # Reach stays active while Shift is held; no automatic
                # contraction phase can peel away an acquired object.
                cmd.activation = 0.90
                cmd.extension = 1.42
                cmd.curvature = 0.0
                cmd.sweep = 0.0
            if arm_controllers[i].phases[arm] == "rest":
                # Symmetric resting configuration, with an active low-force
                # restoring motor in the C++ world rather than a teleport.
                cmd.extension = 1.04
                cmd.curvature = 0.0
                cmd.sweep = 0.0
            var twist := 0.0
            if manual:
                twist = (float(Input.is_physical_key_pressed(KEY_PERIOD)) - float(Input.is_physical_key_pressed(KEY_COMMA))) * 3.0
            if test_actuation and i == 0 and arm == 0: twist = 3.0
            out += " %d %d %f %f %f %f %f %d %f" % [
                i, arm, cmd.activation, cmd.curvature, cmd.extension, twist, 0.02,
                2 if release_grab else (1 if grab_nearest else 0), cmd.sweep]
    out += " %d %d 0 %f %f %f 30 20 %d" % [
        drag_kind if dragging else 0, drag_index,
        drag_target.x, drag_target.y, drag_target.z,
        1 if suction_on else 0]
    out += " %d %d %f %f %f" % [
        target_kind, maxi(target_index, 0), target_hit.x, target_hit.y, target_hit.z]
    return out

func inject_key(code: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)

func exercise_input() -> void:
    if not test_input or animals != 2: return
    if current.tick >= 50 and input_phase == 1:
        var active_tip := vec(current.animals[1].arms[0].nodes[-1]) - vec(current.animals[1].center)
        var passive_tip := vec(current.animals[0].arms[0].nodes[-1]) - vec(current.animals[0].center)
        input_arm_delta = maxf(input_arm_delta,active_tip.distance_to(passive_tip)-input_arm_baseline)
    if current.tick >= 90 and input_phase == 3:
        var center := vec(current.animals[1].center)
        input_center_delta = maxf(input_center_delta,Vector2(center.x,center.z).distance_to(Vector2(input_center_baseline.x,input_center_baseline.z)))
    if current.tick >= 10 and input_phase == 0:
        var active_tip := vec(current.animals[1].arms[0].nodes[-1]) - vec(current.animals[1].center)
        var passive_tip := vec(current.animals[0].arms[0].nodes[-1]) - vec(current.animals[0].center)
        input_arm_baseline = active_tip.distance_to(passive_tip)
        inject_key(KEY_TAB,true)
        inject_key(KEY_TAB,false)
        inject_key(KEY_R,true)
        input_phase = 1
    if current.tick >= 55 and input_phase == 1:
        inject_key(KEY_R,false)
        inject_key(KEY_ALT,true)
        input_center_baseline = vec(current.animals[1].center)
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.position = camera.unproject_position(vec(current.animals[1].center))
        event.pressed = true
        Input.parse_input_event(event)
        input_phase = 2
    if current.tick >= 60 and input_phase == 2:
        var motion := InputEventMouseMotion.new()
        motion.position = camera.unproject_position(vec(current.animals[1].center)) + Vector2(100,-40)
        Input.parse_input_event(motion)
        input_phase = 3
    if current.tick >= 95 and input_phase == 3:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = false
        Input.parse_input_event(event)
        inject_key(KEY_ALT,false)
        input_phase = 4

# Render-only HUD field: native snapshots produced before controls-v1
# do not contain 'attached'. Keep the scene usable while those binaries
# are being replaced; never infer active suction from missing fields.
func count_grips_from_snapshot(state: Dictionary) -> int:
    var count := 0
    for animal in state.get("animals", []):
        for arm in animal.get("arms", []):
            for contact in arm.get("attached", []):
                if contact == true:
                    count += 1
    return count

func _process(delta: float) -> void:
    var start := Time.get_ticks_usec(); poll()
    if current.is_empty() or quitting: return
    exercise_input()
    if test_crawl:
        if current.tick >= 10 and not crawl_started:
            crawl_started = true
            crawl_origin = vec(current.animals[selected].center)
            inject_key(KEY_UP, true)
        if current.tick >= benchmark_ticks - 45 and not crawl_released:
            crawl_released = true
            inject_key(KEY_UP, false)
        crawl_grips = maxi(crawl_grips, count_grips_from_snapshot(current))
        if selected < arm_controllers.size():
            for phase in arm_controllers[selected].phases: crawl_phases[phase] = true
    if test_kill_native and current.tick >= 20 and not killed_native:
        killed_native = true
        OS.kill(child.pid)
    if test_reset and current.tick >= 120 and not reset_issued:
        reset_issued = true
        inbox_lock.lock()
        reset_requested = true
        inbox_lock.unlock()
    if first_tick_usec > 0 and current.tick > 1: frame_wall_ms.append(delta*1000.0)
    update_camera()
    update_target_marker()
    var grip_count := count_grips_from_snapshot(current)
    label.text = "Animal %d / %d    Tick %d    %.2f s\nSolver %.2f ms   RPC %.2f ms   Contacts %d   Grips %d\nParse %.2f ms   Skin %.2f ms   Command %.2f ms" % [selected+1,animals,current.tick,current.time,current.diagnostics.step_ms,rpc_ms,current.diagnostics.contact_count,grip_count,parse_ms,skin_ms,command_ms]
    var active_labels := PackedStringArray()
    if selected < arm_controllers.size():
        for arm in arm_controllers[selected].phases.size():
            var phase: String = arm_controllers[selected].phases[arm]
            if phase != "rest":
                active_labels.append("%s:%s" % [OS.get_keycode_string(ARM_KEYS[arm]),phase])
    label.text += "\nArms: " + (", ".join(active_labels) if not active_labels.is_empty() else "relaxed")
    var command_start := Time.get_ticks_usec()
    var next_command := step_command()
    if test_input:
        input_arm_seen = input_arm_seen or (selected == 1 and Input.is_physical_key_pressed(KEY_R) and next_command.contains(" 1 0 0.800000 0.050000 1.380000"))
        input_drag_seen = input_drag_seen or (dragging and drag_kind == 1 and drag_index == 1 and drag_target.distance_to(vec(current.animals[1].center)) > .05)
    command_ms = float(Time.get_ticks_usec()-command_start)/1000.0
    inbox_lock.lock()
    latest_command = next_command
    inbox_lock.unlock()
    if not auto_step:
        auto_step = true
        send(next_command)
    frame_sum += float(Time.get_ticks_usec()-start)/1000.0; frame_count += 1
    if smoke and current.tick >= benchmark_ticks and (not test_reset or reset_observed):
        if test_crawl:
            var travel := vec(current.animals[selected].center) - crawl_origin
            print("CRAWL_CHECK phases=%s grips_peak=%d travel_m=%s released=%s" % [str(crawl_phases.keys()),crawl_grips,str(travel),str(crawl_released)])
            if not crawl_phases.has("pull") or crawl_grips == 0 or not crawl_released:
                fail("Crawl assist did not complete a physical grip/pull/release cycle"); return
        if test_input:
            print("INPUT_CHECK selected=%d arm=%s drag=%s phase=%d arm_delta_m=%.5f center_delta_m=%.5f" % [selected,str(input_arm_seen),str(input_drag_seen),input_phase,input_arm_delta,input_center_delta])
            if not input_arm_seen or not input_drag_seen or input_arm_delta < .005 or input_center_delta < .002: fail("Key or mouse input did not produce physical response"); return
        smoke = false
        if test_reset: print("RESET_CHECK issued=%s observed=%s" % [reset_issued,reset_observed])
        if test_actuation:
            var measured_roll := float(current.animals[0].arms[0].roll[8])
            print("ACTUATION_CHECK roll_mid_rad=%.5f tip_y_m=%.5f" % [measured_roll,float(current.animals[0].arms[0].nodes[-1][1])])
            if measured_roll < 0.25: fail("Nonzero twist did not reach the original-model renderer"); return
        measure_skin_floor()
        var elapsed_ms := float(Time.get_ticks_usec()-first_tick_usec)/1000.0
        var ordered := frame_wall_ms.duplicate()
        ordered.sort()
        var wall_p95: float = ordered[mini(int(ceil(ordered.size()*0.95))-1,ordered.size()-1)] if not ordered.is_empty() else 0.0
        var slow_frames := 0
        for frame_ms in ordered:
            if frame_ms > 16.667: slow_frames += 1
        print("SMOKE_OK tick=%d elapsed_ms=%.3f effective_sim_tps=%.3f render_frames=%d wall_p95_ms=%.3f slow_frames=%d frame_cpu_avg_ms=%.3f rpc_ms=%.3f solver_ms=%.3f parse_ms=%.3f skin_ms=%.3f command_ms=%.3f" % [current.tick,elapsed_ms,float(current.tick-1)*1000.0/elapsed_ms,ordered.size(),wall_p95,slow_frames,frame_sum/maxi(frame_count,1),rpc_ms,current.diagnostics.step_ms,parse_ms,skin_ms,command_ms])
        if not screenshot.is_empty() and DisplayServer.get_name() != "headless":
            await RenderingServer.frame_post_draw
            var err := get_viewport().get_texture().get_image().save_png(screenshot)
            print("SCREENSHOT path=%s error=%d" % [screenshot,err])
            if err != OK: get_tree().quit(2); return
        get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_TAB: selected = (selected+1)%animals
        if event.keycode == KEY_F5:
            inbox_lock.lock()
            reset_requested = true
            inbox_lock.unlock()
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = clampf(distance * 0.88, 1.7, 30.0)
            update_camera()
            get_viewport().set_input_as_handled()
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance = clampf(distance / 0.88, 1.7, 30.0)
            update_camera()
            get_viewport().set_input_as_handled()
            return
    if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): yaw -= event.relative.x*.005; pitch = clampf(pitch+event.relative.y*.005,.12,1.45)
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not current.is_empty():
        dragging = false
        if event.pressed:
            if Input.is_physical_key_pressed(KEY_ALT):
                var origin := camera.project_ray_origin(event.position)
                var direction := camera.project_ray_normal(event.position)
                var nearest := INF
                for i in current.animals.size() + current.rigids.size():
                    var center: Vector3 = vec(current.animals[i].center) if i < animals else vec(current.rigids[i-animals].center)
                    var extent := Vector3.ONE * (0.4 if i < animals else 0.25)
                    var hit = AABB(center-extent, extent*2).intersects_ray(origin, direction)
                    if hit != null and origin.distance_to(hit) < nearest:
                        nearest = origin.distance_to(hit)
                        dragging = true
                        drag_kind = 1 if i < animals else 3
                        drag_index = i if i < animals else i-animals
                        drag_target = center
                if dragging:
                    drag_plane = Plane(camera.global_basis.z, drag_target)
            else:
                select_mouse_target(event.position)
    if event is InputEventMouseMotion and dragging:
        var hit = drag_plane.intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
        if hit != null: drag_target = hit

func fail(message: String) -> void:
    stop_reader = true
    push_error(message)
    if label != null: label.text = "ERROR: " + message
    quitting = true
    if smoke: get_tree().quit(2)

func _exit_tree() -> void:
    stop_reader = true
    if reader.is_started(): reader.wait_to_finish()
    if pipe != null and child.has("pid") and OS.is_process_running(child.pid):
        if not pending: pipe.store_string("1 %d quit\n" % (request_id+1)); pipe.flush()
        pipe.close(); OS.kill(child.pid)
