@tool
extends VBoxContainer

signal operation_failed(message: String)
const Document = preload("res://addons/map_editor/map_edit_document.gd")
var document: Document
var npc_id: String = ""
var node_id: String = ""
var choice_index: int = -1
var _busy := false
var _pending_before: Dictionary = {}
var _pending_description: String = ""
var _typing := Timer.new()
var nodes := ItemList.new()
var label_edit := LineEdit.new()
var body_edit := TextEdit.new()
var next_option := OptionButton.new()
var choices := ItemList.new()
var choice_edit := LineEdit.new()
var choice_next := OptionButton.new()
var preview_view := DialogueView.new()
var preview_model := DialogueModel.new()
var preview_status := Label.new()

func _ready() -> void:
	_typing.one_shot = true
	_typing.wait_time = 0.7
	_typing.timeout.connect(flush_text)
	add_child(_typing)
	var title := Label.new()
	title.text = "会話の本文一覧"
	add_child(title)
	nodes.custom_minimum_size.y = 105
	add_child(nodes)
	nodes.item_selected.connect(func(index: int):
		flush_text()
		node_id = nodes.get_item_metadata(index)
		choice_index = -1
		refresh()
	)
	var node_actions := HFlowContainer.new()
	add_child(node_actions)
	_button(node_actions, "本文追加", _add_node)
	_button(node_actions, "複製", _duplicate_node)
	_button(node_actions, "削除", _delete_node)
	_button(node_actions, "↑", func(): _move_node(-1))
	_button(node_actions, "↓", func(): _move_node(1))
	_button(node_actions, "開始本文", _set_start)
	_button(node_actions, "ID修復", _repair_node_ids)
	add_child(_label("編集用ラベル"))
	add_child(label_edit)
	label_edit.text_changed.connect(func(value: String): _type_change("本文ラベルを編集", func(): _selected_node().editor_label = value))
	label_edit.focus_exited.connect(flush_text)
	add_child(_label("本文（改行可・表示は2行ずつ）"))
	body_edit.custom_minimum_size.y = 105
	body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(body_edit)
	body_edit.text_changed.connect(func(): _type_change("本文を編集", func(): _selected_node().text = body_edit.text))
	body_edit.focus_exited.connect(flush_text)
	add_child(_label("通常の移動先"))
	add_child(next_option)
	next_option.item_selected.connect(func(index: int): _change("本文の移動先を変更", func(): _selected_node().next_node_id = next_option.get_item_metadata(index)))
	add_child(_label("選択肢（最終ページに表示）"))
	choices.custom_minimum_size.y = 80
	add_child(choices)
	choices.item_selected.connect(func(index: int): flush_text(); choice_index = index; refresh())
	var choice_actions := HFlowContainer.new()
	add_child(choice_actions)
	_button(choice_actions, "選択肢追加", _add_choice)
	_button(choice_actions, "削除", _delete_choice)
	_button(choice_actions, "↑", func(): _move_choice(-1))
	_button(choice_actions, "↓", func(): _move_choice(1))
	add_child(_label("選択肢の文言"))
	add_child(choice_edit)
	choice_edit.text_changed.connect(func(value: String): _type_change("選択肢を編集", func(): _selected_node().choices[choice_index].text = value))
	choice_edit.focus_exited.connect(flush_text)
	add_child(_label("選択後の移動先"))
	add_child(choice_next)
	choice_next.item_selected.connect(func(index: int): _change("選択肢の移動先を変更", func(): _selected_node().choices[choice_index].next_node_id = choice_next.get_item_metadata(index)))
	add_child(_label("表示・会話プレビュー"))
	var preview_actions := HFlowContainer.new()
	add_child(preview_actions)
	_button(preview_actions, "開始から再生", func(): _start_preview(false))
	_button(preview_actions, "選択本文を確認", func(): _start_preview(true))
	_button(preview_actions, "停止", _stop_preview)
	var preview_keys := HFlowContainer.new()
	add_child(preview_keys)
	_button(preview_keys, "↑", func(): _preview_select(-1))
	_button(preview_keys, "↓", func(): _preview_select(1))
	_button(preview_keys, "Enter 次へ", _preview_confirm)
	_button(preview_keys, "表示を上へ", func(): preview_view.scroll_choices(-1))
	_button(preview_keys, "表示を下へ", func(): preview_view.scroll_choices(1))
	preview_view.custom_minimum_size = Vector2(380, 253)
	preview_view.focus_mode = Control.FOCUS_ALL
	add_child(preview_view)
	preview_view.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			preview_view.grab_focus()
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				preview_view.scroll_choices(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				preview_view.scroll_choices(1)
	)
	preview_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(preview_status)
	refresh()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or preview_model.current == null or get_viewport().gui_get_focus_owner() != preview_view:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_UP, KEY_W]:
		_preview_select(-1)
	elif event.keycode in [KEY_DOWN, KEY_S]:
		_preview_select(1)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_preview_confirm()
	else:
		return
	get_viewport().set_input_as_handled()

func _label(value: String) -> Label:
	var result := Label.new()
	result.text = value
	return result

