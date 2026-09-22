extends SceneTree
## Exercises the real scene, physical key events, physics and map resources.

const MainScript = preload("res://scripts/main.gd")
var config: GameConfig = MainScript.CONFIG
const MAPS: Dictionary = MainScript.MAPS
const FRAME_LIMIT: int = 180
var game: Node
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_maps()
	if failures > 0:
		_finish()
		return
	var original_chance: float = config.encounter_chance
	var original_escape: float = config.escape_chance
	var original_min: int = config.attack_min
	var original_max: int = config.attack_max
	var original_message: float = config.message_seconds
	var original_transition: float = config.transition_seconds
	config.encounter_chance = 0.0
	config.transition_seconds = 0.025
	config.message_seconds = 0.04
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_check(game.state == MainScript.State.EXPLORATION and game.exploration.visible, "Main scene starts directly in visible exploration without input")
	_check(game.session.map_id == "world" and game.session.hp == config.max_hp, "Startup initializes a fresh world session")
	_check(game.session.position == MAPS.world.spawn_position("start", config.tile_size), "New game starts at resource spawn")
	_check(game.encounters.safe_remaining == config.tile_size * config.safety_tiles and game.encounters.distance_remainder == 0.0, "Startup initializes encounter safety and distance")
	await _test_movement()
	await _test_pause()
	await _test_portals()
	await _test_town_encounters()
	await _test_healing()
	await _test_battles()
	await _test_restart()
	config.encounter_chance = original_chance
	config.escape_chance = original_escape
	config.attack_min = original_min
	config.attack_max = original_max
	config.message_seconds = original_message
	config.transition_seconds = original_transition
	game.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("PASS: %d map and real-scene integration checks." % checks)
	else:
		push_error("FAIL: %d of %d integration checks failed." % [failures, checks])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _key(code: Key, pressed: bool, echo: bool = false, logical_only: bool = false) -> void:
	var event := InputEventKey.new()
	if not logical_only:
		event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(code: Key, logical_only: bool = false) -> void:
	_key(code, true, false, logical_only)
	await _frames(1)
	_key(code, false, false, logical_only)
	await _frames(1)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _wait_state(expected: int) -> void:
	for index in FRAME_LIMIT:
		if game.state == expected:
			return
		await _frames(1)
	_check(false, "Timed out waiting for state %d; got %d" % [expected, game.state])


func _place(map_id: String, point: Vector2) -> void:
	game._begin_transition(map_id, point)
	await _wait_state(MainScript.State.EXPLORATION)
	await _frames(2)


func _center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * config.tile_size


func _validate_maps() -> void:
	for map_id: String in MAPS:
		var map: MapData = MAPS[map_id]
		var report := MapValidator.validate(map, MAPS)
		_check(report.errors.is_empty(), "%s shared format validation: %s" % [map_id, str(report.errors)])
		_check(report.warnings.is_empty(), "%s shared route validation: %s" % [map_id, str(report.warnings)])
		_check(map.id == map_id and map.width > 0 and map.height > 0 and map.rows.size() == map.height, "%s has matching id and height" % map_id)
		var rows_valid: bool = true
		var terrains_valid: bool = true
		for row in map.rows:
			rows_valid = rows_valid and row.length() == map.width
			for x in row.length():
				terrains_valid = terrains_valid and map.terrains.has(row.substr(x, 1))
		_check(rows_valid, "%s rows match width" % map_id)
		_check(terrains_valid, "%s tiles have terrain definitions" % map_id)
		if not rows_valid or not terrains_valid or map.spawns.is_empty():
			_check(not map.spawns.is_empty(), "%s has spawn points" % map_id)
			continue
		var visited: Dictionary = {}
		var frontier: Array[Vector2i] = [map.spawns.values()[0]]
		visited[frontier[0]] = true
		var cursor: int = 0
		while cursor < frontier.size():
			var cell: Vector2i = frontier[cursor]
			cursor += 1
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + direction
				if map.is_walkable(next) and not visited.has(next):
					visited[next] = true
					frontier.append(next)
		for spawn_id: String in map.spawns:
			var cell: Vector2i = map.spawns[spawn_id]
			_check(map.is_walkable(cell) and visited.has(cell), "%s:%s spawn is walkable and connected" % [map_id, spawn_id])
			var clear: bool = true
			for portal: Dictionary in map.portals:
				clear = clear and portal.cell != cell
			_check(clear, "%s:%s spawn is outside portal trigger cells" % [map_id, spawn_id])
		for portal: Dictionary in map.portals:
			_check(map.is_walkable(portal.cell) and visited.has(portal.cell), "%s portal is reachable" % map_id)
			var target_valid: bool = MAPS.has(portal.target_map)
			_check(target_valid, "%s portal target map exists" % map_id)
			if target_valid:
				var target: MapData = MAPS[portal.target_map]
				_check(target.spawns.has(portal.target_spawn), "%s portal target spawn exists" % map_id)
		for cell: Vector2i in map.healing_cells:
			_check(map.is_walkable(cell) and visited.has(cell), "%s healing cell is reachable" % map_id)
		_check(map.encounters_enabled == (map_id != "town"), "%s encounter permission matches specification" % map_id)
		_check(not map.encounters_enabled or not map.enemies.is_empty(), "%s enabled encounters have enemy candidates" % map_id)
		_check(not map.is_walkable(Vector2i(-1, 0)) and not map.is_walkable(Vector2i(map.width, map.height - 1)), "%s blocks cells beyond map bounds" % map_id)


