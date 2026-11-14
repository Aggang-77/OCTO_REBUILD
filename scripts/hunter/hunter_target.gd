class_name HunterTarget
extends CharacterBody3D
## Reusable autonomous target. Physics/capture/combat do not depend on demo nodes.
signal state_changed(previous: StringName, current: StringName)
signal captured(source: Node3D)
signal released(source: Node3D)
signal attack_landed(kind: StringName, source: Node3D, damage: float)
signal objective_completed(result: StringName, score: int)

@export var profile: HunterProfile
@export var safe_zone: Node3D
@export var safe_zone_radius: float = 1.6
@export var arena_bounds_enabled: bool = true
@export var arena_bounds: Rect2 = Rect2(-13.0, -10.0, 26.0, 20.0)
@export_flags_3d_physics var environment_mask: int = 1
@export var threat_memory_seconds: float = 2.5
@export_enum("1 · Lily", "2 · Rin", "3 · Aki", "0 · Lily Orange") var character_index: int = 0
@export_flags_3d_physics var physical_hitbox_layer: int = 4
@export_flags_3d_physics var physical_collision_mask: int = 1|8
## Gameplay overrides; standalone labs retain their original difficulty profiles.
@export var capture_seconds_override: float = 0.0
@export var continuous_capture: bool = false
@onready var visual: Node3D = $Visual
@onready var objective: HunterObjective = $Objective
@onready var animation: HunterAnimation = $AnimationDriver
@onready var navigation: NavigationAgent3D = $NavigationAgent3D
var state: StringName = &"idle"
var stamina: float = 100.0
var capture_source: Node3D
var incapacitated: bool = false
var debug_destination: Vector3
var perceived_threats: Array[Dictionary] = []
var _decision_left: float = 0.0
var _reaction_left: float = 0.0
var _memory_left: float = 0.0
var _elbow_cooldown: float = 0.0
var _sword_cooldown: float = 0.0
var _action_left: float = 0.0
var _action_elapsed: float = 0.0
var _action_target: Node3D
var _hit_done: bool = false
var _steering: Vector3 = Vector3.ZERO
var _capture_elapsed: float = 0.0
var _progress_anchor: Vector3
var _stuck_elapsed: float = 0.0
var _last_known_threat: Vector3
var _alerted: bool = false
var physics_rig: HunterPhysicsRig
var _fall_left: float = 0.0
var _recover_left: float = 0.0
var _recover_duration: float = 1.0
var _swing_hits: Dictionary = {}
var _lunge_left: float = 0.0
var fighter: HunterFighter

func _ready() -> void:
	add_to_group("hunter_targets")
	if profile == null:
		profile = load("res://assets/hunter/level_1.tres")
	objective.resolved.connect(_on_resolved)
	reset_target(global_position)

func set_difficulty(level: int) -> void:
	profile = load("res://assets/hunter/level_%d.tres" % clampi(level, 1, 3))
	if is_node_ready():
		reset_target(global_position)

func set_character(index: int) -> void:
	character_index = clampi(index,0,HunterAnimation.CHARACTERS.size()-1)
	if is_node_ready():
		animation.load_character(character_index)
		reset_target(global_position)

func reset_target(spawn: Vector3) -> void:
	global_position = spawn
	velocity = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	capture_source = null
	incapacitated = false
	stamina = profile.max_stamina
	objective.capture_seconds = capture_seconds_override if capture_seconds_override > 0.0 else profile.capture_seconds
	objective.continuous_capture = continuous_capture
	objective.reset_objective()
	_action_left = 0.0
	_fall_left=0.0
	_recover_left=0.0
	_swing_hits.clear()
	_decision_left = 0.0
	_memory_left = 0.0
	_reaction_left = 0.0
	_elbow_cooldown = 0.0
	_sword_cooldown = 0.0
	_capture_elapsed = 0.0
	_stuck_elapsed = 0.0
	_alerted = false
	_progress_anchor = spawn
	_steering = Vector3.ZERO
	perceived_threats.clear()
	_set_state(&"idle")
	animation.set_weapon_visible(profile.sword_enabled)
	animation.cancel_action()
	animation.play_state(&"idle", 0.0)
	if is_instance_valid(physics_rig):physics_rig.reset_pose()
	if is_instance_valid(animation.cloth):animation.cloth.reset_motion()
	if is_instance_valid(animation.hair_motion):animation.hair_motion.reset_motion()
	if is_instance_valid(fighter):fighter.reset_fighter()

