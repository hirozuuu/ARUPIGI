@tool
extends VBoxContainer

signal operation_failed(message: String)
const Document = preload("res://addons/map_editor/map_edit_document.gd")
const DialoguePanel = preload("res://addons/map_editor/dialogue_editor_panel.gd")
var document: Document
var npc_id: String = ""
var _busy := false
var _pending_before: Dictionary = {}
var _pending_description: String = ""
var _typing := Timer.new()
var name_edit := LineEdit.new()
var texture_edit := LineEdit.new()
var tint_edit := ColorPickerButton.new()
var dialogue_panel: VBoxContainer
var image_dialog := FileDialog.new()
var reset_dialogue_button := Button.new()

func _ready() -> void:
	_typing.one_shot = true
	_typing.wait_time = 0.7
	_typing.timeout.connect(flush_text)
	add_child(_typing)
	add_child(_label("NPCの名前"))
	add_child(name_edit)
	name_edit.text_changed.connect(func(value: String): _type_change("NPCの名前を編集", func(): _npc().display_name = value))
	name_edit.focus_exited.connect(flush_text)
	add_child(_label("画像のResourceパス"))
	add_child(texture_edit)
	texture_edit.text_submitted.connect(func(_value: String): _commit_texture())
	texture_edit.focus_exited.connect(_commit_texture)
	var browse := Button.new()
	browse.text = "画像を選ぶ"
	browse.pressed.connect(func(): image_dialog.popup_centered_ratio(0.6))
	add_child(browse)
	image_dialog.access = FileDialog.ACCESS_RESOURCES
	image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_dialog.filters = PackedStringArray(["*.svg, *.png, *.webp ; 画像"])
	image_dialog.file_selected.connect(func(path: String): texture_edit.text = path; _commit_texture())
	add_child(image_dialog)
	add_child(_label("服の色"))
	add_child(tint_edit)
	reset_dialogue_button.text = "欠落した会話を作成"
	reset_dialogue_button.pressed.connect(_create_dialogue)
	add_child(reset_dialogue_button)
	tint_edit.color_changed.connect(func(value: Color): _type_change("NPCの色を編集", func(): _npc().tint = value))
	tint_edit.focus_exited.connect(flush_text)
	var separator := HSeparator.new()
	add_child(separator)
	dialogue_panel = DialoguePanel.new()
	add_child(dialogue_panel)
	dialogue_panel.operation_failed.connect(func(message: String): operation_failed.emit(message))
	refresh()

func _label(value: String) -> Label:
	var result := Label.new()
	result.text = value
	return result

func set_target(value: Document, id: String) -> void:
	flush_text()
	document = value
	npc_id = id
	dialogue_panel.set_target(value, id)
	refresh()

func _npc() -> NpcData:
	if document == null or document.data == null:
		return null
	for npc in document.data.npcs:
		if npc != null and npc.id == npc_id:
			return npc
	return null

func refresh() -> void:
	if _busy or not _pending_before.is_empty():
		return
	_busy = true
	var npc := _npc()
	visible = npc != null
	if npc != null:
		name_edit.text = npc.display_name
		texture_edit.text = npc.texture.resource_path if npc.texture != null else ""
		tint_edit.color = npc.tint
		reset_dialogue_button.visible = npc.dialogue == null
	_busy = false
	if dialogue_panel != null:
		dialogue_panel.refresh()

func _type_change(description: String, action: Callable) -> void:
	if _busy or _npc() == null:
		return
	if _pending_before.is_empty():
		_pending_before = document._snapshot()
		_pending_description = description
	action.call()
	document.changed.emit()
	_typing.start()

func flush_text() -> void:
	var pending_texture_path := texture_edit.text
	if not _pending_before.is_empty():
		_typing.stop()
		var before := _pending_before
		var description := _pending_description
		_pending_before = {}
		document.commit_npcs(before, description)
	if dialogue_panel != null:
		dialogue_panel.flush_text()
	texture_edit.text = pending_texture_path
	_apply_texture_path()
	refresh()

func _commit_texture() -> void:
	flush_text()

func _apply_texture_path() -> void:
	if _busy or _npc() == null:
		return
	var path := texture_edit.text.strip_edges()
	if path == (_npc().texture.resource_path if _npc().texture != null else ""):
		return
	var resource := load(path) as Texture2D if not path.is_empty() else null
	if resource == null:
		operation_failed.emit("画像を読み込めません: " + path)
		refresh()
		return
	var before := document._snapshot()
	_npc().texture = resource
	document.commit_npcs(before, "NPCの画像を変更")
	refresh()

func _create_dialogue() -> void:
	flush_text()
	if _npc() == null or _npc().dialogue != null:
		return
	var before := document._snapshot()
	var data := DialogueData.new()
	var node := DialogueNodeData.new()
	node.id = "node_1"
	node.text = "新しい会話"
	data.start_node_id = node.id
	data.nodes.append(node)
	_npc().dialogue = data
	document.commit_npcs(before, "欠落した会話を作成")
	dialogue_panel.refresh()
