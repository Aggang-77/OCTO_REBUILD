class_name HunterCombatHitboxes
extends Node3D
## Visual-pose hurtboxes and independent, windowed hand/foot/knee hitboxes.
## All damage contacts come from Shape3D overlap queries, including swept samples.
const HIT_LAYER: int=32
const HURT_LAYER: int=64
const DODGE_LAYER: int=128
var actor: HunterTarget
var skeleton: Skeleton3D
var fighter: HunterFighter
var hurtboxes: Dictionary={}
var hitboxes: Dictionary={}
var dodge_trace: Array[Area3D]=[]
var debug_visible: bool=false
var last_contact: Dictionary={}
var _exclusions: Array[RID]=[]

func setup(owner_actor: HunterTarget, driver: HunterFighter) -> void:
	if is_instance_valid(skeleton) and skeleton.skeleton_updated.is_connected(_sample_pose):skeleton.skeleton_updated.disconnect(_sample_pose)
	actor=owner_actor
	fighter=driver
	skeleton=actor.animation.skeleton
	for child in get_children():
		remove_child(child)
		child.queue_free()
	hurtboxes.clear()
	hitboxes.clear()
	dodge_trace.clear()
	_exclusions.clear()
	for part_name in actor.physics_rig.part_order:
		var part: Dictionary=actor.physics_rig.parts[part_name]
		var body: RigidBody3D=part["body"]
		var collision: CollisionShape3D=body.get_child(0)
		var area:=_area("Hurt_"+String(part_name),collision.shape.duplicate(),Color(0.25,0.75,0.95,0.22))
		area.collision_layer=HURT_LAYER
		area.set_meta("hurt_actor",actor)
		area.set_meta("hurt_part",part_name)
		area.add_to_group("hunter_hurtboxes")
		var local:=Transform3D(collision.basis,part["offset"])
		hurtboxes[part_name]={"area":area,"bone":part["bone"],"local":local}
		_exclusions.append(area.get_rid())
	for name in [&"left_hand",&"right_hand",&"left_foot",&"right_foot",&"left_knee",&"right_knee",&"left_elbow",&"right_elbow",&"left_shin",&"right_shin"]:
		var source_name:=HunterCombatMoves.physical_part(name)
		var part: Dictionary=actor.physics_rig.parts[source_name]
		var local:=Transform3D.IDENTITY
		var shape: Shape3D
		if "knee" in name or "elbow" in name or "hand" in name:
			var sphere:=SphereShape3D.new()
			sphere.radius=0.033 if "hand" in name else (0.065 if "elbow" in name else 0.080)
			shape=sphere
			if "hand" in name:local.origin=part["offset"]
		else:
			var capsule:=CapsuleShape3D.new()
			capsule.radius=0.055 if "hand" in name else 0.060
			capsule.height=maxf(capsule.radius*2.0,float(part["length"])+0.05)
			shape=capsule
			local=Transform3D(Basis(Quaternion(Vector3.UP,part["axis"])),part["offset"])
		var area:=_area("Hit_"+String(name),shape,Color(1.0,0.58,0.20,0.55))
		area.set_meta("attack_part",name)
		hitboxes[name]={"area":area,"shape":shape,"bone":part["bone"],"local":local,"previous":Transform3D.IDENTITY,"sampled":false,"active":false}
	_sample_pose()
	set_debug_visible(debug_visible)
	skeleton.skeleton_updated.connect(_sample_pose)

func begin_dodge_trace() -> void:
	clear_dodge_trace()
	# Snapshot the body before the step: an attack must threaten this position
	# and miss the real moving hurtboxes for a successful dodge reward.
	for part in hurtboxes:
		var original: Area3D=hurtboxes[part]["area"]
		var area:=_area("DodgeTrace_"+String(part),original.get_child(0).shape,Color.TRANSPARENT)
		area.global_transform=original.global_transform
		area.collision_layer=DODGE_LAYER
		area.get_child(1).visible=false
		area.set_meta("hurt_actor",actor)
		area.set_meta("hurt_part",part)
		area.set_meta("dodge_trace",true)
		dodge_trace.append(area)

func clear_dodge_trace() -> void:
	for area in dodge_trace:
		area.collision_layer=0
		area.queue_free()
	dodge_trace.clear()

func _area(label: String, shape: Shape3D, color: Color) -> Area3D:
	var area:=Area3D.new()
	area.name=label
	area.collision_layer=0
	area.collision_mask=0
	area.monitoring=false
	area.monitorable=true
	add_child(area)
	area.top_level=true
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	area.add_child(collision)
	var mesh:=MeshInstance3D.new()
	if shape is CapsuleShape3D:
		var capsule:=CapsuleMesh.new()
		capsule.radius=shape.radius
		capsule.height=shape.height
		mesh.mesh=capsule
	else:
		var sphere:=SphereMesh.new()
		sphere.radius=shape.radius
		sphere.height=shape.radius*2.0
		mesh.mesh=sphere
	var material:=StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color
	mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mesh)
	return area

