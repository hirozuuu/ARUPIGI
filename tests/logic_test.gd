extends SceneTree
## Run with Godot --headless --path . --script res://tests/logic_test.gd.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_test_session()
	_test_encounters()
	_test_battle()
	if failures == 0:
		print("PASS: %d deterministic session, encounter and battle checks." % checks)
	else:
		push_error("FAIL: %d of %d logic checks failed." % [failures, checks])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _enemy() -> EnemyData:
	var enemy := EnemyData.new()
	enemy.id = "test_enemy"
	enemy.display_name = "テストの敵"
	enemy.max_hp = 12
	enemy.attack_min = 3
	enemy.attack_max = 3
	return enemy


func _test_session() -> void:
	var config := GameConfig.new()
	var session := GameSession.new()
	session.reset(config, Vector2(120.5, 215.25))
	_check(session.hp == config.max_hp and session.max_hp == config.max_hp, "New game restores configured maximum HP")
	_check(session.map_id == "world" and session.position == Vector2(120.5, 215.25), "New game sets world and exact continuous position")
	session.damage(7)
	_check(session.hp == config.max_hp - 7, "Damage reduces HP")
	session.damage(-9)
	_check(session.hp == config.max_hp - 7, "Negative damage does not heal")
	session.map_id = "dungeon"
	session.position = Vector2(90.125, 251.5)
	session.save_battle_return()
	session.map_id = "town"
	session.position = Vector2.ZERO
	session.restore_battle_return()
	_check(session.map_id == "dungeon" and session.position == Vector2(90.125, 251.5), "Battle return preserves map and subpixel position")
	_check(session.hp == config.max_hp - 7, "Battle return preserves HP")
	session.damage(1000)
	_check(session.hp == 0, "Lethal damage clamps HP at zero")
	session.heal()
	session.heal()
	_check(session.hp == session.max_hp, "Healing cannot exceed maximum HP")
	session.reset(config, Vector2(24, 24))
	_check(session.map_id == "world" and session.battle_map_id == "world" and session.battle_position == Vector2(24, 24), "Restart clears saved return information")


func _test_encounters() -> void:
	var config := GameConfig.new()
	config.tile_size = 48
	config.safety_tiles = 4.0
	config.encounter_chance = 1.0
	var map := MapData.new()
	map.encounters_enabled = true
	map.enemies.append(_enemy())
	var encounters := EncounterController.new()
	encounters.rng.seed = 31
	encounters.reset(config)
	_check(encounters.safe_remaining == 192.0 and encounters.distance_remainder == 0.0, "Reset grants four safe tiles and clears remainder")
	_check(encounters.advance(191.5, map, config) == null, "No encounter within safety distance")
	_check(encounters.safe_remaining == 0.5, "Safety consumes actual fractional movement")
	_check(encounters.advance(24.5, map, config) == null and encounters.distance_remainder == 24.0, "Only movement beyond safety enters remainder")
	var random_state: int = encounters.rng.state
	_check(encounters.advance(0.0, map, config) == null and encounters.distance_remainder == 24.0 and encounters.rng.state == random_state, "Stopping or blocked movement consumes no distance or randomness")
	_check(encounters.advance(-5.0, map, config) == null and encounters.distance_remainder == 24.0, "Invalid negative movement is ignored")
	_check(encounters.advance(23.75, map, config) == null and encounters.distance_remainder == 47.75, "Subtile remainder persists across updates")
	_check(encounters.advance(0.25, map, config) == map.enemies[0], "Encounter is checked exactly at one full unsafe tile")
	_check(encounters.distance_remainder == 0.0, "Starting battle discards unused frame distance")
	encounters.reset(config)
	_check(encounters.safe_remaining == 192.0 and encounters.distance_remainder == 0.0, "Map entry and battle return can restore full safety with reset")
	map.encounters_enabled = false
	random_state = encounters.rng.state
	_check(encounters.advance(5000.0, map, config) == null and encounters.safe_remaining == 192.0 and encounters.distance_remainder == 0.0 and encounters.rng.state == random_state, "Disabled maps neither encounter nor accumulate movement")
	map.encounters_enabled = true
	map.enemies.clear()
	_check(encounters.advance(5000.0, map, config) == null and encounters.safe_remaining == 192.0, "Maps without enemy candidates are safe")
	map.enemies.append(_enemy())
	config.encounter_chance = 0.0
	_check(encounters.advance(192.0 + 48.0 * 7.0 + 11.5, map, config) == null and encounters.distance_remainder == 11.5, "Large moves process all tile boundaries and preserve remainder")
	# Equivalent movement partitioning must produce the same checks and RNG state.
	config.encounter_chance = 0.0625
	var large_steps := EncounterController.new()
	var small_steps := EncounterController.new()
	large_steps.rng.seed = 1209
	small_steps.rng.seed = 1209
	large_steps.reset(config)
	small_steps.reset(config)
	var large_result: EnemyData = large_steps.advance(192.0 + 48.0 * 12.0 + 5.5, map, config)
	var small_result: EnemyData
	for index in range(192 + 48 * 12):
		small_result = small_steps.advance(1.0, map, config)
		if small_result != null:
			break
	if small_result == null:
		small_result = small_steps.advance(5.5, map, config)
	_check(large_result == small_result and large_steps.rng.state == small_steps.rng.state, "Seeded encounter results are independent of frame partition")
	_check(large_steps.distance_remainder == small_steps.distance_remainder, "Frame partition preserves equivalent remainder")
	config.encounter_chance = 1.0
	encounters.reset(config)
	_check(encounters.advance(100000.0, map, config) != null and encounters.distance_remainder == 0.0, "One update starts at most one battle even over large distance")


