extends SceneTree
var world: Node3D
var target: HunterTarget
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks+=1
	if value:print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func ticks(count: int) -> void:
	for i in range(count):await physics_frame

func _run() -> void:
	world=Node3D.new()
	root.add_child(world)
	current_scene=world
	var floor_body:=StaticBody3D.new()
	world.add_child(floor_body)
	floor_body.position.y=-0.1
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(100,0.2,100)
	collision.shape=shape
	floor_body.add_child(collision)
	target=load("res://scenes/hunter_target.tscn").instantiate()
	world.add_child(target)
	await ticks(120)
	var rig:=target.physics_rig
	check(rig.parts.size()==15,"Fifteen actual rigid-body hitboxes exist")
	check(rig.total_mass>50.0 and rig.total_mass<65.0,"Body parts have a plausible finite total mass")
	var error_sum:=0.0
	var maximum_error:=0.0
	for part in rig.parts.values():
		error_sum+=float(part["error"])
		maximum_error=maxf(maximum_error,part["error"])
	print("PHYSICS_IDLE ",rig.get_snapshot()," mean_error ",error_sum/15.0," max_error ",maximum_error)
	check(maximum_error<0.10,"Unrestrained physical body stays near its animated pose")
	var external:=RigidBody3D.new()
	world.add_child(external)
	external.mass=6.0
	external.gravity_scale=0.0
	external.collision_layer=8
	external.collision_mask=0
	external.global_position=rig.get_part_position(&"right_forearm")
	var id:=rig.attach_grip(&"right_forearm",external,external.global_position,1000.0,45.0,400.0,3.0)
	check(id>0,"A physical limb can be gripped by an external rigid body")
	var initial:=external.global_position
	rig.apply_part_impulse(&"right_forearm",Vector3(3.0,0.0,0.0))
	var force_peak:=0.0
	var motion_peak:=0.0
	var minimum_mobility:=1.0
	for i in range(40):
		await physics_frame
		force_peak=maxf(force_peak,rig.last_external_force.length())
		motion_peak=maxf(motion_peak,external.global_position.distance_to(initial))
		minimum_mobility=minf(minimum_mobility,rig.get_mobility(&"right_forearm"))
	print("PHYSICS_COUPLING ",rig.get_snapshot()," external_motion ",external.global_position.distance_to(initial)," force_peak ",force_peak," minimum_mobility ",minimum_mobility)
	check(force_peak>0.5,"Character effort reaches the external restraint as a real force")
	check(motion_peak>0.005,"External rigid body physically moves from the transmitted effort")
	check((rig.last_character_force+rig.last_external_force).length()<0.001,"Grip contact forces are equal and opposite")
	check(minimum_mobility>0.0 and minimum_mobility<0.99,"Arm mobility weakens continuously instead of switching off")
	external.freeze=true
	external.global_position+=Vector3(0.25,0,0)
	await ticks(30)
	check(rig.parts[&"right_forearm"]["error"]>0.02,"A held limb deviates from its authored animation")
	check(rig.get_action_efficiency(&"slash")>0.0,"A restrained sword arm retains nonzero effort")
	var source:=Node3D.new()
	world.add_child(source)
	source.global_position=target.global_position+Vector3(0,0,1.5)
	target.profile=load("res://assets/hunter/level_3.tres")
	target._start_action(&"slash",source)
	check(target.state==&"slash" and target._action_left>0.0,"A held arm still attempts its authored attack")
	rig.release_grip(id)
	check(rig.grips.is_empty(),"A physical grip can be released")
	await ticks(90)
	check(rig.get_mobility(&"right_forearm")>minimum_mobility,"Released arm recovers motion")
	# Verify a contact against a physics hitbox, independently of the grip API.
	var projectile:=RigidBody3D.new()
	projectile.mass=2.0
	projectile.gravity_scale=0.0
	projectile.collision_layer=8
	projectile.collision_mask=4
	world.add_child(projectile)
	var projectile_collision:=CollisionShape3D.new()
	var projectile_shape:=SphereShape3D.new()
	projectile_shape.radius=0.07
	projectile_collision.shape=projectile_shape
	projectile.add_child(projectile_collision)
	projectile.global_position=rig.get_part_position(&"left_forearm")+Vector3(0.3,0,0)
	projectile.linear_velocity=Vector3(-2,0,0)
	var contact_seen:=false
	for i in range(24):
		await physics_frame
		for item in rig.parts.values():
			if projectile in item["body"].get_colliding_bodies():contact_seen=true
	check(contact_seen,"External moving body collides with the actual limb hitboxes")
	projectile.queue_free()
	for index in range(3):
		target.set_character(index)
		await ticks(120)
		var pose_error:=0.0
		for item in target.physics_rig.parts.values():pose_error=maxf(pose_error,item["error"])
		check(pose_error<0.12,"Character %d physical body holds its unrestrained posture"%index)
		var hair_count:=0
		for mesh in target.get_node("Visual/Model").find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var mat: Material=mesh.get_active_material(surface)
				if mat is ShaderMaterial and mat.shader==load("res://assets/characters/hair_recolor.gdshader"):
					hair_count+=1
					check(mat.get_shader_parameter("hair_color")==HunterAnimation.HAIR_COLORS[index],"Character %d uses the requested hair color"%index)
		check(hair_count>0,"Character %d recolors only tagged hair surfaces"%index)
	var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
	var file:=FileAccess.open("res://.tools/physics_test_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("PHYSICS_TEST_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