func set_debug_visible(value: bool) -> void:
	debug_visible=value
	for box in hurtboxes.values():box["area"].get_child(1).visible=value
	for box in hitboxes.values():box["area"].get_child(1).visible=value and box["active"]

func deactivate_attacks() -> void:
	for box in hitboxes.values():
		box["active"]=false
		box["area"].collision_layer=0
		box["area"].get_child(1).visible=false

func _sample_pose() -> void:
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree() or not is_instance_valid(fighter):return
	for box in hurtboxes.values():
		var area: Area3D=box["area"]
		if not area.is_inside_tree():return
		area.global_transform=skeleton.global_transform*skeleton.get_bone_global_pose(box["bone"])*(box["local"] as Transform3D)
		area.force_update_transform()
	var windows:=fighter.active_windows()
	for part_name in hitboxes:
		var box: Dictionary=hitboxes[part_name]
		var area: Area3D=box["area"]
		if not area.is_inside_tree():return
		var pose:=skeleton.global_transform*skeleton.get_bone_global_pose(box["bone"])*(box["local"] as Transform3D)
		area.global_transform=pose
		var enabled:=false
		for window in windows:
			if window["part"]==part_name:enabled=true
		box["active"]=enabled
		area.collision_layer=HIT_LAYER if enabled else 0
		area.get_child(1).visible=debug_visible and enabled
		if enabled:
			var previous: Transform3D=box["previous"] if box["sampled"] else pose
			for window in windows:
				if window["part"]==part_name:_sweep_contact(box,previous,pose,window)
		box["previous"]=pose
		box["sampled"]=true

func _sweep_contact(box: Dictionary, previous: Transform3D, current: Transform3D, window: Dictionary) -> void:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=box["shape"]
	query.collision_mask=HURT_LAYER|DODGE_LAYER
	query.collide_with_areas=true
	query.collide_with_bodies=false
	query.exclude=_exclusions
	query.margin=0.002
	var rotation:=previous.basis.get_rotation_quaternion().angle_to(current.basis.get_rotation_quaternion())
	var count:=clampi(int(ceil(maxf(previous.origin.distance_to(current.origin)/0.035,rotation/0.12))),1,24)
	var contacts: Dictionary={}
	var ghosts: Dictionary={}
	for index in range(count+1):
		query.transform=previous.interpolate_with(current,float(index)/count)
		for overlap in get_world_3d().direct_space_state.intersect_shape(query,48):
			var area:=overlap["collider"] as Area3D
			if area==null or not area.has_meta("hurt_actor"):continue
			var victim: HunterTarget=area.get_meta("hurt_actor")
			if victim==actor or not is_instance_valid(victim.fighter) or victim.fighter.team==fighter.team:continue
			if not fighter.accepts_hurt_part(window["part"],area.get_meta("hurt_part")):continue
			if area.has_meta("dodge_trace"):
				ghosts[victim]=query.transform.origin
				continue
			if not fighter.can_hit(victim,window["id"]):continue
			var distance:=query.transform.origin.distance_squared_to(area.global_position)
			if not contacts.has(victim) or distance<float(contacts[victim]["distance"]):
				contacts[victim]={"area":area,"distance":distance,"point":query.transform.origin.lerp(area.global_position,0.5)}
	for victim in ghosts:
		if _unobstructed(victim,window["part"],ghosts[victim]):victim.fighter.note_dodge_threat()
	for victim in contacts:
		var contact: Dictionary=contacts[victim]
		var point: Vector3=contact["point"]
		if not _unobstructed(victim,window["part"],point):continue
		var hurt_part: StringName=contact["area"].get_meta("hurt_part")
		last_contact={"attacker":actor,"victim":victim,"attack_part":window["part"],"hurt_part":hurt_part,"position":point,"move":fighter.move}
		fighter.resolve_contact(victim,window["id"],window["part"],hurt_part,point)

func _unobstructed(victim: HunterTarget, part: StringName, point: Vector3) -> bool:
	var side: String="left" if String(part).begins_with("left") else "right"
	var proximal:=StringName(side+("_upper_arm" if "hand" in part or "elbow" in part else "_thigh"))
	var bone: int=actor.physics_rig.parts[proximal]["bone"]
	var origin:=skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
	var ray:=PhysicsRayQueryParameters3D.create(origin,point,actor.environment_mask,[actor.get_rid(),victim.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