func enable_fighter(mode: StringName = &"player", team: int = 0) -> HunterFighter:
	if not is_instance_valid(fighter):
		fighter=HunterFighter.new()
		fighter.name="FighterControl"
		add_child(fighter)
		fighter.setup(self)
	fighter.control=mode
	fighter.team=team
	fighter.enabled=true
	_action_left=0.0
	animation.cancel_action()
	animation.set_weapon_visible(false)
	animation.set_combat_stance(true)
	return fighter

func is_fallen() -> bool:
	return _fall_left>0.0 or _recover_left>0.0

func knock_down(impulse: Vector3 = Vector3(14,2,4), part: StringName = &"torso", apply_impulse: bool = true) -> bool:
	if is_fallen() or objective.result!=&"" or not is_instance_valid(physics_rig):return false
	_action_left=0.0
	animation.cancel_action()
	if is_instance_valid(fighter):
		fighter.interrupt()
		fighter.pressure_hits=0
		fighter.pressure_left=0.0
	_fall_left=1.45
	physics_rig.ragdoll_weight=1.0
	physics_rig.motor_scale=0.0
	physics_rig.activate_part(part,1.5)
	if apply_impulse:
		var body := physics_rig.get_part_body(part)
		if body:body.apply_central_impulse(impulse)
	_set_state(&"falling")
	animation.play_state(&"incapacitated",0.0)
	return true

func _tick_fall(delta: float) -> void:
	if _fall_left>0.0:
		_fall_left=maxf(0.0,_fall_left-delta)
		_set_state(&"knocked_out" if incapacitated and is_instance_valid(fighter) and fighter.enabled else (&"down" if _fall_left<0.5 else &"falling"))
		# A strongly held torso must not stand up through its restraint.
		if _fall_left<=0.0:
			if incapacitated and is_instance_valid(fighter) and fighter.enabled:
				_fall_left=0.2
				_set_state(&"knocked_out")
				_brake(delta)
				return
			var held_torso:=false
			for grip in physics_rig.grips.values():
				if grip["part"] in [&"pelvis",&"torso"] and grip["force"].length()>150.0:held_torso=true
			if held_torso:
				_fall_left=0.2
			else:
				_set_state(&"getting_up")
				# The get-up OneShot must fade out onto standing locomotion. Leaving
				# the base in "down" briefly replays the fallen pose at its tail.
				animation.play_state(&"getting_up", 0.0)
				_recover_duration=animation.play_action(&"get_up")
				_recover_left=_recover_duration
	else:
		_recover_left=maxf(0.0,_recover_left-delta)
		var progress := 1.0-_recover_left/_recover_duration
		physics_rig.motor_scale=smoothstep(0.0,0.55,progress)
		physics_rig.ragdoll_weight=1.0-smoothstep(0.10,0.85,progress)
		if _recover_left<=0.0:
			physics_rig.motor_scale=1.0
			physics_rig.ragdoll_weight=0.0
			animation.cancel_action()
			_set_state(&"captured" if is_instance_valid(capture_source) else &"idle")
	_brake(delta)

func try_capture(source: Node3D, strength: float = 1.0) -> bool:
	if not is_instance_valid(source) or objective.result != &"" or capture_source != null:
		return false
	# Integration calls this only after its own tentacle contact check.
	if source is HunterThreat and not source.active:
		return false
	capture_source = source
	_capture_elapsed = 0.0
	set_meta("restraint_strength", maxf(0.1, strength))
	_action_left = 0.0
	animation.cancel_action()
	_set_state(&"captured")
	captured.emit(source)
	if is_instance_valid(physics_rig) and source.has_method("get_physics_anchor"):
		var anchor: Node3D=source.get_physics_anchor()
		if is_instance_valid(anchor):
			var attached := false
			for grip in physics_rig.grips.values():
				if grip["external"]==anchor:attached=true
			if not attached:physics_rig.attach_grip(&"torso",anchor,physics_rig.get_part_position(&"torso"),1000.0*strength,65.0,400.0*strength)
	return true

