class_name PhysicsGrabDemo
extends Node3D
## Movable rigid tentacle tips with finite support springs, for two-way force tests.
var target: HunterTarget
var anchors: Dictionary = {}
var anchor_mass: float = 8.0
var support_stiffness: float = 700.0
var selected_part: StringName = &"right_forearm"

func grab(part: StringName, strength: float = 1.0) -> RigidBody3D:
	if not is_instance_valid(target.physics_rig):return null
	selected_part=part
	if anchors.has(part):
		var existing: RigidBody3D=anchors[part]["body"]
		if target.physics_rig.grips.has(anchors[part]["grip"]):return existing
		if is_instance_valid(existing):existing.queue_free()
		anchors.erase(part)
	var point := target.physics_rig.get_part_position(part)
	var body := RigidBody3D.new()
	body.name="TentacleTip_"+String(part)
	add_child(body)
	body.global_position=point
	body.mass=anchor_mass
	body.gravity_scale=0.0
	body.collision_layer=8
	body.collision_mask=1|4
	body.linear_damp=0.25
	body.angular_damp=0.4
	body.can_sleep=false
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius=0.055
	collision.shape=sphere
	body.add_child(collision)
	# The grasping contact overlaps the grabbed hitbox; exclude only that pair.
	body.add_collision_exception_with(target.physics_rig.get_part_body(part))
	var mesh := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius=0.075
	orb.height=0.15
	mesh.mesh=orb
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("af84df")
	material.metallic=0.25
	material.roughness=0.4
	mesh.material_override=material
	body.add_child(mesh)
	var grip := target.physics_rig.attach_grip(part,body,point,1300.0*strength,55.0*sqrt(strength),450.0*strength,2.5)
	anchors[part]={"body":body,"goal":point,"grip":grip}
	return body

func release_all() -> void:
	if is_instance_valid(target.physics_rig):target.physics_rig.clear_grips()
	for item in anchors.values():
		if is_instance_valid(item["body"]):item["body"].queue_free()
	anchors.clear()

func set_mass(value: float) -> void:
	anchor_mass=value
	for item in anchors.values():
		if is_instance_valid(item["body"]):item["body"].mass=value

func push_selected() -> void:
	if is_instance_valid(target.physics_rig):
		target.physics_rig.apply_part_impulse(selected_part,Vector3(2.2,0.3,0))

func _physics_process(delta: float) -> void:
	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_LEFT):movement.x-=1.0
	if Input.is_key_pressed(KEY_RIGHT):movement.x+=1.0
	if Input.is_key_pressed(KEY_UP):movement.z-=1.0
	if Input.is_key_pressed(KEY_DOWN):movement.z+=1.0
	for part in anchors.keys():
		var item: Dictionary=anchors[part]
		var body: RigidBody3D=item["body"]
		if not is_instance_valid(body):
			anchors.erase(part)
			continue
		if part==selected_part:item["goal"]+=movement*delta*0.8
		var goal: Vector3=item["goal"]
		var force := (goal-body.global_position)*support_stiffness-body.linear_velocity*35.0
		body.apply_central_force(force.limit_length(1200.0))
		body.set_meta("support_point",goal+Vector3(1.4,-0.6,-0.8))
