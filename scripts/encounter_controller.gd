class_name EncounterController
extends RefCounted
## Distances are pixels. Feed only actual exploration movement after collision.
## Entry, battle return and new games call reset; pausing does not call reset.

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var safe_remaining: float = 0.0
var distance_remainder: float = 0.0


func _init() -> void:
	rng.randomize()


func reset(config: GameConfig) -> void:
	safe_remaining = maxf(0.0, config.safety_tiles) * maxf(1.0, config.tile_size)
	distance_remainder = 0.0


func advance(distance: float, map: MapData, config: GameConfig) -> EnemyData:
	if distance <= 0.0 or not is_finite(distance):
		return null
	if not map.encounters_enabled or map.enemies.is_empty():
		return null
	var unsafe_distance: float = maxf(0.0, distance - safe_remaining)
	safe_remaining = maxf(0.0, safe_remaining - distance)
	distance_remainder += unsafe_distance
	var tile_distance: float = maxf(1.0, config.tile_size)
	var chance: float = clampf(config.encounter_chance, 0.0, 1.0)
	while distance_remainder >= tile_distance:
		distance_remainder -= tile_distance
		if chance >= 1.0 or (chance > 0.0 and rng.randf() < chance):
			# A single frame may cross several cells, but can start only one battle.
			distance_remainder = 0.0
			return map.enemies[rng.randi_range(0, map.enemies.size() - 1)]
	return null
