extends SceneTree
## Regression: rolling mud was rejecting all 32 horizontal flee sweeps.

var failures: Array[String] = []
var checks := 0
var measurements: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("PASS: ", message)
	else:
		failures.append(message)
		printerr("FAIL: ", message)

func ticks(count: int) -> void:
	for i in range(count): await physics_frame

func escape_case(lab: Node3D, level: int, spawn: Vector2, minimum_travel: float) -> void:
	lab._set_level(level)
	if spawn != Vector2.INF:
		lab.hunter.reset_target(Vector3(spawn.x, lab.arena.terrain_height(spawn.x, spawn.y) + 0.04, spawn.y))
	await ticks(60)
	var actor: HunterTarget = lab.hunter
	var start := actor.global_position
	lab.threat.global_position = start + Vector3(-3, 0, 0)
	lab.threat.active = true
	lab.threat.severable = false
	await ticks(2)
	actor._scan_threats()
	var name := "Level %d at %s" % [level, str(Vector2(start.x, start.z))]
	check(actor.perceived_threats.size() == 1, name + " sees the grounded exposed tentacle")
	var travel := 0.0
	var previous := actor.global_position
	var stalled_frames := 0
	var fall_frames := 0
	for i in range(480):
		await physics_frame
		travel += Vector2(actor.position.x - previous.x, actor.position.z - previous.z).length()
		previous = actor.global_position
		if actor._steering.length_squared() < 0.01: stalled_frames += 1
		if actor.is_fallen(): fall_frames += 1
	var displacement := Vector2(actor.position.x - start.x, actor.position.z - start.z).length()
	check(travel > minimum_travel and displacement > 5.0, name + " escapes across the uneven terrain")
	check(stalled_frames < 60, name + " does not reject every route and stop")
	check(fall_frames == 0, name + " does not spontaneously fall during ordinary flight")
	measurements.append({"level": level, "start": str(start), "travel_metres": travel,
		"displacement_metres": displacement, "stalled_frames": stalled_frames})

func solid(parent: Node3D, position_3d: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = position_3d
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _run() -> void:
	var lab: Node3D = load("res://scenes/tidal_hunter_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await escape_case(lab, 2, Vector2.INF, 18.0)
	await escape_case(lab, 1, Vector2.INF, 8.0)
	await escape_case(lab, 2, Vector2(0, 0), 14.0)
	await escape_case(lab, 2, Vector2(2.8, 3.8), 12.0)
	# Click placement must hit the real negative-height pool, not the old y=0 plane.
	lab._reset()
	await ticks(12)
	var pool_point := Vector3(0, lab.arena.terrain_height(0, 0), 0)
	lab.camera.position = Vector3(0, 8, 8)
	lab.camera.look_at(pool_point)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = lab.camera.unproject_position(pool_point)
	lab._unhandled_input(click)
	check(Vector2(lab.threat.position.x, lab.threat.position.z).length() < 0.1 and lab.threat.position.y < -0.6,
		"Mouse placement uses the visible pool floor below zero")
	check(absf(lab.threat.position.y - lab.arena.terrain_height(lab.threat.position.x, lab.threat.position.z) - 0.025) < 0.001,
		"Virtual tentacle stays on the actual local terrain")
	lab.queue_free()
	await ticks(3)
	# Analytic ramp separates walkable floor contact from an actual wall and cliff.
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var floor_body := solid(world, Vector3(0, -0.15, 0), Vector3(12, 0.3, 12))
	floor_body.rotation.z = deg_to_rad(10)
	var actor: HunterTarget = load("res://scenes/hunter_target.tscn").instantiate()
	world.add_child(actor)
	await ticks(70)
	check(actor.test_move(actor.global_transform, Vector3.RIGHT * 3.0), "Ramp reproduces the old false obstacle result")
	check(actor._probe_flee_path(Vector3.RIGHT, 3.0).is_finite(), "Walkable uphill floor remains a valid escape route")
	var threat := HunterThreat.new()
	world.add_child(threat)
	threat.position = Vector3(3, -3, 0)
	threat.aim_offset = Vector3.UP * (3.95 + tan(deg_to_rad(10)) * 3.0)
	await ticks(2)
	actor._scan_threats()
	check(actor.perceived_threats.size() == 1, "An exposed tip is sensed even when its base is beneath terrain")
	var wall := solid(world, Vector3(1.5, 1.3, 0), Vector3(0.3, 2.6, 5))
	await ticks(2)
	check(not actor._probe_flee_path(Vector3.RIGHT, 3.0).is_finite(), "Real wall behind the slope still blocks escape")
	actor._scan_threats()
	check(actor.perceived_threats.is_empty(), "Solid wall still occludes a tentacle tip")
	wall.queue_free()
	await ticks(2)
	actor.reset_target(Vector3(4.8, tan(deg_to_rad(10)) * 4.8 + 0.03, 0))
	await ticks(3)
	check(not actor._probe_flee_path(Vector3.RIGHT, 3.0).is_finite(), "Planner rejects a route off an unsupported cliff")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "measurements": measurements}
	FileAccess.open("res://.tools/terrain_evasion_results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("TERRAIN_EVASION_TEST_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
