extends SceneTree
## Run with --editor; exercise the installed plugin and its lifecycle hooks.
const EditorPanel = preload("res://addons/map_editor/map_editor_panel.gd")
const PluginScript = preload("res://addons/map_editor/plugin.gd")
const Document = preload("res://addons/map_editor/map_edit_document.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _find_plugin(node: Node) -> Node:
	if node.get_script() == PluginScript:
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _run() -> void:
	for frame in 20:
		await process_frame
	var plugin := _find_plugin(root)
	check(plugin != null, "Plugin registered in the actual Godot editor")
	if plugin == null:
		quit(1)
		return
	var panel: EditorPanel = plugin.panel
	if panel._recovery_pending:
		push_error("Existing user recovery found; refusing to modify it during tests.")
		quit(1)
		return
	panel.recovery_map_path = "res://build/map-editor-tests/plugin-recovery.tres"
	panel.recovery_info_path = "res://build/map-editor-tests/plugin-recovery.cfg"
	panel.clear_recovery()
	var path := "res://build/map-editor-tests/plugin-map.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(ResourceSaver.save(Document.copy_map(load(EditorPanel.MAP_PATHS[0])), path) == OK, "Create isolated editor fixture")
	check(panel._open_now(path), "Open fixture inside real editor")
	EditorInterface.set_main_screen_editor("マップ")
	for frame in 5:
		await process_frame
	check(panel.is_visible_in_tree(), "Main screen is visible")
	panel.document.begin_stroke(load("res://data/terrains/wall.tres"))
	panel.document.paint_to(Vector2i(0, 0))
	plugin._apply_changes()
	check(not plugin._get_unsaved_status("").is_empty(), "Editor exit hook reports unsaved map")
	check(plugin._get_unsaved_status("res://scenes/main.tscn").is_empty(), "Map does not mark unrelated scene dirty")
	plugin._save_external_data()
	check(not panel.document.is_dirty(), "Editor save hook saves map")
	panel.document.undo()
	check(panel.document.is_dirty(), "Undo remains available after editor save")
	# Disable/enable through EditorInterface, then restore the on-disk checkpoint.
	EditorInterface.set_plugin_enabled("map_editor", false)
	await process_frame
	check(FileAccess.file_exists("res://build/map-editor-tests/plugin-recovery.cfg"), "Disable preserves unsaved recovery")
	EditorInterface.set_plugin_enabled("map_editor", true)
	await process_frame
	plugin = _find_plugin(root)
	check(plugin != null, "Plugin can be enabled again")
	if plugin != null:
		panel = plugin.panel
		panel.recovery_map_path = "res://build/map-editor-tests/plugin-recovery.tres"
		panel.recovery_info_path = "res://build/map-editor-tests/plugin-recovery.cfg"
		panel._restore_recovery()
		check(panel.document.is_dirty() and panel.document.data.rows[0][0] == ".", "Reenabled editor restores unsaved content")
		panel.document.open(path)
		panel.clear_recovery()
	for frame in 5:
		await process_frame
	print("%s: %d actual editor plugin checks (%d failures)." % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
