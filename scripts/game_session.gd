class_name GameSession
extends RefCounted
## Mutable progress for one playthrough, separate from map and enemy resources.

var max_hp: int = 30
var hp: int = 30
var level: int = 1
var experience: int = 0
var map_id: String = "world"
var position: Vector2 = Vector2.ZERO


func reset(config: GameConfig, start_position: Vector2) -> void:
	max_hp = maxi(1, config.max_hp)
	hp = max_hp
	level = 1
	experience = 0
	map_id = "world"
	position = start_position


func damage(amount: int) -> void:
	hp = clampi(hp - maxi(0, amount), 0, max_hp)


func heal() -> void:
	hp = max_hp


func gain_experience(amount: int, config: GameConfig) -> int:
	var previous_level := level
	experience += maxi(0, amount)
	while level < GameConfig.MAX_LEVEL and experience >= config.level_experience[level]:
		level += 1
	return level - previous_level


func move_speed(config: GameConfig) -> float:
	return config.move_speed * config.level_speed_multipliers[level - 1]


func next_level_experience(config: GameConfig) -> int:
	return config.level_experience[level] if level < GameConfig.MAX_LEVEL else 0
