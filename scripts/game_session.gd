class_name GameSession
extends RefCounted
## Mutable progress for one playthrough, separate from map and enemy resources.

var max_hp: int = 30
var hp: int = 30
var map_id: String = "world"
var position: Vector2 = Vector2.ZERO
var battle_map_id: String = "world"
var battle_position: Vector2 = Vector2.ZERO


func reset(config: GameConfig, start_position: Vector2) -> void:
	max_hp = maxi(1, config.max_hp)
	hp = max_hp
	map_id = "world"
	position = start_position
	save_battle_return()


func damage(amount: int) -> void:
	hp = clampi(hp - maxi(0, amount), 0, max_hp)


func heal() -> void:
	hp = max_hp


func save_battle_return() -> void:
	battle_map_id = map_id
	battle_position = position


func restore_battle_return() -> void:
	map_id = battle_map_id
	position = battle_position
