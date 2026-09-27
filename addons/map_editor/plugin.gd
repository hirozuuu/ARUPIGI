@tool
extends EditorPlugin

const EditorPanel = preload("res://addons/map_editor/map_editor_panel.gd")
var panel: EditorPanel

func _enter_tree() -> void:
	panel = EditorPanel.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.map_saved.connect(func(path: String): EditorInterface.get_resource_filesystem().update_file(path))
	_make_visible(false)

func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.canvas.finish_stroke()
		panel.flush_text()
		panel.checkpoint()
		panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "マップ"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("TileMap", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible

func _apply_changes() -> void:
	if is_instance_valid(panel):
		panel.canvas.finish_stroke()
		panel.flush_text()

func _get_unsaved_status(for_scene: String) -> String:
	if is_instance_valid(panel):
		panel.flush_text()
	if for_scene.is_empty() and is_instance_valid(panel) and panel.document.is_dirty():
		return "マップ %s に未保存の変更があります。" % panel.document.path
	return ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.document.is_dirty():
		panel.save_current()