func _test_movement() -> void:
	var start: Vector2 = MAPS.world.spawn_position("start", config.tile_size)
	await _place("world", start)
	_key(KEY_D, true)
	await _frames(20)
	_key(KEY_D, false)
	var horizontal: float = start.distance_to(game.session.position)
	_check(horizontal > 45.0 and horizontal < 85.0, "WASD produces continuous movement at configured speed")
	_check(not is_equal_approx(fposmod(game.session.position.x, config.tile_size), config.tile_size * 0.5), "Position is not snapped to tile centers")
	await _place("world", start)
	_key(KEY_RIGHT, true)
	_key(KEY_DOWN, true)
	await _frames(20)
	_key(KEY_RIGHT, false)
	_key(KEY_DOWN, false)
	var diagonal: float = start.distance_to(game.session.position)
	_check(absf(horizontal - diagonal) < 4.0, "Arrow-key diagonal movement has the same speed as axial WASD movement")
	_check(absf(game.session.position.x - start.x - (game.session.position.y - start.y)) < 0.1, "Diagonal input moves both axes equally")
	await _place("world", _center(Vector2i(0, 0)))
	_key(KEY_LEFT, true)
	await _frames(20)
	_check(game.session.position.x >= 8.9 and game.session.position.x < 10.0, "Circle collision stops the player at the outside boundary")
	var blocked_position: Vector2 = game.session.position
	var blocked_safety: float = game.encounters.safe_remaining
	var blocked_remainder: float = game.encounters.distance_remainder
	await _frames(20)
	_key(KEY_LEFT, false)
	_check(game.session.position.distance_to(blocked_position) < 0.001, "Holding input into a wall does not move the player")
	_check(is_equal_approx(game.encounters.safe_remaining, blocked_safety) and is_equal_approx(game.encounters.distance_remainder, blocked_remainder), "Holding into a wall accumulates no encounter distance")
	_check(game.exploration.camera.get_screen_center_position().distance_to(game.exploration.player.global_position) < 0.1, "Camera remains centered at map edge")
	# Town's top wall lets us verify diagonal sliding as well as obstacle blocking.
	await _place("town", _center(Vector2i(7, 1)))
	var wall_start: Vector2 = game.session.position
	_key(KEY_UP, true)
	_key(KEY_RIGHT, true)
	await _frames(25)
	_key(KEY_UP, false)
	_key(KEY_RIGHT, false)
	_check(game.session.position.y >= config.tile_size + 8.9 and game.session.position.x > wall_start.x + 25.0, "Diagonal contact slides along an interior wall without penetration")


func _test_pause() -> void:
	await _place("world", MAPS.world.spawn_position("start", config.tile_size))
	game.encounters.safe_remaining = 19.0
	game.encounters.distance_remainder = 11.0
	await _tap(KEY_ESCAPE, true)
	_check(game.state == MainScript.State.MENU, "Logical-only Esc opens exploration menu")
	var position_before: Vector2 = game.session.position
	var animation_before: float = game.exploration.player.walk_time
	_key(KEY_D, true)
	await _frames(10)
	_key(KEY_D, false)
	_check(game.session.position == position_before and game.exploration.player.walk_time == animation_before, "Menu pauses movement and walking animation")
	_check(game.encounters.safe_remaining == 19.0 and game.encounters.distance_remainder == 11.0, "Menu preserves safe distance and partial encounter distance")
	await _tap(KEY_ESCAPE)
	_check(game.state == MainScript.State.EXPLORATION and game.encounters.safe_remaining == 19.0 and game.encounters.distance_remainder == 11.0, "Closing menu resumes without resetting encounter state")
	game.session.damage(3)
	var hp_before: int = game.session.hp
	for direction in [KEY_DOWN, KEY_UP, KEY_S, KEY_W]:
		await _tap(KEY_ESCAPE)
		await _tap(direction)
		await _tap(KEY_ENTER, true)
		_check(game.state == MainScript.State.EXPLORATION and game.exploration.visible, "Menu direction input followed by logical Enter resumes exploration")
		_check(game.session.hp == hp_before and game.session.position == position_before and game.encounters.safe_remaining == 19.0 and game.encounters.distance_remainder == 11.0, "Menu confirmation preserves HP, position and encounter progress")