func _button(parent: Node, value: String, action: Callable) -> void:
	var button := Button.new()
	button.text = value
	button.pressed.connect(action)
	parent.add_child(button)

func set_target(value: Document, id: String) -> void:
	flush_text()
	document = value
	npc_id = id
	node_id = ""
	choice_index = -1
	_stop_preview()
	refresh()

func _npc() -> NpcData:
	if document == null or document.data == null:
		return null
	for npc in document.data.npcs:
		if npc != null and npc.id == npc_id:
			return npc
	return null

func _selected_node() -> DialogueNodeData:
	var npc := _npc()
	if npc == null or npc.dialogue == null:
		return null
	for node in npc.dialogue.nodes:
		if node != null and node.id == node_id:
			return node
	return null

func _new_node_id() -> String:
	var index := 1
	var used: Dictionary = {}
	for node in _npc().dialogue.nodes:
		if node != null:
			used[node.id] = true
	while used.has("node_%d" % index):
		index += 1
	return "node_%d" % index

func refresh() -> void:
	if _busy or not _pending_before.is_empty():
		return
	_busy = true
	var npc := _npc()
	visible = npc != null and npc.dialogue != null
	if not visible:
		_busy = false
		return
	if _selected_node() == null and not node_id.begins_with("__missing__"):
		node_id = ""
		for entry in npc.dialogue.nodes:
			if entry != null:
				node_id = entry.id
				break
	var node := _selected_node()
	nodes.clear()
	for index in npc.dialogue.nodes.size():
		var entry := npc.dialogue.nodes[index]
		if entry == null:
			nodes.add_item("(欠落した本文Resource) [%d]" % index)
			nodes.set_item_metadata(nodes.item_count - 1, "__missing__%d" % index)
			if node_id == "__missing__%d" % index:
				nodes.select(nodes.item_count - 1)
			continue
		var marker := "★ " if entry.id == npc.dialogue.start_node_id else ""
		var caption := entry.editor_label if not entry.editor_label.is_empty() else entry.text.replace("\n", " ").substr(0, 18)
		nodes.add_item(marker + caption + " [%s]" % entry.id)
		nodes.set_item_metadata(nodes.item_count - 1, entry.id)
		if entry.id == node_id:
			nodes.select(nodes.item_count - 1)
	label_edit.editable = node != null
	body_edit.editable = node != null
	# 入力確定後もrefreshされるため、同じ文字列を再設定してキャレットや選択を消さない。
	var label_text := node.editor_label if node != null else ""
	if label_edit.text != label_text:
		label_edit.text = label_text
	var body_text := node.text if node != null else ""
	if body_edit.text != body_text:
		body_edit.text = body_text
	_fill_targets(next_option, node.next_node_id if node != null else "")
	next_option.disabled = node == null or not node.choices.is_empty()
	choices.clear()
	if node != null:
		for choice in node.choices:
			choices.add_item(choice.text.replace("\n", " ").substr(0, 25) if choice != null else "(欠落)")
	if choice_index >= choices.item_count:
		choice_index = -1
	if choice_index >= 0:
		choices.select(choice_index)
	var choice: DialogueChoiceData = node.choices[choice_index] if node != null and choice_index >= 0 else null
	choice_edit.editable = choice != null
	var choice_text := choice.text if choice != null else ""
	if choice_edit.text != choice_text:
		choice_edit.text = choice_text
	_fill_targets(choice_next, choice.next_node_id if choice != null else "")
	choice_next.disabled = choice == null
	_busy = false

func _fill_targets(option: OptionButton, value: String) -> void:
	option.clear()
	option.add_item("会話終了")
	option.set_item_metadata(0, "")
	var selected := 0
	var npc := _npc()
	if npc != null and npc.dialogue != null:
		for node in npc.dialogue.nodes:
			if node == null:
				continue
			option.add_item("%s [%s]" % [node.editor_label if not node.editor_label.is_empty() else node.text.substr(0, 12), node.id])
			option.set_item_metadata(option.item_count - 1, node.id)
			if node.id == value:
				selected = option.item_count - 1
	if not value.is_empty() and selected == 0:
		option.add_item("(欠落した移動先) [%s]" % value)
		selected = option.item_count - 1
		option.set_item_metadata(selected, value)
	option.select(selected)

func _change(description: String, action: Callable) -> void:
	if _busy or _npc() == null:
		return
	flush_text()
	var before := document._snapshot()
	action.call()
	document.commit_npcs(before, description)
	refresh()

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
	if _pending_before.is_empty():
		return
	_typing.stop()
	var before := _pending_before
	var description := _pending_description
	_pending_before = {}
	document.commit_npcs(before, description)
	refresh()

func _add_node() -> void:
	if _npc() == null or _npc().dialogue == null:
		return
	var new_id := _new_node_id()
	_change("本文を追加", func():
		var node := DialogueNodeData.new()
		node.id = new_id
		node.text = "新しい本文"
		_npc().dialogue.nodes.append(node)
		if _npc().dialogue.start_node_id.is_empty():
			_npc().dialogue.start_node_id = new_id
	)
	node_id = new_id
	refresh()