func release_capture(source: Node3D = null) -> bool:
	if capture_source == null or (source != null and source != capture_source):
		return false
	var previous := capture_source
	if objective.continuous_capture:
		objective.tick_capture(0.0, false)
	if is_instance_valid(physics_rig) and is_instance_valid(previous) and previous.has_method("get_physics_anchor"):
		var anchor: Node3D=previous.get_physics_anchor()
		if is_instance_valid(anchor):physics_rig.release_grips_for(anchor)
	capture_source = null
	_capture_elapsed = 0.0
	if state != &"elbow":
		_action_left = 0.0
	_decision_left = 0.0
	if state != &"elbow":
		_set_state(&"flee" if not incapacitated else &"incapacitated")
	released.emit(previous)
	return true

func apply_damage(amount: float) -> void:
	objective.apply_damage(amount)

func incapacitate() -> void:
	incapacitated = true
	_action_left = 0.0
	animation.cancel_action()
	if is_instance_valid(fighter):fighter.interrupt()
	_set_state(&"incapacitated")

func get_target_data() -> Dictionary:
	var data := objective.get_snapshot()
	data.merge({"position": global_position, "velocity": velocity, "state": state,
		"difficulty": profile.level, "stamina": stamina, "capturable": objective.result == &"",
		"restrained": is_instance_valid(capture_source), "incapacitated": incapacitated,"fallen":is_fallen()})
	if is_instance_valid(physics_rig):
		data["physics"]=physics_rig.get_snapshot()
		data["partially_restrained"]=not physics_rig.grips.is_empty() and capture_source==null
	if is_instance_valid(fighter):
		data["combat"]={"enabled":fighter.enabled,"control":fighter.control,"team":fighter.team,"move":fighter.move,
			"reaction":fighter.last_reaction,"round_over":fighter.round_over}
	return data

func _physics_process(delta: float) -> void:
	_elbow_cooldown = maxf(0.0, _elbow_cooldown - delta)
	_sword_cooldown = maxf(0.0, _sword_cooldown - delta)
	if capture_source != null and (not is_instance_valid(capture_source) or (capture_source is HunterThreat and not capture_source.active)):
		release_capture()
	var restrained := is_instance_valid(capture_source)
	objective.tick_capture(delta, restrained)
	var safe := is_instance_valid(safe_zone) and global_position.distance_to(safe_zone.global_position) < safe_zone_radius
	objective.tick_escape(delta, safe, restrained)
	# A result listener may disable/remove this controller while the signal is
	# being emitted. Do not call move_and_slide on its now-removed physics body.
	if not is_inside_tree() or not can_process():
		return
	if is_fallen():
		_tick_fall(delta)
		return
	if objective.result != &"":
		_brake(delta)
		animation.play_state(state, 0.0)
		return
	if incapacitated:
		if is_instance_valid(fighter) and fighter.enabled and fighter.knockout_reaction_left>0.0:
			fighter.tick_knockout_reaction(delta)
			return
		_brake(delta)
		animation.play_state(&"incapacitated", 0.0)
		return
	if is_instance_valid(fighter) and fighter.enabled:
		fighter.tick(delta)
		return
	if _action_left > 0.0:
		_tick_action(delta)
		_move_action(delta)
		return
	if restrained:
		_capture_elapsed += delta
		stamina = minf(profile.max_stamina, stamina + profile.stamina_recovery * delta)
		_set_state(&"captured")
		if profile.elbow_enabled and _capture_elapsed >= profile.reaction_time + 0.35 and _elbow_cooldown <= 0.0 and stamina >= profile.elbow_stamina_cost:
			_start_action(&"elbow", capture_source)
		_brake(delta)
		animation.play_state(state, 0.0)
		return
	_decision_left -= delta
	if _decision_left <= 0.0:
		_scan_threats()
		_decision_left = 0.18
		if not perceived_threats.is_empty() or (_alerted and is_instance_valid(safe_zone)):
			_choose_destination()
	if not perceived_threats.is_empty():
		_alerted = true
		_memory_left = threat_memory_seconds
		if state == &"idle":
			_reaction_left = profile.reaction_time
			_set_state(&"alert")
	else:
		_memory_left = maxf(0.0, _memory_left - delta)
	if state == &"alert":
		_reaction_left -= delta
		if _reaction_left > 0.0:
			_brake(delta)
			animation.play_state(&"alert", 0.0)
			return
	var attack_target := _find_cut_target()
	if is_instance_valid(attack_target) and _sword_cooldown <= 0.0 and stamina >= profile.sword_stamina_cost:
		_start_action(&"slash", attack_target)
		_brake(delta)
		return
	if _memory_left <= 0.0 and not (_alerted and is_instance_valid(safe_zone)):
		_set_state(&"idle")
		stamina = minf(profile.max_stamina, stamina + profile.stamina_recovery * delta)
		_brake(delta)
		animation.play_state(&"idle", velocity.length())
		return
	_set_state(&"flee")
	_move(delta)

