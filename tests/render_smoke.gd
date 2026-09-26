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
	await _capture("world_battle")
	var start: Vector2 = game.exploration.player.position
	_key(KEY_W, true)
	await _frames(12)
	_key(KEY_W, true, true)
	await _frames(4)
	_key(KEY_W, false)
	assert(game.ui.selected == 1 and game.exploration.player.position.y < start.y - 20.0)
	await _capture("battle_move")
	game.ui.selected = 0
	game._run_action()
	await _capture("battle_action")
	game.battle.outcome = BattleModel.Outcome.VICTORY
	game.battle.enemy_hp = 0
	game.ui.battle_phase = "result"
	game.ui.battle_text = "敵を たおした！"
	game.exploration.arena.set_enemy_active(false)
	game._refresh_ui()
	await _capture("victory_result")
	game._finish_battle()
	game.begin_battle(game.MAPS.world.enemies[0])
	game.battle.outcome = BattleModel.Outcome.ESCAPED
	game.ui.battle_phase = "result"
	game.ui.battle_text = "うまく にげきれた！"
	game._refresh_ui()
	await _capture("escape_result")
	game._finish_battle()
	game.begin_battle(game.MAPS.world.enemies[0])
	game.session.hp = 0
	game.battle.outcome = BattleModel.Outcome.DEFEAT
	game.ui.battle_phase = "result"
	game.ui.battle_text = "ちからつきて しまった……\n町で ひとやすみしよう。"
	game._refresh_ui()
	await _capture("defeat_result")
	game._finish_battle()
	game._begin_transition("town", game.MAPS.town.spawn_position("recovery", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	await _capture("town")
	game._begin_transition("dungeon", game.MAPS.dungeon.spawn_position("entry", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	await _capture("dungeon_before")
	game.begin_battle(game.MAPS.dungeon.enemies[0])
	await _capture("dungeon_battle")
	root.size = Vector2i(720, 480)
	await _capture("small_battle")
	root.size = Vector2i(1200, 700)
	await _capture("wide_battle")
	game.queue_free()
	await process_frame
	print("PASS: 13 Compatibility renderer screenshots and held-key battle input saved under %s." % output_dir)
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