func _test_battle() -> void:
	var config := GameConfig.new()
	var session := GameSession.new()
	session.reset(config, Vector2.ZERO)
	var enemy := _enemy()
	var battle := BattleModel.new()
	battle.rng.seed = 101
	config.attack_min = 5
	config.attack_max = 5
	battle.setup(enemy)
	var messages: Array[String] = battle.attack(session, config)
	_check(battle.enemy_hp == 7 and session.hp == config.max_hp - 3 and battle.outcome == BattleModel.Outcome.ONGOING, "Nonlethal attack receives exactly one enemy retaliation")
	_check(messages.size() == 2, "Ongoing turn supplies player and enemy messages")
	config.attack_min = 100
	config.attack_max = 100
	var hp_before: int = session.hp
	messages = battle.attack(session, config)
	_check(battle.enemy_hp == 0 and session.hp == hp_before and battle.outcome == BattleModel.Outcome.VICTORY, "Lethal attack wins without retaliation and clamps enemy HP")
	_check(messages.size() == 2, "Victory supplies attack and result messages")
	_check(battle.attack(session, config).is_empty() and battle.escape(session, config).is_empty() and session.hp == hp_before, "Finished battle cannot execute additional commands")
	_check(enemy.max_hp == 12, "Battle damage never changes shared enemy data")
	battle.setup(enemy)
	config.escape_chance = 1.0
	messages = battle.escape(session, config)
	_check(battle.outcome == BattleModel.Outcome.ESCAPED and session.hp == hp_before and messages.size() == 1, "Successful escape preserves HP and produces final message")
	battle.setup(enemy)
	config.escape_chance = 0.0
	messages = battle.escape(session, config)
	_check(battle.outcome == BattleModel.Outcome.ONGOING and session.hp == hp_before - 3 and messages.size() == 2, "Failed escape receives exactly one retaliation")
	session.hp = 1
	messages = battle.escape(session, config)
	_check(battle.outcome == BattleModel.Outcome.DEFEAT and session.hp == 0 and messages.size() == 3, "Failed escape can cause defeat with a separate result message")
	session.heal()
	battle.setup(enemy)
	session.hp = 2
	config.attack_min = 1
	config.attack_max = 1
	messages = battle.attack(session, config)
	_check(battle.outcome == BattleModel.Outcome.DEFEAT and session.hp == 0 and battle.enemy_hp == 11 and messages.size() == 3, "Surviving enemy can defeat player after an attack")
	# Real probability and variable damage remain reproducible with an injected seed.
	config.escape_chance = 0.6
	config.attack_min = 5
	config.attack_max = 8
	var other_battle := BattleModel.new()
	var other_session := GameSession.new()
	session.reset(config, Vector2.ZERO)
	other_session.reset(config, Vector2.ZERO)
	battle.setup(enemy)
	other_battle.setup(enemy)
	battle.rng.seed = 55
	other_battle.rng.seed = 55
	_check(battle.attack(session, config) == other_battle.attack(other_session, config) and session.hp == other_session.hp and battle.enemy_hp == other_battle.enemy_hp, "Seed fixes attack damage and retaliation")
	_check(battle.escape(session, config) == other_battle.escape(other_session, config) and battle.outcome == other_battle.outcome and session.hp == other_session.hp, "Seed fixes probabilistic escape outcome")