func _scan_threats() -> void:
	perceived_threats.clear()
	for node in get_tree().get_nodes_in_group("hunter_threats"):
		if not node.has_method("get_threat_data"):
			continue
		var data: Dictionary = node.get_threat_data(self)
		if not data.get("active", false):
			continue
		# Sense the exposed tentacle tip, not a base/pivot that may be under terrain.
		var point: Vector3 = data.get("perception_position", data.get("cut_position", data.get("position", node.global_position) + Vector3.UP * 0.5))
		if not data.has("perception_position") and data.has("cut_position"):
			# Aim at the visible upper surface of a tip resting on the floor;
			# a ray ending at its ground-level centre can hit the ground itself.
			point += up_direction * clampf(float(data.get("cut_radius", 0.2)), 0.05, 0.25)
		if point.distance_to(global_position) > profile.perception_radius:
			continue
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.35, point, environment_mask, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		data["source"] = node
		perceived_threats.append(data)
	if not perceived_threats.is_empty():
		_last_known_threat = perceived_threats[0]["position"]

func _choose_destination() -> void:
	var best_score := -INF
	var best_point := global_position
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var point := _probe_flee_path(direction, 3.0)
		if not point.is_finite():
			continue
		if arena_bounds_enabled and not arena_bounds.grow(-0.55).has_point(Vector2(point.x, point.z)):
			continue
		var danger := 0.0
		for threat in perceived_threats:
			var predicted: Vector3 = threat["position"] + threat.get("velocity", Vector3.ZERO) * 0.45
			var distance := maxf(0.3, point.distance_to(predicted) - float(threat.get("radius", 0.3)))
			danger += float(threat.get("weight", 1.0)) * 13.0 / distance
		var score := -danger + direction.dot(_steering) * 0.7
		if is_instance_valid(safe_zone):
			score -= point.distance_to(safe_zone.global_position) * 0.3
		if arena_bounds_enabled:
			var edge := minf(minf(point.x - arena_bounds.position.x, arena_bounds.end.x - point.x), minf(point.z - arena_bounds.position.y, arena_bounds.end.y - point.z))
			score += minf(edge, 2.0) * 0.2
		if score > best_score:
			best_score = score
			best_point = point
	debug_destination = best_point
	# Use the host level's baked NavigationRegion3D when available.
	var map := navigation.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_regions(map).is_empty():
		var destination := safe_zone.global_position if is_instance_valid(safe_zone) and perceived_threats.is_empty() else best_point
		navigation.target_position = destination
		if not navigation.is_navigation_finished():
			var next := navigation.get_next_path_position()
			if next.distance_to(global_position) > 0.1:
				best_point = next
	var offset := best_point - global_position
	offset.y = 0.0
	_steering = offset.normalized()

