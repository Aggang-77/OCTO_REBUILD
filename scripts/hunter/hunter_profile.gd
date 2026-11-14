class_name HunterProfile
extends Resource
## Difficulty data can be replaced per enemy without changing AI code.
@export_range(1, 3) var level: int = 1
@export var title: String = "01 / EVASION"
@export var move_speed: float = 2.0
@export var acceleration: float = 4.5
@export var turn_speed: float = 6.0
@export var perception_radius: float = 14.0
@export var reaction_time: float = 0.65
@export var preferred_distance: float = 7.0
@export var max_stamina: float = 100.0
@export var stamina_recovery: float = 13.0
@export var run_stamina_cost: float = 0.0
@export var elbow_enabled: bool = false
@export var elbow_damage: float = 24.0
@export var elbow_escape_power: float = 2.2
@export var elbow_stamina_cost: float = 18.0
@export var elbow_cooldown: float = 3.0
@export var sword_enabled: bool = false
@export var sword_range: float = 2.65
@export var sword_damage: float = 45.0
@export var sword_stamina_cost: float = 15.0
@export var sword_cooldown: float = 1.05
@export var capture_seconds: float = 8.0
