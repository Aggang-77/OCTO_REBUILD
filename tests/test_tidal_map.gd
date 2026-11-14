extends SceneTree
## Integration checks against the baked map and the actual Jolt simulation.

var failures: Array[String] = []
var checks := 0
var preview: Node3D
var arena: TidalArena

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value:
		print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame

func ray(from: Vector3, to: Vector3, mask: int = 1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return arena.get_world_3d().direct_space_state.intersect_ray(query)

func _run() -> void:
	preview = load("res://scenes/tidal_colosseum.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	arena = preview.get_node("TidalColosseum")
	await ticks(5)
	check(arena.props.size() == 48, "All 48 imported movable props are registered")
	check(arena.get_node("SpawnPoints/OctopusSpawn").is_in_group("octopus_spawn"), "Octopus spawn marker is ready for integration")
	check(arena.get_node("ColosseumRuins/WeatheredLimestone").mesh.get_surface_count() == 1, "All architecture is batched into one rendering surface")
	var valid_collisions := true
	for body in arena.props:
		var collision := body.get_node("CollisionShape3D") as CollisionShape3D
		valid_collisions = valid_collisions and collision.shape is ConvexPolygonShape3D
		valid_collisions = valid_collisions and body.collision_layer == 16 and body.collision_mask == 31 and body.continuous_cd
	check(valid_collisions, "Every movable uses a convex hull, continuous collision, and character/tentacle/prop masks")
	var floor_match := true
	for point: Vector2 in [Vector2(0, 0), Vector2(3, -2), Vector2(-8, 4.5), Vector2(12, 3), Vector2(-4, -9)]:
		var hit := ray(Vector3(point.x, 5, point.y), Vector3(point.x, -3, point.y))
		floor_match = floor_match and not hit.is_empty()
		if not hit.is_empty():
			floor_match = floor_match and absf(hit.position.y - arena.terrain_height(point.x, point.y)) < 0.055
			floor_match = floor_match and hit.normal.y > 0.4
	check(floor_match, "Visible mudflat and pool depressions have matching upward-facing physical ground")
	var bay_angle := PI
	var opening_angle := bay_angle + PI / 36.0
	var opening := Vector3(sin(opening_angle), 0, cos(opening_angle))
	var pier := Vector3(sin(bay_angle), 0, cos(bay_angle))
	check(ray(opening * 26 + Vector3.UP * 1.4, opening * 22 + Vector3.UP * 1.4).is_empty(), "Arched doorway is physically open")
	check(not ray(pier * 26 + Vector3.UP * 1.4, pier * 22 + Vector3.UP * 1.4).is_empty(), "Stone pier blocks movement beside the doorway")
	await ticks(360)
	var no_fallthrough := true
	var max_speed := 0.0
	for body in arena.props:
		no_fallthrough = no_fallthrough and body.position.y > -2.0
		max_speed = maxf(max_speed, body.linear_velocity.length())
	check(no_fallthrough, "All 48 props remain on the terrain after six seconds of gravity")
	check(max_speed < 1.5, "Props settle without unstable or exploding contacts")
	var stone: RigidBody3D
	var barrel: RigidBody3D
	for body in arena.props:
		if body.name.begins_with("sea_rock_small") and stone == null: stone = body
		if body.name.begins_with("barrel") and barrel == null: barrel = body
	stone.position = Vector3(5.0, 2.0, 0)
	stone.linear_velocity = Vector3.ZERO
	stone.angular_velocity = Vector3.ZERO
	stone.sleeping = false
	await ticks(100)
	var rest_y := stone.position.y
	check(rest_y < 1.0 and rest_y > -0.3, "A dropped stone lands on the dry mud surface")
	stone.apply_central_impulse(Vector3(5, 4, 0) * stone.mass)
	await ticks(12)
	check(stone.position.y > rest_y + 0.25 and stone.position.x > 5.3, "A physical impulse throws the imported prop upward and sideways")
	barrel.position = Vector3(0.0, 0.5, 0.0)
	barrel.linear_velocity = Vector3.ZERO
	barrel.angular_velocity = Vector3.ZERO
	barrel.sleeping = false
	stone.position = Vector3(0.85, 0.4, 0.0)
	stone.linear_velocity = Vector3.ZERO
	stone.angular_velocity = Vector3.ZERO
	stone.sleeping = false
	await ticks(240)
	check(barrel.position.y > stone.position.y + 0.15, "Wood flotation and water damping differ from a sinking stone in the tidal pool")
	preview._grabbed = barrel
	preview._release(true)
	await ticks(3)
	check(barrel.linear_velocity.length() > 2.0 and preview._grabbed == null, "Preview throw control releases and applies a real impulse")
	arena.reset_props()
	await ticks(1)
	var reset_ok := true
	for body in arena.props:
		var spawn: Transform3D = arena._initial_transforms[body]
		reset_ok = reset_ok and body.position.distance_to(spawn.origin) < 0.08
	check(reset_ok, "Reset restores every prop to its original local spawn")
	for view in [1, 2, 3]:
		preview._set_view(view)
	check(preview.camera.position.is_finite(), "All three preview cameras produce a valid transform")
	preview._toggle_colliders()
	check(preview._debug_bodies.size() == arena.props.size(), "Collision preview exposes all real prop hulls")
	preview._toggle_colliders()
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "maximum_settled_speed": max_speed}
	print("TIDAL_MAP_TEST_RESULT ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