func _probe_flee_path(direction: Vector3, distance: float) -> Vector3:
	# A horizontal sweep treats every uphill floor triangle as a wall. Follow the
	# support surface in short steps instead, retaining real wall/cliff checks.
	var transform_3d := global_transform
	transform_3d.origin.y += 0.04
	var steps := maxi(1, int(ceil(distance / 0.45)))
	var step_length := distance / steps
	var floor_cosine := cos(floor_max_angle)
	var space := get_world_3d().direct_space_state
	for index in range(1, steps + 1):
		var point := global_position + direction * step_length * index
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(point.x, transform_3d.origin.y + 0.55, point.z),
			Vector3(point.x, transform_3d.origin.y - 0.85, point.z), environment_mask, [get_rid()])
		var ground := space.intersect_ray(ray)
		if ground.is_empty() or ground.normal.dot(up_direction) < floor_cosine:
			return Vector3.INF
		point.y = ground.position.y + 0.04
		if absf(point.y - transform_3d.origin.y) > step_length * tan(floor_max_angle) + 0.06:
			return Vector3.INF
		var collision := KinematicCollision3D.new()
		if test_move(transform_3d, point - transform_3d.origin, collision, safe_margin, false, 4):
			for contact in range(collision.get_collision_count()):
				if collision.get_normal(contact).dot(up_direction) < floor_cosine:
					return Vector3.INF
		transform_3d.origin = point
	return transform_3d.origin

func _find_cut_target() -> Node3D:
	if not profile.sword_enabled:
		return null
	var nearest: Node3D
	var best_distance := profile.sword_range
	for threat in perceived_threats:
		if not threat.get("is_tentacle", false) or not threat.get("severable", false):
			continue
		var offset: Vector3 = threat["position"] - global_position
		var distance := offset.length()
		var closing := (threat.get("velocity", Vector3.ZERO) as Vector3).dot(-offset.normalized())
		if distance < best_distance and (closing > 0.1 or distance < profile.sword_range * 0.8):
			nearest = threat["source"]
			best_distance = distance
	return nearest

func _move(delta: float) -> void:
	var speed := profile.move_speed
	var nearest := INF
	for threat in perceived_threats:
		nearest = minf(nearest, global_position.distance_to(threat["position"]))
	if nearest > profile.preferred_distance:
		speed *= 0.72
	if stamina < 15.0:
		speed *= 0.6
	var desired := _steering * speed
	if is_instance_valid(physics_rig):desired+=physics_rig.get_root_feedback_velocity()
	velocity.x = move_toward(velocity.x, desired.x, profile.acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, profile.acceleration * delta)
	_gravity(delta)
	move_and_slide()
	if Vector2(velocity.x, velocity.z).length() > 0.15:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(velocity.x, velocity.z), minf(1.0, profile.turn_speed * delta))
	stamina = clampf(stamina + (profile.stamina_recovery if speed < 3.0 else -profile.run_stamina_cost) * delta, 0.0, profile.max_stamina)
	_stuck_elapsed += delta
	if _stuck_elapsed > 0.8:
		if global_position.distance_to(_progress_anchor) < 0.2:
			_steering = _steering.rotated(Vector3.UP, PI * 0.5)
			_decision_left = 0.25
		_progress_anchor = global_position
		_stuck_elapsed = 0.0
	animation.play_state(&"flee", Vector2(velocity.x, velocity.z).length())

func _start_action(kind: StringName, target: Node3D) -> void:
	if is_fallen():return
	_action_target = target
	_action_elapsed = 0.0
	_hit_done = false
	_swing_hits.clear()
	_lunge_left=0.55 if kind==&"slash" and not is_instance_valid(capture_source) else 0.0
	_set_state(kind)
	_action_left = animation.play_action(kind,target)
	if kind == &"elbow":
		stamina -= profile.elbow_stamina_cost
		_elbow_cooldown = profile.elbow_cooldown
	else:
		stamina -= profile.sword_stamina_cost
		_sword_cooldown = maxf(profile.sword_cooldown, _action_left + 0.1)
	_face(target.global_position, 0.25)

func _tick_action(delta: float) -> void:
	_action_left = maxf(0.0, _action_left - delta)
	_action_elapsed += delta
	if is_instance_valid(_action_target):
		_face(_action_target.global_position, minf(1.0, delta * 12.0))
	# Damage occurs inside the animation's strike window, never on state entry.
	var hit_at := animation.action_hit_time(state)
	if state==&"elbow" and not _hit_done and _action_elapsed >= hit_at:
		_hit_done = true
		_resolve_hit()
	if _action_left <= 0.0:
		animation.finish_strike()
		_set_state(&"captured" if is_instance_valid(capture_source) else &"flee")

