@tool
class_name GameConfig
extends Resource

const MAX_LEVEL := 10

@export var tile_size: int = 48
@export var move_speed: float = 192.0
@export_range(1, 1000) var escape_experience: int = 10
# レベル1〜10の必要累計経験値と、基礎移動速度に掛ける倍率。
@export var level_experience := PackedInt32Array([0, 10, 30, 60, 100, 150, 210, 280, 360, 450])
@export var level_speed_multipliers := PackedFloat32Array([1.0, 1.15, 1.35, 1.65, 2.1, 2.8, 4.0, 6.0, 9.0, 16.0])
@export var max_hp: int = 30
@export var attack_min: int = 5
@export var attack_max: int = 8
@export var safety_tiles: float = 4.0
@export_range(0.0, 1.0) var encounter_chance: float = 0.0625
@export_range(0.05, 10.0) var escape_seconds: float = 1.3
@export var message_seconds: float = 0.65
@export var transition_seconds: float = 0.2
