extends SceneTree
## Render with the real Compatibility renderer and save reviewable screenshots.
## Run without --headless. No runtime test hooks are shipped in the game.

var output_dir: String = "res://build/screenshots"

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output_dir = OS.get_cmdline_user_args()[0]
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _capture("world_before")
	game._set_state(game.State.MENU)
	await _capture("menu")
	game._set_state(game.State.EXPLORATION)
	game.begin_battle(game.MAPS.world.enemies[0])
	assert(game.ui.selected == GameUI.BattleCommand.ESCAPE)
	await _capture("world_battle")
	var start: Vector2 = game.exploration.player.position
	var arena: BattleArena = game.exploration.arena
	game.exploration.player.position = Vector2(arena.world_rect.get_center().x, arena.world_rect.position.y + 65.0)
	await _capture("battle_above_enemy")
	game.exploration.player.position = start
	_key(KEY_W, true)
	await _frames(12)
	_key(KEY_W, true, true)
	await _frames(4)
	_key(KEY_W, false)
	assert(game.ui.selected == GameUI.BattleCommand.ATTACK and game.exploration.player.position.y < start.y - 20.0)
	await _capture("battle_move")
	game._run_action()
	await _capture("battle_action")
	game.battle.enemy_hp = 1
	var victory_messages: Array[String] = game.battle.attack(game.session, game.CONFIG)
	game.ui.battle_phase = "result"
	game.ui.battle_text = victory_messages[-1]
	game.exploration.arena.set_enemy_active(false)
	game._refresh_ui()
	await _capture("victory_result")
	game._finish_battle()
	game.begin_battle(game.MAPS.world.enemies[0])
	game.ui.selected = GameUI.BattleCommand.ESCAPE
	game._run_action()
	game.exploration.player.position.x = arena.world_rect.end.x - 10.0
	game._refresh_ui()
	await _capture("escape_open")
	_key(KEY_D, true)
	await _frames(16)
	_key(KEY_D, false)
	assert(game.battle.outcome == BattleModel.Outcome.ESCAPED and game.ui.battle_phase == "result")
	game._refresh_ui()
	await _capture("escape_result")
	assert(game.session.level == 2 and game.ui.battle_text.contains("レベル 2"))
	root.size = Vector2i(720, 480)
	await _capture("small_level_up")
	root.size = Vector2i(1200, 700)
	await _capture("wide_level_up")
	root.size = Vector2i(720, 900)
	await _capture("tall_level_up")
	root.size = Vector2i(960, 640)
	game._finish_battle()
	game.begin_battle(game.MAPS.world.enemies[0])
	game.ui.selected = GameUI.BattleCommand.ESCAPE
	game._run_action()
	game.exploration.player.position.x = arena.world_rect.end.x + 40.0
	await _frames(2)
	assert(game.session.level == 2 and game.session.experience == 20 and not game.ui.battle_text.contains("アップ"))
	await _capture("escape_no_level_up")
	game._finish_battle()
	game.begin_battle(game.MAPS.world.enemies[0])
	game.exploration.player.position = arena.world_rect.get_center() + Vector2(0.0, 100.0)
	game.ui.selected = GameUI.BattleCommand.ESCAPE
	game._run_action()
	game.escape_remaining = 0.01
	await _frames(2)
	assert(game.ui.battle_phase == "command" and game.ui.battle_boundary_visible)
	await _capture("escape_timeout")
	game.session.hp = 0
	game.battle.outcome = BattleModel.Outcome.DEFEAT
	game.ui.battle_phase = "result"
	game.ui.battle_text = "ちからつきて しまった……\n町で ひとやすみしよう。"
	game._refresh_ui()
	await _capture("defeat_result")
	game._finish_battle()
	await create_timer(0.6).timeout
	await _capture("town")
	game.exploration.player.position = game.MAPS.town.spawn_position("entry", game.CONFIG.tile_size)
	game.session.position = game.exploration.player.position
	game.exploration.player.facing = Vector2.LEFT
	game._begin_dialogue(game.exploration.npcs[0])
	game._refresh_ui()
	await _capture("town_dialogue_choices")
	root.size = Vector2i(720, 480)
	await _capture("small_dialogue")
	root.size = Vector2i(1200, 700)
	await _capture("wide_dialogue")
	root.size = Vector2i(720, 900)
	await _capture("tall_dialogue")
	root.size = Vector2i(960, 640)
	game.dialogue.select(1)
	game.dialogue.confirm()
	game.ui.dialogue_view.queue_redraw()
	await _capture("town_dialogue_reply")
	game._set_state(game.State.EXPLORATION)
	game._refresh_ui()
	game.exploration.enter(game.MAPS.world, game.MAPS.world.spawn_position("start", game.CONFIG.tile_size), game.CONFIG)
	game.session.map_id = "world"
	game.session.position = game.exploration.player.position
	game._begin_dialogue(game.exploration.npcs[0])
	game._refresh_ui()
	await _capture("world_dialogue_first")
	game.dialogue.confirm()
	game.ui.dialogue_view.queue_redraw()
	await _capture("world_dialogue_middle")
	game.dialogue.confirm()
	game.ui.dialogue_view.queue_redraw()
	await _capture("world_dialogue_last")
	game._set_state(game.State.EXPLORATION)
	game._refresh_ui()
	game._begin_transition("forest", game.MAPS.forest.spawn_position("entry", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	game.ui.notice = ""
	await _capture("forest")
	var forest_spring: Vector2i = game.MAPS.forest.healing_cells[0]
	game.exploration.player.position = (Vector2(forest_spring) + Vector2(0.5, 0.5)) * game.CONFIG.tile_size
	game.session.position = game.exploration.player.position
	await _frames(2)
	await _capture("forest_spring")
	game._begin_transition("world", game.MAPS.world.spawn_position("from_forest", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	game.ui.notice = ""
	await _capture("world_forest_entrance")
	game._begin_transition("dungeon", game.MAPS.dungeon.spawn_position("entry", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	await _capture("dungeon_before")
	game.begin_battle(game.MAPS.dungeon.enemies[0])
	await _capture("dungeon_battle")
	root.size = Vector2i(720, 480)
	await _capture("small_battle")
	root.size = Vector2i(1200, 700)
	await _capture("wide_battle")
	root.size = Vector2i(720, 900)
	await _capture("tall_battle")
	root.size = Vector2i(960, 640)
	game.battle.outcome = BattleModel.Outcome.VICTORY
	game._finish_battle()
	game.session.gain_experience(430, game.CONFIG)
	await _capture("level_max_field")
	game._set_state(game.State.MENU)
	await _capture("level_max_menu")
	game._set_state(game.State.EXPLORATION)
	game.begin_battle(game.MAPS.dungeon.enemies[0])
	game.ui.selected = GameUI.BattleCommand.ESCAPE
	game._run_action()
	game.exploration.player.position.x = arena.world_rect.end.x + 40.0
	await _frames(2)
	assert(game.session.level == 10 and game.session.experience == 460)
	await _capture("level_max_escape")
	game.queue_free()
	await process_frame
	print("PASS: 35 Compatibility renderer screenshots and held-key battle input saved under %s." % output_dir)
	quit()

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := root.get_texture().get_image().save_png(output_dir.path_join("%s.png" % label))
	assert(error == OK)
