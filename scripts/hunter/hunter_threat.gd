class_name HunterThreat
extends Node3D
## Attach below a future octopus/tentacle. No dependency on an octopus scene.
signal cut_received(damage: float, attacker: Node3D)
signal severed(attacker: Node3D)
signal escape_impulse(power: float, target: Node3D)
@export var threat_id: StringName = &"tentacle"
@export var active: bool = true
@export var is_tentacle: bool = true
@export var severable: bool = true
@export var health: float = 60.0
@export var radius: float = 0.35
@export var danger_weight: float = 1.0
@export var restraint_strength: float = 1.0
## World-space cut point is this node plus aim_offset, or the actual physics tip.
@export var aim_offset: Vector3 = Vector3.ZERO
@export var cut_radius: float = 0.20
var world_velocity: Vector3 = Vector3.ZERO
var _previous_position: Vector3
var _initial_health: float
@export var physics_anchor: Node3D

func get_physics_anchor() -> Node3D:
	return physics_anchor

func get_cut_position() -> Vector3:
	return physics_anchor.global_position if is_instance_valid(physics_anchor) else global_position+aim_offset

func _ready() -> void:
	add_to_group("hunter_threats")
	_previous_position = global_position
	_initial_health = health

func _physics_process(delta: float) -> void:
	if is_instance_valid(physics_anchor):physics_anchor.set_meta("hunter_severable",severable)
	world_velocity = (global_position - _previous_position) / maxf(delta, 0.001)
	_previous_position = global_position

func get_threat_data(_target: Node3D) -> Dictionary:
	return {"id": threat_id, "position": global_position, "velocity": world_velocity,
		"active": active, "is_tentacle": is_tentacle, "severable": severable,
		"radius": radius, "weight": danger_weight, "source": self,
		"cut_position":get_cut_position(),"cut_radius":cut_radius}

func receive_cut(damage: float, attacker: Node3D) -> bool:
	if not active or not severable:
		return false
	health = maxf(0.0, health - damage)
	cut_received.emit(damage, attacker)
	if health <= 0.0:
		active = false
		severed.emit(attacker)
	return true

func receive_escape_impulse(power: float, target: Node3D) -> void:
	escape_impulse.emit(power, target)

func reset_threat() -> void:
	health = _initial_health
	active = true
	world_velocity = Vector3.ZERO
	_previous_position = global_position
