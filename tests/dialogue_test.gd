extends SceneTree

const Document = preload("res://addons/map_editor/map_edit_document.gd")
const EditorPanel = preload("res://addons/map_editor/map_editor_panel.gd")
const MainScript = preload("res://scripts/main.gd")
const TEST_DIR := "res://build/map-editor-tests"
const WORLD: MapData = preload("res://data/maps/world.tres")
const TOWN: MapData = preload("res://data/maps/town.tres")
var checks := 0
var failures := 0
var font: Font = preload("res://assets/fonts/ui_font.tres")

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_test_dialogue()
	_test_pagination()
	_test_copy_and_save()
	await _test_editor()
	await _test_game()
	print("%s: %d NPC/dialogue checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _test_dialogue() -> void:
	for map in [WORLD, TOWN]:
		var report := MapValidator.validate(map, {"world": WORLD, "town": TOWN, "dungeon": load("res://data/maps/dungeon.tres")})
		check(report.errors.is_empty() and report.warnings.is_empty(), "Sample map validates: %s %s" % [map.id, str(report)])
	var data := TOWN.npcs[0].dialogue
	var before: Variant = Document.storage_value(data)
	var model := DialogueModel.new()
	check(model.start(data, font), "Branching conversation starts")
	check(model.current.id == "ask" and model.choices_visible(), "Choices appear at final page")
	model.select(1)
	check(model.choice_index == 1, "Down selects second choice")
	check(model.confirm() and model.current.id == "about_cave", "Second choice reaches cave reply")
	while model.current != null:
		model.confirm()
	check(model.current == null, "Conversation ends")
	check(model.start(data, font) and model.current.id == "ask" and model.choice_index == 0, "Replay resets branch and selection")
	model.confirm()
	check(model.current.id == "about_town", "First branch reaches town reply")
	while model.current.id == "about_town":
		model.confirm()
	check(model.current.id == "ask", "Reply rejoins question node")
	model.select(2)
	check(not model.confirm() and model.current == null, "Exit option ends loop")
	check(Document.storage_value(data) == before, "Playback never mutates Resource")
	var invalid := Document.copy_map(TOWN).npcs[0].dialogue
	invalid.nodes[1].next_node_id = "missing"
	check(not DialogueValidator.validate(invalid).errors.is_empty(), "Missing destination is rejected")
	invalid.nodes[1].next_node_id = "ask"
	invalid.nodes[0].choices[2].next_node_id = "ask"
	invalid.nodes[2].next_node_id = "ask"
	check("終了できません" in "\n".join(DialogueValidator.validate(invalid).errors), "Endless cycle is rejected")
	invalid.nodes[0].choices[2].next_node_id = ""
	check(DialogueValidator.validate(invalid).errors.is_empty(), "Cycle with exit is accepted")
	invalid.nodes[0].next_node_id = "about_town"
	check(not DialogueValidator.validate(invalid).errors.is_empty(), "Choices and normal next are mutually exclusive")
	var many := Document.copy_map(TOWN).npcs[0].dialogue
	many.nodes[0].text = "説明文を長くします。".repeat(20)
	for i in 20:
		var choice := DialogueChoiceData.new()
		choice.text = "詳しい選択肢 %d の説明を最後まで読むための文章" % i
		many.nodes[0].choices.append(choice)
	var long_model := DialogueModel.new()
	check(long_model.start(many, font) and long_model.pages.size() >= 2 and not long_model.choices_visible(), "Choices stay hidden before final text page")
	while not long_model.choices_visible():
		long_model.confirm()
	check(long_model.choice_index == 0, "First choice is initially selected")
	long_model.select(100)
	check(long_model.choice_index == long_model.current.choices.size() - 1, "Choice selection reaches final item without fixed count limit")
	var view := DialogueView.new()
	root.add_child(view)
	view.set_content(long_model, "町の住人")
	view.sync_selection()
	check(view.choice_scroll > 0, "Many choices scroll to selected item")
	var scroll_before := view.choice_scroll
	view.scroll_choices(-1)
	check(view.choice_scroll == scroll_before - 1, "Long choice list can be scrolled line by line")
	view.queue_free()

func _test_pagination() -> void:
	var text := "あいうえお、かきくけこ。\nさしすせそ。たちつてと。長い文章を続けて読めるようにします。"
	var pages := DialoguePaginator.paginate(text, font, 23, 125)
	check(pages.size() >= 3, "Long text splits into three or more pages")
	for page in pages:
		check(page.split("\n", true).size() <= 2, "Each page has at most two lines")
		for line in page.split("\n", true):
			check(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x <= 125.5, "Rendered line fits width")
	check("".join(pages).replace("\n", "") == text.replace("\n", ""), "Page splitting retains every character")
	check(DialoguePaginator.paginate("一行", font, 23, 820).size() == 1, "Short text has one page")
	check(DialoguePaginator.paginate("一行\n二行", font, 23, 820).size() == 1, "Manual newline stays in one page")
	check(DialoguePaginator.paginate("一行\n二行\n三行", font, 23, 820).size() == 2, "Third explicit line starts another page")
	check(DialoguePaginator.paginate("一行\n二行\n", font, 23, 820).size() == 1, "Trailing newline does not create an empty page")
	var continuous := "漢".repeat(100)
	var result := DialoguePaginator.paginate(continuous, font, 23, 100)
	check("".join(result).replace("\n", "") == continuous, "Unbroken Japanese string remains complete")

func _test_copy_and_save() -> void:
	var copy := Document.copy_map(TOWN)
	check(copy.npcs[0] != TOWN.npcs[0] and copy.npcs[0].dialogue != TOWN.npcs[0].dialogue, "NPC and dialogue are independently copied")
	check(copy.npcs[0].dialogue.nodes[0].choices[0] != TOWN.npcs[0].dialogue.nodes[0].choices[0], "Nested choice is independently copied")
	check(copy.npcs[0].texture == TOWN.npcs[0].texture, "External image reference is retained")
	copy.npcs[0].dialogue.nodes[0].choices[0].text = "変更"
	check(TOWN.npcs[0].dialogue.nodes[0].choices[0].text == "町について", "Copy edit does not affect source")
	var path := TEST_DIR.path_join("dialogue-saving.tres")
	check(ResourceSaver.save(Document.copy_map(TOWN), path) == OK, "Write isolated map fixture")
	var doc := Document.new()
	check(doc.open(path), "Open dialogue fixture")
	var before := doc._snapshot()
	doc.data.npcs[0].dialogue.nodes[0].choices[0].text = "町を教えて"
	doc.commit_npcs(before, "選択肢を編集")
	check(doc.is_dirty() and doc.history.has_undo(), "Nested edit is dirty and undoable")
	doc.undo()
	check(not doc.is_dirty() and doc.data.npcs[0].dialogue.nodes[0].choices[0].text == "町について", "Undo restores nested choice and clean status")
	doc.redo()
	check(doc.is_dirty(), "Redo restores nested edit")
	check(doc.save({"world": WORLD, "town": TOWN, "dungeon": load("res://data/maps/dungeon.tres")}), "Save nested dialogue: " + doc.last_error)
	check(not doc.is_dirty(), "Saved dialogue is clean")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	check(loaded.npcs[0].dialogue.nodes[0].choices[0].text == "町を教えて", "Reload preserves edited choice")
	doc.undo()
	check(doc.is_dirty(), "Undo after save is dirty")
	doc.redo()
	check(not doc.is_dirty(), "Redo to saved dialogue is clean")
	doc.history.clear_history()
	var broken := Document.copy_map(TOWN)
	broken.npcs[0].cell = Vector2i(-1, -1)
	check(not MapValidator.validate(broken).warnings.is_empty(), "Invalid placement warns")
	broken.npcs[0].display_name = " "
	check(not MapValidator.validate(broken).errors.is_empty(), "Blank display name blocks save")

func _test_editor() -> void:
	var panel := EditorPanel.new()
	panel.recovery_map_path = TEST_DIR.path_join("dialogue-recovery.tres")
	panel.recovery_info_path = TEST_DIR.path_join("dialogue-recovery.cfg")
	panel.clear_recovery()
	root.add_child(panel)
	await process_frame
	check(panel._open_now(TEST_DIR.path_join("dialogue-saving.tres")), "Open NPC editor fixture")
	panel._select_npc("town_resident")
	check(panel.npc_detail.visible and panel.npc_list.item_count == 1, "NPC detail opens from list")
	panel._duplicate_npc()
	check(panel.pending_npc != null and panel.pending_npc.dialogue != panel.document.data.npcs[0].dialogue, "Duplicate has independent conversation")
	panel._npc_cell(Vector2i(8, 11), false)
	check(panel.document.data.npcs.size() == 2 and panel.document.is_dirty(), "Canvas places duplicate NPC")
	panel.document.undo()
	check(panel.document.data.npcs.size() == 1, "NPC placement undo")
	panel.document.redo()
	check(panel.document.data.npcs.size() == 2, "NPC placement redo")
	panel._select_npc("town_resident")
	var editor = panel.npc_detail.dialogue_panel
	editor._add_node()
	check(panel.document.data.npcs[0].dialogue.nodes.size() == 4, "Editor adds dialogue node")
	editor._add_choice()
	check(editor._selected_node().choices.size() == 1, "Editor adds choice")
	var values := Document.map_values(panel.document.data)
	editor._start_preview(false)
	check(editor.preview_model.current != null, "Preview starts from copied dialogue")
	editor._preview_confirm()
	editor._stop_preview()
	check(Document.map_values(panel.document.data) == values, "Preview does not edit document")
	panel.npc_detail.name_edit.text = "編集した住人"
	panel.npc_detail.name_edit.text_changed.emit("編集した住人")
	panel.npc_detail.texture_edit.text = "res://assets/art/player.svg"
	check(panel.save_current(), "Editor saves NPC and dialogue")
	check(panel.document.data.npcs[0].texture.resource_path == "res://assets/art/player.svg" and panel.document.data.npcs[0].display_name == "編集した住人", "Save flushes simultaneous NPC name and image edits")
	panel.document.history.clear_history()
	panel.queue_free()
	await process_frame

func _game_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _game_tap(code: Key) -> void:
	_game_key(code, true)
	await physics_frame
	_game_key(code, false)
	await physics_frame

func _test_game() -> void:
	var config: GameConfig = MainScript.CONFIG
	var old_chance := config.encounter_chance
	config.encounter_chance = 0.0
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var point := TOWN.spawn_position("entry", config.tile_size)
	game.exploration.enter(TOWN, point, config)
	game.session.map_id = "town"
	game.session.position = point
	game.exploration.player.facing = Vector2.LEFT
	await physics_frame
	game._refresh_ui()
	check(game.exploration.npcs.size() == 1 and game.exploration.talk_target() != null, "Town NPC is spawned and targetable from adjacent cell")
	check(game.ui.talk_name == "町の住人", "Prompt names the same talk target")
	var before_position: Vector2 = game.session.position
	var before_distance: float = game.encounters.distance_remainder
	game.confirm_armed = true
	await _game_tap(KEY_ENTER)
	check(game.state == MainScript.State.DIALOGUE and game.dialogue.current.id == "ask", "Enter starts dialogue without skipping first page")
	_game_key(KEY_D, true)
	for i in 8:
		await physics_frame
	_game_key(KEY_D, false)
	check(game.session.position == before_position and game.encounters.distance_remainder == before_distance, "Dialogue stops movement and encounter progress")
	await _game_tap(KEY_ESCAPE)
	check(game.state == MainScript.State.DIALOGUE, "Esc does not interrupt dialogue")
	await _game_tap(KEY_DOWN)
	check(game.dialogue.choice_index == 1, "Down chooses second branch without moving player")
	await _game_tap(KEY_ENTER)
	check(game.dialogue.current.id == "about_cave", "Enter follows selected branch")
	await _game_tap(KEY_ENTER)
	check(game.state == MainScript.State.EXPLORATION and game.session.position == before_position, "Dialogue ends at same position")
	game.exploration.player.facing = Vector2.LEFT
	await _game_tap(KEY_ENTER)
	check(game.state == MainScript.State.DIALOGUE and game.dialogue.current.id == "ask" and game.dialogue.choice_index == 0, "Talking again starts fresh")
	# Finish via the explicit exit choice.
	await _game_tap(KEY_DOWN)
	await _game_tap(KEY_DOWN)
	await _game_tap(KEY_ENTER)
	check(game.state == MainScript.State.EXPLORATION, "Exit choice returns to exploration")
	game.exploration.player.position = (Vector2(TOWN.npcs[0].cell) + Vector2.ONE * 0.5) * config.tile_size
	game.session.position = game.exploration.player.position
	game.begin_battle(WORLD.enemies[0])
	game.battle.outcome = BattleModel.Outcome.VICTORY
	game._finish_battle()
	check(game.exploration.overlap_exceptions.size() == 1, "Battle ending on NPC temporarily excludes that collision")
	_game_key(KEY_D, true)
	for i in 20:
		await physics_frame
	_game_key(KEY_D, false)
	await physics_frame
	check(game.exploration.overlap_exceptions.is_empty(), "NPC collision returns after leaving overlap")
	game.exploration.enter(WORLD, WORLD.spawn_position("start", config.tile_size), config)
	check(game.exploration.npcs.size() == 1 and game.exploration.npcs[0].data.id == "field_guide", "Map switch destroys old NPC list and spawns current map NPC")
	var two := Document.copy_map(WORLD)
	var extra := Document.copy_map(WORLD).npcs[0]
	extra.id = "aaa"
	extra.cell = Vector2i(23, 17)
	two.npcs.append(extra)
	var midpoint := Vector2(23.0, 16.5) * config.tile_size
	game.exploration.enter(two, midpoint, config)
	game.exploration.player.facing = Vector2.DOWN
	await physics_frame
	check(game.exploration.talk_target() != null and game.exploration.talk_target().data.id == "aaa", "Equidistant candidates use NPC ID order")
	var blocked := Document.copy_map(WORLD)
	blocked.npcs[0].cell = Vector2i(23, 17)
	var row := blocked.rows[16]
	blocked.rows[16] = row.substr(0, 23) + "^" + row.substr(24)
	var corner := Vector2(22.75, 16.6) * config.tile_size
	game.exploration.enter(blocked, corner, config)
	game.exploration.player.facing = (game.exploration.npcs[0].position - corner).normalized()
	await physics_frame
	check(game.exploration.talk_target() == null, "Terrain corner blocks line of sight to nearby NPC")
	config.encounter_chance = old_chance
	game.queue_free()
	await process_frame