func _cross_portal(map_id: String, portal_index: int) -> void:
	var map: MapData = MAPS[map_id]
	var portal: Dictionary = map.portals[portal_index]
	var offset := Vector2i.DOWN
	for candidate in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		if map.is_walkable(portal.cell + candidate):
			offset = candidate
			break
	var start: Vector2 = _center(portal.cell) + Vector2(offset) * (config.tile_size * 0.5 + 1.0)
	await _place(map_id, start)
	config.encounter_chance = 1.0
	game.encounters.safe_remaining = 0.0
	game.encounters.distance_remainder = config.tile_size - 1.0
	var key: Key = {Vector2i.DOWN: KEY_UP, Vector2i.UP: KEY_DOWN, Vector2i.LEFT: KEY_RIGHT, Vector2i.RIGHT: KEY_LEFT}[offset]
	_key(key, true)
	await _frames(1)
	_key(key, false)
	_check(game.state == MainScript.State.TRANSITION, "%s portal takes priority over a guaranteed encounter" % map_id)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	_check(game.state == MainScript.State.TRANSITION, "Transition blocks menu input")
	await _wait_state(MainScript.State.EXPLORATION)
	config.encounter_chance = 0.0
	var expected: Vector2 = MAPS[portal.target_map].spawn_position(portal.target_spawn, config.tile_size)
	_check(game.session.map_id == portal.target_map and game.session.position == expected, "%s portal uses target resource spawn" % map_id)
	_check(game.encounters.safe_remaining == config.tile_size * config.safety_tiles and game.encounters.distance_remainder == 0.0, "Map teleport resets encounter distance instead of accumulating teleport length")
	await _frames(6)
	_check(game.state == MainScript.State.EXPLORATION and game.session.position == expected, "Destination does not immediately retrigger a portal")


func _test_portals() -> void:
	await _cross_portal("world", 0)
	await _cross_portal("town", 0)
	await _cross_portal("world", 1)
	await _cross_portal("dungeon", 0)


func _test_healing() -> void:
	var cell: Vector2i = MAPS.town.healing_cells[0]
	await _place("town", _center(cell + Vector2i.DOWN))
	game.session.damage(10)
	game.exploration.player.position = _center(cell)
	await _frames(1)
	_check(game.session.hp == game.session.max_hp and not game.ui.notice.is_empty(), "Entering the town healing cell restores HP and displays a notice")
	game.session.damage(1)
	var notice_time: float = game.notice_remaining
	await _frames(8)
	_check(game.session.hp == game.session.max_hp - 1 and game.notice_remaining < notice_time, "Standing on healing cell does not repeatedly heal or restart notice")
	game.exploration.player.position = _center(cell + Vector2i.DOWN)
	await _frames(1)
	game.exploration.player.position = _center(cell)
	await _frames(1)
	_check(game.session.hp == game.session.max_hp, "Leaving and reentering healing cell allows another heal")


func _test_town_encounters() -> void:
	await _place("town", MAPS.town.spawn_position("recovery", config.tile_size))
	config.encounter_chance = 1.0
	game.encounters.safe_remaining = 0.0
	game.encounters.distance_remainder = config.tile_size - 1.0
	var start: Vector2 = game.session.position
	_key(KEY_D, true)
	await _frames(20)
	_key(KEY_D, false)
	_check(game.session.position.distance_to(start) > config.tile_size and game.state == MainScript.State.EXPLORATION, "Actual town movement never encounters even with guaranteed probability")
	_check(game.encounters.safe_remaining == 0.0 and game.encounters.distance_remainder == config.tile_size - 1.0, "Town movement leaves encounter accumulators unchanged")
	config.encounter_chance = 0.0


func _wait_messages() -> void:
	for index in FRAME_LIMIT:
		if game.ui.battle_phase != "busy":
			return
		await _frames(1)
	_check(false, "Timed out waiting for battle messages")


