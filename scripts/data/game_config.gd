@tool
class_name GameConfig
extends Resource

@export var tile_size: int = 48
@export var move_speed: float = 192.0
@export var max_hp: int = 30
@export var attack_min: int = 5
@export var attack_max: int = 8
@export var safety_tiles: float = 4.0
@export_range(0.0, 1.0) var encounter_chance: float = 0.0625
@export_range(0.05, 10.0) var escape_seconds: float = 1.3
@export var message_seconds: float = 0.65
@export var transition_seconds: float = 0.2
