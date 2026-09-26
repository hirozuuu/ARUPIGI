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
	await _test_arena()
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


func _test_arena() -> void:
	await _place("world", MAPS.world.spawn_position("start", config.tile_size))
	var player: Player = game.exploration.player
	var camera: Camera2D = game.exploration.camera
	var before_world := player.global_position
	var before_screen := player.get_global_transform_with_canvas().origin
	var before_size := player.get_global_transform_with_canvas().basis_xform(Vector2.RIGHT).length()
	var map_screen: Vector2 = game.exploration.map.get_global_transform_with_canvas().origin
	game.begin_battle(MAPS.world.enemies[0])
	game._refresh_ui()
	var arena: BattleArena = game.exploration.arena
	_check(game.exploration.visible and arena.active and player.global_position == before_world, "Battle retains the visible field and exact player world position")
	_check(player.get_global_transform_with_canvas().origin.distance_to(before_screen) < 0.1 and absf(player.get_global_transform_with_canvas().basis_xform(Vector2.RIGHT).length() - before_size) < 0.01, "Battle start retains player screen position and size")
	_check(game.exploration.map.get_global_transform_with_canvas().origin.distance_to(map_screen) < 0.1, "Battle start does not jump the background")
	_check(absf(arena.screen_rect().size.x - arena.screen_rect().size.y) < 0.1 and absf(arena.screen_rect().size.x - 400.0) < 0.1, "Battle frame is a 400 pixel square at the reference size")
	_check(player.collision_mask == BattleArena.BATTLE_LAYER and arena.enemy_body.collision_layer == BattleArena.BATTLE_LAYER, "Battle uses only arena and enemy collisions")
	_check((arena.enemy_body.get_child(0) as CollisionShape2D).shape.size.distance_to(arena.enemy_rect.size) < 0.01, "Enemy collision square matches its configured visible size")
	game.encounters.safe_remaining = 123.0
	game.encounters.distance_remainder = 17.0
	var fixed_camera := camera.global_position
	var fixed_map_screen: Vector2 = game.exploration.map.get_global_transform_with_canvas().origin
	_key(KEY_D, true)
	await _frames(10)
	_key(KEY_D, false)
	_check(player.position.x > before_world.x + 20.0 and game.session.position == player.position, "Battle moves continuously and records the current position")
	_check(camera.global_position.distance_to(fixed_camera) < 0.01 and game.exploration.map.get_global_transform_with_canvas().origin.distance_to(fixed_map_screen) < 0.1, "Battle camera and background stay fixed while player moves")
	var selection: int = game.ui.selected
	var up_start := player.position
	_key(KEY_W, true)
	await _frames(8)
	_key(KEY_W, true, true)
	await _frames(3)
	_key(KEY_W, false)
	_check(game.ui.selected == 1 - selection and player.position.y < up_start.y - 20.0, "One up press changes command once while held movement continues")
	_key(KEY_A, true)
	await _frames(5)
	_key(KEY_A, false)
	_check(game.ui.selected == 1 - selection, "Horizontal movement does not change the command")
	game.ui.battle_phase = "busy"
	var busy_messages: Array[String] = ["移動中のメッセージ"]
	game.messages = busy_messages
	game.message_index = 0
	game.message_remaining = 1.0
	var busy_start := player.position
	_key(KEY_S, true)
	await _frames(6)
	_key(KEY_S, false)
	_check(game.ui.battle_phase == "busy" and player.position.y > busy_start.y + 10.0 and game.ui.selected == 1 - selection, "Busy messages allow movement without command changes")
	game.ui.battle_phase = "result"
	game.battle.outcome = BattleModel.Outcome.DEFEAT
	game.session.hp = 0
	var result_start := player.position
	_key(KEY_D, true)
	await _frames(6)
	_key(KEY_D, false)
	_check(player.position.x > result_start.x + 10.0, "Defeat result allows movement even at zero HP")
	_check(game.encounters.safe_remaining == 123.0 and game.encounters.distance_remainder == 17.0, "Battle movement never consumes encounter distance or safety")
	var fixed_rect := arena.world_rect
	var position_before_resize := player.position
	root.size = Vector2i(720, 480)
	await _frames(3)
	_check(player.position == position_before_resize and arena.world_rect == fixed_rect, "Resize leaves player and arena world coordinates unchanged")
	_check(absf(arena.screen_rect().size.x - arena.screen_rect().size.y) < 0.2 and arena.screen_rect().position.y >= -0.2, "Small viewport keeps the square arena visible")
	root.size = Vector2i(1200, 700)
	await _frames(3)
	_check(absf(arena.screen_rect().size.x - arena.screen_rect().size.y) < 0.2 and player.position == position_before_resize, "Wide viewport keeps arena square without moving player")
	root.size = Vector2i(960, 640)
	await _frames(3)
	game.battle.outcome = BattleModel.Outcome.ESCAPED
	var final_position := player.position
	game._finish_battle()
	_check(game.state == MainScript.State.EXPLORATION and game.session.position == final_position and player.position == final_position, "Escape uses the position at final confirmation")
	_check(player.collision_mask == 1 and not arena.active and arena.enemy_body.collision_layer == 0 and camera.get_parent() == player, "Battle cleanup restores terrain collisions and following camera")
	root.size = Vector2i(720, 480)
	await _frames(2)
	var small_screen_start := player.get_global_transform_with_canvas().origin
	var small_size_start := player.get_global_transform_with_canvas().basis_xform(Vector2.RIGHT).length()
	game.begin_battle(MAPS.world.enemies[0])
	await _frames(1)
	_check(player.get_global_transform_with_canvas().origin.distance_to(small_screen_start) < 0.1 and absf(player.get_global_transform_with_canvas().basis_xform(Vector2.RIGHT).length() - small_size_start) < 0.01, "Battle start after resizing retains player screen position and size")
	_check(absf(arena.screen_rect().size.x - arena.screen_rect().size.y) < 0.2 and arena.world_rect.size.x > 0.0, "Battle started after resizing retains a square frame in logical canvas coordinates")
	root.size = Vector2i(960, 640)
	await _frames(2)
	_check(arena.active and arena.enemy_body.collision_layer == BattleArena.BATTLE_LAYER, "Next battle rebuilds enemy collision")
	var r := arena.world_rect
	var tests := [
		{"position": Vector2(r.position.x + 25, r.get_center().y), "key": KEY_A},
		{"position": Vector2(r.end.x - 25, r.get_center().y), "key": KEY_D},
		{"position": Vector2(r.get_center().x + 100, r.position.y + 25), "key": KEY_W},
		{"position": Vector2(r.get_center().x + 100, r.end.y - 25), "key": KEY_S},
	]
	for side in tests:
		player.position = side.position
		_key(side.key, true)
		await _frames(15)
		_key(side.key, false)
		_check(player.position.x >= r.position.x + 8.5 and player.position.x <= r.end.x - 8.5 and player.position.y >= r.position.y + 8.5 and player.position.y <= r.end.y - 8.5, "Foot circle stays inside each arena edge")
	player.position = Vector2(r.get_center().x + 100, r.position.y + 9.1)
	game.ui.selected = 0
	_key(KEY_W, true)
	await _frames(3)
	_key(KEY_W, false)
	_check(game.ui.selected == 1 and player.position.y >= r.position.y + 8.5, "Blocked upward input still selects a command")
	var enemy_tests := [
		{"position": Vector2(arena.enemy_rect.position.x - 20, arena.enemy_rect.get_center().y), "key": KEY_D},
		{"position": Vector2(arena.enemy_rect.end.x + 20, arena.enemy_rect.get_center().y), "key": KEY_A},
		{"position": Vector2(arena.enemy_rect.get_center().x, arena.enemy_rect.position.y - 20), "key": KEY_S},
		{"position": Vector2(arena.enemy_rect.get_center().x, arena.enemy_rect.end.y + 20), "key": KEY_W},
	]
	for side in enemy_tests:
		player.position = side.position
		_key(side.key, true)
		await _frames(15)
		_key(side.key, false)
		_check(player.position.x <= arena.enemy_rect.position.x - 8.5 or player.position.x >= arena.enemy_rect.end.x + 8.5 or player.position.y <= arena.enemy_rect.position.y - 8.5 or player.position.y >= arena.enemy_rect.end.y + 8.5, "Foot circle cannot enter enemy square from any side")
	player.position = Vector2(arena.enemy_rect.position.x - 20, arena.enemy_rect.end.y + 20)
	var slide_start := player.position
	_key(KEY_D, true)
	_key(KEY_W, true)
	await _frames(15)
	_key(KEY_D, false)
	_key(KEY_W, false)
	var nearest_enemy := Vector2(clampf(player.position.x, arena.enemy_rect.position.x, arena.enemy_rect.end.x), clampf(player.position.y, arena.enemy_rect.position.y, arena.enemy_rect.end.y))
	_check(player.position.distance_to(slide_start) > 15.0 and player.position.distance_to(nearest_enemy) >= 8.5, "Diagonal contact slides around the enemy corner without penetration")
	game.ui.battle_phase = "result"
	game.battle.outcome = BattleModel.Outcome.VICTORY
	arena.set_enemy_active(false)
	_check(arena.enemy_body.collision_layer == 0 and not arena.enemy_art.visible, "Victory hides the enemy and removes its collision together")
	game._finish_battle()
	await _place("dungeon", MAPS.dungeon.spawn_position("entry", config.tile_size))
	game.begin_battle(MAPS.dungeon.enemies[0])
	player.position = _center(Vector2i(0, 8))
	var wall_position := player.position
	_key(KEY_D, true)
	await _frames(8)
	_key(KEY_D, false)
	_check(not MAPS.dungeon.is_walkable(Vector2i(0, 8)) and player.position.x > wall_position.x + 10.0, "Battle movement ignores blocked terrain")
	game.battle.outcome = BattleModel.Outcome.ESCAPED
	var blocked_finish := player.position
	game._finish_battle()
	_check(game.session.position == blocked_finish and player.position == blocked_finish, "Battle finish does not correct a blocked terrain position")
	game.begin_battle(MAPS.dungeon.enemies[0])
	player.position = Vector2(-20.0, player.position.y)
	await _frames(2)
	game.battle.outcome = BattleModel.Outcome.ESCAPED
	var outside_finish := player.position
	game._finish_battle()
	_check(outside_finish.x < 0.0 and game.session.position == outside_finish, "Battle finish retains a position outside the map")
	await _place("world", MAPS.world.spawn_position("from_town", config.tile_size))
	game.begin_battle(MAPS.world.enemies[0])
	player.position = _center(Vector2i(17, 13))
	await _frames(2)
	_check(game.state == MainScript.State.BATTLE and game.session.map_id == "world", "Battle movement over a portal does not change maps")
	game.battle.outcome = BattleModel.Outcome.ESCAPED
	game._finish_battle()
	await _place("town", MAPS.town.spawn_position("recovery", config.tile_size))
	game.session.heal()
	game.session.damage(5)
	game.begin_battle(MAPS.world.enemies[0])
	player.position = _center(Vector2i(10, 5))
	await _frames(2)
	_check(game.session.hp == config.max_hp - 5, "Battle movement over the healing spring does not heal: hp=%d expected=%d" % [game.session.hp, config.max_hp - 5])
	game.battle.outcome = BattleModel.Outcome.ESCAPED
	game._finish_battle()
	game.session.heal()
	await _place("world", MAPS.world.spawn_position("start", config.tile_size))


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
	_key(KEY_D, true)
	await _frames(8)
	_key(KEY_D, false)
	var victory_position: Vector2 = game.session.position
	_check(victory_position.distance_to(return_position) > 10.0, "Victory result movement changes the final position")
	await _tap(KEY_ENTER)
	_check(game.state == MainScript.State.EXPLORATION and game.session.map_id == "world" and game.session.position == victory_position and game.session.hp == return_hp, "Victory carries the final battle position and HP")
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
	_check(game.ui.battle_phase == "command" and game.battle.outcome == BattleModel.Outcome.ONGOING and game.session.hp < hp_before, "Failed escape retaliates and returns to command selection: phase=%s outcome=%s hp=%d before=%d" % [game.ui.battle_phase, game.battle.outcome, game.session.hp, hp_before])
	config.escape_chance = 1.0
	await _frames(1)
	await _tap(KEY_ENTER)
	await _wait_messages()
	var escape_hp: int = game.session.hp
	await _frames(1)
	_key(KEY_D, true)
	await _frames(8)
	_key(KEY_D, false)
	var escape_position: Vector2 = game.session.position
	await _tap(KEY_ENTER)
	_check(game.state == MainScript.State.EXPLORATION and game.session.position == escape_position and game.session.hp == escape_hp, "Successful escape carries the final position with remaining HP: state=%s pos=%s expected=%s hp=%d expected=%d" % [game.state, game.session.position, escape_position, game.session.hp, escape_hp])
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
	_check(not game.exploration.arena.active and game.exploration.player.collision_mask == 1 and game.exploration.camera.get_parent() == game.exploration.player, "Defeat restores terrain collision and following camera")


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
