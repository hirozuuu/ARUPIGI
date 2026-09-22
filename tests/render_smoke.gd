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
	await _capture("world")
	game._set_state(game.State.MENU)
	await _capture("menu")
	game._begin_transition("town", game.MAPS.town.spawn_position("recovery", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	await _capture("town")
	game._begin_transition("dungeon", game.MAPS.dungeon.spawn_position("entry", game.CONFIG.tile_size))
	await create_timer(0.6).timeout
	await _capture("dungeon")
	game.begin_battle(game.MAPS.dungeon.enemies[0])
	await _capture("battle")
	game._run_action()
	await _capture("battle_action")
	root.size = Vector2i(1200, 700)
	await _capture("resized")
	game.queue_free()
	await process_frame
	print("PASS: 7 Compatibility renderer screenshots saved under %s." % output_dir)
	quit()

func _capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := root.get_texture().get_image().save_png(output_dir.path_join("%s.png" % label))
	assert(error == OK)