func _test_battles() -> void:
	await _place("world", MAPS.world.spawn_position("start", config.tile_size))
	game.session.damage(5)
	config.encounter_chance = 1.0
	game.encounters.safe_remaining = 0.0
	game.encounters.distance_remainder = config.tile_size - 1.0
	_key(KEY_D, true)
	await _frames(1)
	_key(KEY_D, false)
	_check(game.state == MainScript.State.BATTLE, "Actual world movement starts a random encounter")
	config.encounter_chance = 0.0
	var return_position: Vector2 = game.session.position
	var return_hp: int = game.session.hp
	await _tap(KEY_ESCAPE)
	_check(game.state == MainScript.State.BATTLE, "Esc cannot open a menu or end battle")
	config.attack_min = 100
	config.attack_max = 100
	_key(KEY_ENTER, true)
	await _frames(1)
	_check(game.ui.battle_phase == "busy" and game.battle.outcome == BattleModel.Outcome.VICTORY, "Attack begins message sequencing and resolves victory")
	_key(KEY_ENTER, true, true)
	await _frames(1)
	_check(game.session.hp == return_hp and game.state == MainScript.State.BATTLE, "Repeat Enter during action cannot duplicate action or skip battle")
	await _wait_messages()
	await _frames(3)
	_check(game.ui.battle_phase == "result" and game.state == MainScript.State.BATTLE, "Held Enter does not consume final battle result")
	_key(KEY_ENTER, false)
	await _tap(KEY_ENTER)
	_check(game.state == MainScript.State.EXPLORATION and game.session.map_id == "world" and game.session.position == return_position and game.session.hp == return_hp, "Victory restores exact battle position and carries HP")
	_check(game.encounters.safe_remaining == config.tile_size * config.safety_tiles and game.encounters.distance_remainder == 0.0, "Victory resets encounter safety")
	# Hold Enter across a newly started battle; it must require a release first.
	_key(KEY_ENTER, true)
	game.begin_battle(MAPS.world.enemies[0])
	await _frames(2)
	_key(KEY_ENTER, true, true)
	_check(game.ui.battle_phase == "command" and game.battle.enemy_hp == game.battle.enemy.max_hp, "Enter held across battle entry does not choose a command")
	_key(KEY_ENTER, false)
	config.escape_chance = 0.0
	await _tap(KEY_DOWN)
	var hp_before: int = game.session.hp
	await _tap(KEY_ENTER)
	await _wait_messages()
	_check(game.ui.battle_phase == "command" and game.battle.outcome == BattleModel.Outcome.ONGOING and game.session.hp < hp_before, "Failed escape retaliates and returns to command selection")
	config.escape_chance = 1.0
	await _frames(1)
	await _tap(KEY_ENTER)
	await _wait_messages()
	var escape_hp: int = game.session.hp
	await _frames(1)
	await _tap(KEY_ENTER)
	_check(game.state == MainScript.State.EXPLORATION and game.session.position == return_position and game.session.hp == escape_hp, "Successful escape restores exact position with remaining HP")
	await _place("dungeon", MAPS.dungeon.spawn_position("entry", config.tile_size))
	game.session.hp = 1
	config.encounter_chance = 1.0
	game.encounters.safe_remaining = 0.0
	game.encounters.distance_remainder = config.tile_size - 1.0
	_key(KEY_D, true)
	await _frames(1)
	_key(KEY_D, false)
	_check(game.state == MainScript.State.BATTLE, "Actual dungeon movement starts a random encounter")
	config.encounter_chance = 0.0
	config.attack_min = 1
	config.attack_max = 1
	await _frames(1)
	await _tap(KEY_ENTER)
	await _wait_messages()
	_check(game.battle.outcome == BattleModel.Outcome.DEFEAT and game.session.hp == 0 and game.ui.battle_phase == "result", "Lethal retaliation waits on defeat result with zero HP")
	await _frames(1)
	await _tap(KEY_ENTER)
	await _wait_state(MainScript.State.EXPLORATION)
	_check(game.session.map_id == "town" and game.session.position == MAPS.town.spawn_position("recovery", config.tile_size) and game.session.hp == config.max_hp, "Defeat returns to safe town recovery spawn at full HP")


func _test_restart() -> void:
	game.session.damage(8)
	game.encounters.safe_remaining = 0.0
	game.encounters.distance_remainder = 11.0
	game.queue_free()
	await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_check(game.state == MainScript.State.EXPLORATION and game.exploration.visible, "Recreating the main scene immediately starts exploration")
	_check(game.session.map_id == "world" and game.session.position == MAPS.world.spawn_position("start", config.tile_size) and game.session.hp == config.max_hp, "Restart resets HP and map position")
	_check(game.encounters.safe_remaining == config.tile_size * config.safety_tiles and game.encounters.distance_remainder == 0.0, "Restart clears encounter remainder and restores safety")