func _duplicate_node() -> void:
	var node := _selected_node()
	if node == null:
		return
	var new_id := _new_node_id()
	_change("本文を複製", func():
		var copy := node.duplicate(false) as DialogueNodeData
		copy.id = new_id
		copy.choices = []
		for choice in node.choices:
			copy.choices.append(choice.duplicate(false) as DialogueChoiceData if choice != null else null)
		_npc().dialogue.nodes.append(copy)
	)
	node_id = new_id
	refresh()

func _delete_node() -> void:
	if node_id.begins_with("__missing__") and _npc() != null and _npc().dialogue != null:
		var index := int(node_id.trim_prefix("__missing__"))
		if index >= 0 and index < _npc().dialogue.nodes.size() and _npc().dialogue.nodes[index] == null:
			_change("欠落した本文を削除", func(): _npc().dialogue.nodes.remove_at(index))
			node_id = ""
			refresh()
		return
	var node := _selected_node()
	if node == null:
		return
	var dialogue := _npc().dialogue
	if dialogue.start_node_id == node.id:
		operation_failed.emit("開始本文は削除できません。先に開始本文を変更してください。")
		return
	for source in dialogue.nodes:
		if source == null or source == node:
			continue
		if source.next_node_id == node.id:
			operation_failed.emit("本文 %s から参照されています。" % source.id)
			return
		for choice in source.choices:
			if choice != null and choice.next_node_id == node.id:
				operation_failed.emit("本文 %s の選択肢から参照されています。" % source.id)
				return
	_change("本文を削除", func(): dialogue.nodes.erase(node))
	node_id = ""
	refresh()

func _repair_node_ids() -> void:
	if _npc() == null or _npc().dialogue == null:
		return
	flush_text()
	var before := document._snapshot()
	var seen: Dictionary = {}
	for node in _npc().dialogue.nodes:
		if node == null:
			continue
		if node.id.strip_edges().is_empty() or seen.has(node.id):
			node.id = _new_node_id()
		seen[node.id] = true
	if _npc().dialogue.start_node_id.is_empty():
		for node in _npc().dialogue.nodes:
			if node != null:
				_npc().dialogue.start_node_id = node.id
				break
	document.commit_npcs(before, "本文のIDを修復")
	node_id = ""
	refresh()

func _move_node(delta: int) -> void:
	var node := _selected_node()
	if node == null:
		return
	var entries := _npc().dialogue.nodes
	var index := entries.find(node)
	var target := index + delta
	if target < 0 or target >= entries.size():
		return
	_change("本文を並べ替え", func(): entries[index] = entries[target]; entries[target] = node)

func _set_start() -> void:
	if _selected_node() != null:
		_change("開始本文を変更", func(): _npc().dialogue.start_node_id = node_id)

func _add_choice() -> void:
	if _selected_node() == null:
		return
	_change("選択肢を追加", func():
		var node := _selected_node()
		node.next_node_id = ""
		var choice := DialogueChoiceData.new()
		choice.text = "新しい選択肢"
		node.choices.append(choice)
	)
	choice_index = _selected_node().choices.size() - 1
	refresh()

func _delete_choice() -> void:
	if _selected_node() != null and choice_index >= 0:
		_change("選択肢を削除", func(): _selected_node().choices.remove_at(choice_index))
		choice_index = -1
		refresh()

func _move_choice(delta: int) -> void:
	var node := _selected_node()
	if node == null or choice_index < 0:
		return
	var target := choice_index + delta
	if target < 0 or target >= node.choices.size():
		return
	_change("選択肢を並べ替え", func():
		var item := node.choices[choice_index]
		node.choices[choice_index] = node.choices[target]
		node.choices[target] = item
	)
	choice_index = target
	refresh()

func _start_preview(selected_only: bool) -> void:
	flush_text()
	var npc := _npc()
	if npc == null or npc.dialogue == null:
		return
	var source: Array[NpcData] = [npc]
	var copied := Document.copy_npcs(source)[0]
	if selected_only and _selected_node() != null:
		copied.dialogue.start_node_id = node_id
	var report := DialogueValidator.validate(copied.dialogue)
	if not report.errors.is_empty():
		preview_status.text = "開始不可: " + " / ".join(report.errors)
		return
	if preview_model.start(copied.dialogue, preview_view.font):
		preview_view.set_content(preview_model)
		preview_status.text = "プレビュー中。操作ボタンで進めてください。"

func _preview_select(delta: int) -> void:
	preview_model.select(delta)
	preview_view.sync_selection()

func _preview_confirm() -> void:
	if preview_model.current == null:
		return
	if not preview_model.confirm():
		preview_status.text = "会話終了。再生ボタンで最初から確認できます。"
		preview_view.model = null
	else:
		preview_view.choice_scroll = 0
	preview_view.queue_redraw()

func _stop_preview() -> void:
	preview_model.current = null
	preview_view.model = null
	preview_view.queue_redraw()
	preview_status.text = ""