func _move_action(delta: float) -> void:
	if state!=&"slash" or _lunge_left<=0.0 or _action_elapsed>0.25 or not is_instance_valid(_action_target):
		_brake(delta)
		return
	var point: Vector3=_action_target.get_cut_position() if _action_target.has_method("get_cut_position") else _action_target.global_position
	var offset := point-global_position
	offset.y=0.0
	var distance := minf(_lunge_left,maxf(0.0,offset.length()-1.05))
	if distance<=0.0:
		_brake(delta)
		return
	var mobility := minf(physics_rig.get_mobility(&"pelvis"),physics_rig.get_mobility(&"right_thigh")) if is_instance_valid(physics_rig) else 1.0
	var step := minf(distance,3.0*delta*mobility)
	var desired := offset.normalized()*step/delta
	velocity.x=desired.x
	velocity.z=desired.z
	if is_instance_valid(physics_rig):velocity+=physics_rig.get_root_feedback_velocity()
	_gravity(delta)
	var before := global_position
	move_and_slide()
	_lunge_left=maxf(0.0,_lunge_left-Vector2(global_position.x-before.x,global_position.z-before.z).length())

func _on_blade_swept(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if state!=&"slash" or _action_left<=0.0 or is_fallen():return
	for source in get_tree().get_nodes_in_group("hunter_threats"):
		if not source.has_method("receive_cut") or not source.has_method("get_threat_data"):continue
		var data: Dictionary=source.get_threat_data(self)
		if not data.get("active",false) or not data.get("severable",false) or _swing_hits.has(source.get_instance_id()):continue
		var point: Vector3=source.get_cut_position() if source.has_method("get_cut_position") else data.get("cut_position",source.global_position)
		var radius: float=float(data.get("cut_radius",0.20))+0.035
		var subdivisions := clampi(int(ceil(maxf(a.distance_to(c),b.distance_to(d))/0.035)),1,24)
		for index in range(subdivisions+1):
			var weight := float(index)/subdivisions
			var base := a.lerp(c,weight)
			var tip := b.lerp(d,weight)
			var contact := Geometry3D.get_closest_point_to_segment(point,base,tip)
			if contact.distance_to(point)>radius:continue
			var ray := PhysicsRayQueryParameters3D.create(base,contact,environment_mask,[get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():continue
			var efficiency := physics_rig.get_action_efficiency(&"slash") if is_instance_valid(physics_rig) else 1.0
			_swing_hits[source.get_instance_id()]=true
			if source.receive_cut(profile.sword_damage*efficiency,self):attack_landed.emit(&"slash",source,profile.sword_damage*efficiency)
			break

func _resolve_hit() -> void:
	if not is_instance_valid(_action_target):
		return
	if state == &"elbow":
		if capture_source != _action_target:
			return
		var efficiency := physics_rig.get_action_efficiency(&"elbow") if is_instance_valid(physics_rig) else 1.0
		attack_landed.emit(&"elbow", _action_target, profile.elbow_damage*efficiency)
		if _action_target.has_method("receive_escape_impulse"):
			_action_target.receive_escape_impulse(profile.elbow_escape_power*efficiency, self)
		if profile.elbow_escape_power*efficiency >= float(get_meta("restraint_strength", 1.0)):
			release_capture(_action_target)

func _face(point: Vector3, weight: float) -> void:
	var offset := point - global_position
	if offset.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(offset.x, offset.z), weight)

func _gravity(delta: float) -> void:
	velocity.y = -0.5 if is_on_floor() else velocity.y - 20.0 * delta

func _brake(delta: float) -> void:
	var feedback := physics_rig.get_root_feedback_velocity() if is_instance_valid(physics_rig) else Vector3.ZERO
	velocity.x = move_toward(velocity.x, feedback.x, profile.acceleration * 1.8 * delta)
	velocity.z = move_toward(velocity.z, feedback.z, profile.acceleration * 1.8 * delta)
	_gravity(delta)
	move_and_slide()

func _set_state(value: StringName) -> void:
	if state == value:
		return
	var previous := state
	state = value
	state_changed.emit(previous, value)

func _on_resolved(result: StringName, score: int) -> void:
	_action_left = 0.0
	animation.cancel_action()
	_set_state(result)
	objective_completed.emit(result, score)
