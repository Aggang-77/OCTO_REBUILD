class_name HunterObjective
extends Node
## Octopus-side victory: keep a valid capture for capture_seconds.
signal resolved(result: StringName, score: int)
signal health_changed(current: float, maximum: float)
@export var target_id: StringName = &"female_hunter_01"
@export var faction: StringName = &"hunter"
@export var target_priority: float = 1.0
@export var capture_score: int = 1000
@export var escape_penalty: int = 300
@export var max_health: float = 100.0
@export var capture_seconds: float = 8.0
@export var continuous_capture: bool = false
@export var escape_hold_seconds: float = 1.5
var health: float = 100.0
var capture_progress: float = 0.0
var result: StringName = &""
var _escape_elapsed: float = 0.0

func reset_objective() -> void:
	health = max_health
	capture_progress = 0.0
	_escape_elapsed = 0.0
	result = &""
	health_changed.emit(health, max_health)

func tick_capture(delta: float, restrained: bool) -> void:
	if result != &"":
		return
	if restrained:
		capture_progress = minf(1.0, capture_progress + delta / maxf(capture_seconds, 0.1))
	else:
		capture_progress = 0.0 if continuous_capture else maxf(0.0, capture_progress - delta * 0.25)
	if capture_progress >= 1.0 - 0.000000001:
		capture_progress = 1.0
		_resolve(&"captured", capture_score)

func tick_escape(delta: float, in_safe_zone: bool, restrained: bool) -> void:
	if result != &"":
		return
	_escape_elapsed = _escape_elapsed + delta if in_safe_zone and not restrained else 0.0
	if _escape_elapsed >= escape_hold_seconds:
		_resolve(&"escaped", -escape_penalty)

func apply_damage(amount: float) -> void:
	if result != &"" or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		# Incapacitation still requires a capture: damage alone grants no victory.
		get_parent().incapacitate()

func _resolve(value: StringName, score: int) -> void:
	if result != &"":
		return
	result = value
	resolved.emit(value, score)

func get_snapshot() -> Dictionary:
	return {"target_id": target_id, "faction": faction, "priority": target_priority,
		"health": health, "max_health": max_health, "capture_progress": capture_progress,
		"capture_seconds": capture_seconds, "result": result, "capture_score": capture_score}
