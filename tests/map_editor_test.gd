extends SceneTree

const Document = preload("res://addons/map_editor/map_edit_document.gd")
const EditorPanel = preload("res://addons/map_editor/map_editor_panel.gd")
const Validator = preload("res://scripts/data/map_validator.gd")
const Canvas = preload("res://addons/map_editor/map_canvas.gd")
const TEST_DIR := "res://build/map-editor-tests"
const MAPS := {
	"world": preload("res://data/maps/world.tres"),
	"town": preload("res://data/maps/town.tres"),
	"dungeon": preload("res://data/maps/dungeon.tres"),
}
var checks: int = 0
var failures: int = 0
var plain: TerrainData = preload("res://data/terrains/plain.tres")
var wall: TerrainData = preload("res://data/terrains/wall.tres")

class FailingDocument extends Document:
	func _replace_file(_from: String, _to: String) -> Error:
		return ERR_FILE_NO_PERMISSION

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func paint(doc: Document, terrain: TerrainData, cells: Array[Vector2i]) -> void:
	check(doc.begin_stroke(terrain), "Stroke starts: " + doc.last_error)
	for cell in cells:
		doc.paint_to(cell)
	doc.end_stroke()

func fixture(name: String, map: MapData = MAPS.world) -> String:
	var path := TEST_DIR.path_join(name + ".tres")
	check(ResourceSaver.save(Document.copy_map(map), path) == OK, "Write isolated fixture " + name)
	return path

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_test_editing()
	_test_keys()
	_test_validation()
	_test_saving()
	await _test_panel()
	print("%s: %d map editor checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)

func _test_editing() -> void:
	var doc := Document.new()
	check(doc.open(fixture("editing")), "Open fixture")
	var shared := load(doc.path) as MapData
	var original := Document.map_values(shared)
	var initial_version := doc.history.get_version()
	paint(doc, wall, [Vector2i(0, 0), Vector2i(8, 0), Vector2i(3, 0)])
	var key := doc.key_for(wall)
	check(doc.data.rows[0].substr(0, 9) == key.repeat(9), "Fast drag interpolates every cell and revisit is stable")
	check(doc.data.rows[0].substr(9) == shared.rows[0].substr(9) and doc.data.rows[1] == shared.rows[1], "Only intended cells changed")
	check(Document.map_values(shared) == original, "Editing does not mutate cached source")
	check(doc.data.enemies[0] == shared.enemies[0], "External enemy references stay shared")
	check(doc.is_dirty() and doc.history.get_version() == initial_version + 1, "One stroke produces exactly one undo action")
	doc.undo()
	check(Document.map_values(doc.data) == original and not doc.is_dirty(), "Undo restores rows and newly added terrain mapping")
	doc.redo()
	check(doc.data.rows[0].substr(0, 9) == key.repeat(9) and doc.is_dirty(), "Redo restores mapping and cells")
	var version := doc.history.get_version()
	paint(doc, wall, [Vector2i(0, 0), Vector2i(8, 0), Vector2i(-3, 0), Vector2i(100, 100)])
	check(doc.history.get_version() == version, "Same terrain and out-of-bounds do not add history")
	paint(doc, plain, [Vector2i(2, 0)])
	check(doc.data.rows[0][2] == doc.key_for(plain), "Erase restores valid base terrain")
	check(doc.begin_stroke(wall), "Start interrupted stroke")
	doc.paint_to(Vector2i(2, 0))
	doc.end_stroke()
	doc.undo()
	check(doc.data.rows[0][2] == doc.key_for(plain), "Focus-loss finalization is one reversible operation")
	check(doc.open(fixture("other", MAPS.town)), "Switch map")
	check(not doc.history.has_undo() and not doc.history.has_redo() and not doc.is_dirty(), "Switch clears history and dirty state")
	doc.history.clear_history()

func _test_keys() -> void:
	var doc := Document.new()
	# Keep key allocation independent of edits to the shipped world map.
	var key_map := Document.copy_map(MAPS.world)
	key_map.terrains = {".": plain, "a": wall}
	key_map.rows.fill(".".repeat(key_map.width))
	doc.open(fixture("keys", key_map))
	var terrain := TerrainData.new()
	terrain.id = "new-terrain"
	terrain.texture = plain.texture
	check(doc.key_for(terrain) == "b", "New terrain uses deterministic first unused alphanumeric key")
	paint(doc, terrain, [Vector2i(0, 0)])
	check(doc.key_for(terrain) == "b", "Existing mapping is reused")
	doc.data.terrains["z"] = terrain
	doc.data.rows[0] = "z" + doc.data.rows[0].substr(1)
	var version := doc.history.get_version()
	paint(doc, terrain, [Vector2i(0, 0)])
	check(doc.history.get_version() == version and doc.data.rows[0][0] == "z", "Equivalent terrain with alternate key remains a no-op")
	var alias := TerrainData.new()
	alias.id = plain.id
	alias.texture = plain.texture
	check(not doc.begin_stroke(alias), "Reject duplicate terrain IDs")
	for key in Document.KEYS:
		doc.data.terrains[key] = plain
	var another := TerrainData.new()
	another.id = "no-key"
	another.texture = plain.texture
	var before := Document.map_values(doc.data)
	check(not doc.begin_stroke(another), "Key exhaustion prevents stroke")
	check(Document.map_values(doc.data) == before, "Key exhaustion has no partial mutation")
	doc.history.clear_history()

func _test_validation() -> void:
	for map in MAPS.values():
		var report := Validator.validate(map, MAPS)
		check(report.errors.is_empty() and report.warnings.is_empty(), "Shipped map validates: " + map.id)
	var map := Document.copy_map(MAPS.town)
	map.rows[13] = "####################"
	var report := Validator.validate(map, MAPS)
	check(report.errors.is_empty() and not report.warnings.is_empty(), "Blocked portal warns without blocking save")
	map = Document.copy_map(MAPS.town)
	map.rows[6] = "####################"
	report = Validator.validate(map, MAPS)
	check("到達できません" in "\n".join(report.warnings), "Isolated healing location detected")
	map = Document.copy_map(MAPS.world)
	map.rows[0] = "?" + map.rows[0].substr(1)
	check(not Validator.validate(map, MAPS).errors.is_empty(), "Missing used terrain blocks save")
	map = Document.copy_map(MAPS.world)
	map.terrains["too-long"] = plain
	check(not Validator.validate(map, MAPS).errors.is_empty(), "Multicharacter mapping blocks save")
	map = Document.copy_map(MAPS.world)
	map.rows.resize(1)
	check(not Validator.validate(map, MAPS).errors.is_empty(), "Malformed row count detected")
	map = Document.copy_map(MAPS.world)
	map.spawns.start = Vector2i(-1, -1)
	map.portals[0].target_map = "missing"
	map.enemies.clear()
	report = Validator.validate(map, MAPS)
	check(report.warnings.size() >= 4, "Invalid base, important cell, destination, and encounters warn")
	map.spawns.start = "bad-coordinate"
	map.portals[0].erase("cell")
	check(not Validator.validate(map, MAPS).warnings.is_empty(), "Malformed metadata yields diagnostics without exceptions")

func _test_saving() -> void:
	var path := fixture("saving")
	var doc := Document.new()
	doc.open(path)
	var original := Document.map_values(doc.data)
	paint(doc, wall, [Vector2i(0, 0), Vector2i(6, 0)])
	var expected := Document.map_values(doc.data)
	check(doc.save(MAPS), "Save verified temporary resource and replace existing file: " + doc.last_error)
	check(not doc.is_dirty() and doc.history.has_undo(), "Save clears dirty state and preserves undo history")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	check(Document.map_values(loaded) == expected, "Reload preserves dimensions, metadata, terrain and enemy paths")
	for property in original:
		if property not in ["rows", "terrains"]:
			check(expected[property] == original[property], "Preserved map property: " + property)
	doc.undo()
	check(doc.is_dirty(), "Undo after save becomes dirty")
	doc.redo()
	check(not doc.is_dirty(), "Redo back to saved content becomes clean")
	paint(doc, plain, [Vector2i(2, 0)])
	check(doc.save(MAPS), "Repeated save does not conflict with own previous save")
	paint(doc, wall, [Vector2i(2, 0)])
	var edited := Document.map_values(doc.data)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("\n; external edit\n")
	file.close()
	var external_hash := FileAccess.get_sha256(path)
	check(not doc.save(MAPS), "External modification blocks overwrite")
	check(FileAccess.get_sha256(path) == external_hash and Document.map_values(doc.data) == edited and doc.is_dirty(), "Conflict preserves disk and working edits")
	doc.open(path)
	doc.data.rows[0] = "?"
	check(not doc.save(MAPS) and FileAccess.get_sha256(path) == external_hash, "Structural error blocks saving without changing disk")
	var failing := FailingDocument.new()
	failing.open(path)
	paint(failing, wall, [Vector2i(3, 0)])
	# Ensure the chosen cell differs from the saved map.
	paint(failing, plain, [Vector2i(0, 0)])
	check(not failing.save(MAPS) and failing.is_dirty() and failing.history.has_undo(), "Replacement failure retains working document and history")
	check(FileAccess.get_sha256(path) == external_hash, "Replacement failure retains original file")
	var leftovers := false
	for filename in DirAccess.get_files_at(TEST_DIR):
		leftovers = leftovers or filename.contains(".map-editor-")
	check(not leftovers, "Temporary files cleaned up")
	var warning_doc := Document.new()
	warning_doc.open(fixture("warning", MAPS.town))
	paint(warning_doc, wall, [Vector2i(10, 13)])
	check(warning_doc.save(MAPS), "Unfinished route with warning remains saveable")
	# New resource stored outside the standard palette remains game-compatible.
	var added := TerrainData.new()
	added.id = "test-extra"
	added.texture = plain.texture
	added.walkable = false
	var extra_path := TEST_DIR.path_join("extra.tres")
	check(ResourceSaver.save(added, extra_path) == OK, "Write new external terrain fixture")
	added = load(extra_path) as TerrainData
	paint(warning_doc, added, [Vector2i(1, 1)])
	check(warning_doc.save(MAPS), "Save new terrain mapping")
	loaded = ResourceLoader.load(warning_doc.path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	check(not loaded.is_walkable(Vector2i(1, 1)) and loaded.terrains[loaded.rows[1][1]].resource_path == extra_path, "Game reads new terrain and walkability with external reference intact")
	for item in [doc, failing, warning_doc]:
		item.history.clear_history()

func _test_panel() -> void:
	var panel := EditorPanel.new()
	panel.recovery_map_path = TEST_DIR.path_join("recovery.tres")
	panel.recovery_info_path = TEST_DIR.path_join("recovery.cfg")
	panel.clear_recovery()
	root.add_child(panel)
	await process_frame
	check(panel.palette.item_count == 7, "Panel scans seven existing terrain resources")
	check(panel.canvas.base_terrain.id == "plain", "World default erase base is plain")
	for map_path in EditorPanel.MAP_PATHS:
		check(panel._open_now(map_path), "Panel opens shipped map " + map_path)
		check(panel.canvas.custom_minimum_size == Vector2(panel.document.data.width, panel.document.data.height) * panel.canvas.tile_size, "Canvas follows map extent")
		await _capture(panel.document.data.id)
		if panel.document.data.id == "town":
			panel.edit_kind.select(1)
			panel.edit_kind.item_selected.emit(1)
			panel._select_npc("town_resident")
			await _capture("npc_editor")
			panel.npc_detail.dialogue_panel._start_preview(false)
			panel.npc_scroll.scroll_vertical = 1600
			await process_frame
			await _capture("dialogue_editor_preview")
			panel.npc_detail.dialogue_panel._stop_preview()
			panel.npc_scroll.scroll_vertical = 0
			panel.edit_kind.select(0)
			panel.edit_kind.item_selected.emit(0)
	check(panel.canvas.base_terrain.id == "floor", "Dungeon default erase base is floor")
	panel._open_now(fixture("panel", MAPS.town))
	await process_frame
	for zoom in [0.5, 0.75, 1.0, 1.5, 2.0]:
		panel.canvas.zoom = zoom
		panel.canvas.update_extent()
		check(panel.canvas.cell_at_local(Vector2(3.5, 4.5) * panel.canvas.tile_size * zoom) == Vector2i(3, 4), "Zoom maps displayed point to exact cell")
	panel.canvas.zoom = 1.0
	panel.canvas.update_extent()
	await _test_input(panel)
	paint(panel.document, plain, [Vector2i(0, 0)])
	check(FileAccess.file_exists(panel.recovery_info_path), "Committed edit checkpoints recovery")
	panel.request_open(EditorPanel.MAP_PATHS[0])
	check(panel.switch_dialog.visible and panel.document.data.id == "town", "Dirty map switch waits for save/discard/cancel")
	panel.switch_dialog.canceled.emit()
	panel.switch_dialog.hide()
	check(panel.document.is_dirty() and panel.document.data.id == "town", "Cancel retains edited map")
	panel._restore_recovery()
	check(panel.document.is_dirty() and panel.document.data.rows[0][0] == ".", "Recovery restores unsaved cells")
	check(panel.save_current(), "Recovered document saves")
	check(not FileAccess.file_exists(panel.recovery_info_path), "Successful save clears recovery")
	await _capture("saved")
	panel.document.history.clear_history()
	await _test_palette(panel)
	panel.queue_free()
	await process_frame

func _test_palette(panel: EditorPanel) -> void:
	panel._open_now(TEST_DIR.path_join("warning.tres"))
	check(panel.palette.item_count == 8, "Map-referenced terrain outside standard folder appears in palette")
	panel.terrain_directory = TEST_DIR.path_join("palette")
	DirAccess.make_dir_recursive_absolute(panel.terrain_directory.path_join("nested"))
	var extra := TerrainData.new()
	extra.id = "palette-extra"
	extra.texture = plain.texture
	var path := panel.terrain_directory.path_join("nested/new.tres")
	check(ResourceSaver.save(extra, path) == OK, "Create nested extra terrain")
	panel.refresh_palette()
	var index := -1
	for candidate in panel._terrains.size():
		if panel._terrains[candidate].id == "palette-extra":
			index = candidate
	check(index >= 0 and not panel.palette.is_item_disabled(index), "Refresh discovers and enables new nested terrain without code changes")
	if index >= 0:
		paint(panel.document, panel._terrains[index], [Vector2i(2, 1)])
		check(panel.save_current(), "Palette-added material can be placed and saved")
	var bad := TerrainData.new()
	bad.id = "plain"
	check(ResourceSaver.save(bad, panel.terrain_directory.path_join("invalid.tres")) == OK, "Create duplicate ID with missing texture")
	panel.refresh_palette()
	var rejected := 0
	for candidate in panel._terrains.size():
		if panel._terrains[candidate].id == "plain" and panel.palette.is_item_disabled(candidate):
			rejected += 1
	check(rejected == 2 and not panel._palette_errors.is_empty(), "Duplicate IDs and missing texture are diagnosed and disabled")
	# Keep this suite repeatable without touching any production material.
	DirAccess.remove_absolute(panel.terrain_directory.path_join("invalid.tres"))
	panel.document.history.clear_history()

func _mouse_button(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)

func _key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = true
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func _test_input(panel: EditorPanel) -> void:
	var original := panel.document.data.rows.duplicate()
	panel.canvas.brush = wall
	panel.canvas.base_terrain = plain
	panel.canvas.grab_focus()
	await process_frame
	var origin := panel.canvas.global_position
	_mouse_button(origin + Vector2(72, 72), true)
	_mouse_button(origin + Vector2(72, 72), false)
	check(panel.document.data.rows[1][1] == "#", "Actual GUI left click places terrain")
	_key(KEY_Z)
	check(panel.document.data.rows == original, "Focused Ctrl+Z undoes canvas operation")
	_key(KEY_Z, true)
	check(panel.document.data.rows[1][1] == "#", "Focused Ctrl+Shift+Z redoes canvas operation")
	_mouse_button(origin + Vector2(72, 72), true, MOUSE_BUTTON_RIGHT)
	_mouse_button(origin + Vector2(72, 72), false, MOUSE_BUTTON_RIGHT)
	check(panel.document.data.rows[1][1] == ".", "Actual GUI right click erases to selected base")
	# High speed drag through the GUI, followed by release outside the canvas.
	var version := panel.document.history.get_version()
	_mouse_button(origin + Vector2(72, 72), true)
	var motion := InputEventMouseMotion.new()
	motion.position = origin + Vector2(312, 72)
	motion.global_position = motion.position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse_button(Vector2(10, 10), false)
	check(panel.document.history.get_version() == version + 1, "Release outside viewport commits drag exactly once")
	check(panel.document.data.rows[1].substr(1, 6) == "######", "Actual fast drag interpolates intermediate cells")
	panel.document.undo()
	check(panel.document.data.rows == original, "Single undo restores full GUI drag")
	# A text input must receive its own shortcuts without changing map history.
	var entry := LineEdit.new()
	panel.add_child(entry)
	entry.text = "test"
	entry.grab_focus()
	version = panel.document.history.get_version()
	_key(KEY_Z)
	check(panel.document.history.get_version() == version, "Text field focus does not route shortcuts to map")
	entry.queue_free()
	await process_frame
	panel.canvas.grab_focus()
	_mouse_button(origin + Vector2(72, 72), true)
	root.focus_exited.emit()
	check(not panel.document._active and panel.document.history.get_version() == version + 1, "Window focus loss commits active stroke")
	panel.document.undo()
	var scroll := panel.canvas.get_parent() as ScrollContainer
	panel.canvas.zoom = 2.0
	panel.canvas.update_extent()
	await process_frame
	scroll.scroll_horizontal = 96
	scroll.scroll_vertical = 96
	await process_frame
	origin = panel.canvas.global_position
	_mouse_button(origin + Vector2(240, 240), true)
	_mouse_button(origin + Vector2(240, 240), false)
	check(panel.document.data.rows[2][2] == "#", "Scrolled 200% canvas edits the indicated cell")
	panel.document.undo()
	panel.canvas.zoom = 1.0
	panel.canvas.update_extent()
	scroll.scroll_horizontal = 0
	scroll.scroll_vertical = 0
	await process_frame
	await _capture("input")
	panel.edit_kind.select(1)
	panel.edit_kind.item_selected.emit(1)
	panel._new_npc()
	panel.canvas.zoom = 2.0
	panel.canvas.update_extent()
	await process_frame
	scroll.scroll_horizontal = 96
	scroll.scroll_vertical = 96
	await process_frame
	origin = panel.canvas.global_position
	_mouse_button(origin + Vector2(240, 240), true)
	_mouse_button(origin + Vector2(240, 240), false)
	check(panel.document.npc_at(Vector2i(2, 2)) != null, "Scrolled 200% canvas places NPC in indicated cell")
	panel.document.undo()
	check(panel.document.npc_at(Vector2i(2, 2)) == null, "GUI NPC placement is undoable")
	panel.edit_kind.select(0)
	panel.edit_kind.item_selected.emit(0)
	panel.canvas.zoom = 1.0
	panel.canvas.update_extent()
	scroll.scroll_horizontal = 0
	scroll.scroll_vertical = 0

func _capture(label: String) -> void:
	if not "--screenshots" in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := TEST_DIR.path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "Capture " + label)
