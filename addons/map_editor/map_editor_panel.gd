@tool
extends VBoxContainer

signal map_saved(path: String)
const Document = preload("res://addons/map_editor/map_edit_document.gd")
const Canvas = preload("res://addons/map_editor/map_canvas.gd")
const Validator = preload("res://scripts/data/map_validator.gd")
const NpcPanel = preload("res://addons/map_editor/npc_editor_panel.gd")
var recovery_map_path: String = "user://map_editor_recovery.tres"
var recovery_info_path: String = "user://map_editor_recovery.cfg"
var terrain_directory: String = "res://data/terrains"
const MAP_PATHS := ["res://data/maps/world.tres", "res://data/maps/town.tres", "res://data/maps/dungeon.tres"]
var document := Document.new()
var canvas: Canvas
var maps := OptionButton.new()
var palette := ItemList.new()
var npc_list := ItemList.new()
var npc_scroll := ScrollContainer.new()
var edit_kind := OptionButton.new()
var npc_side: VBoxContainer
var npc_detail: VBoxContainer
var selected_npc_id: String = ""
var pending_npc: NpcData
var moving_npc_id: String = ""
var base := OptionButton.new()
var status := Label.new()
var messages := RichTextLabel.new()
var undo_button: Button
var redo_button: Button
var save_button: Button
var switch_dialog := ConfirmationDialog.new()
var recovery_dialog := ConfirmationDialog.new()
var file_dialog := FileDialog.new()
var _pending_path: String = ""
var _terrains: Array[TerrainData] = []
var _palette_errors: PackedStringArray = []
var _report: Dictionary = {"errors": [], "warnings": []}
var _notice: String = ""
var _hover := Vector2i(-1, -1)
var _recovery_pending: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = Theme.new()
	theme.default_font = load("res://assets/fonts/ui_font.tres")
	var top := HFlowContainer.new()
	add_child(top)
	for path in MAP_PATHS:
		var map := load(path) as MapData
		maps.add_item(map.display_name)
		maps.set_item_metadata(maps.item_count - 1, path)
	top.add_child(maps)
	maps.item_selected.connect(func(index: int): request_open(maps.get_item_metadata(index)))
	_button(top, "別のマップを開く", func(): file_dialog.popup_centered_ratio(0.7))
	save_button = _button(top, "保存 (Ctrl+S)", save_current)
	_button(top, "再読み込み", func(): request_open(document.path))
	var mode := OptionButton.new()
	edit_kind.add_item("地形")
	edit_kind.add_item("NPC")
	edit_kind.item_selected.connect(func(index: int):
		flush_text()
		canvas.finish_stroke()
		canvas.npc_mode = index == 1
		palette.visible = index == 0
		npc_scroll.visible = index == 1
		_update_status()
	)
	top.add_child(edit_kind)
	mode.add_item("配置")
	mode.add_item("消去")
	mode.item_selected.connect(func(index: int): canvas.finish_stroke(); canvas.erase_mode = index == 1)
	top.add_child(mode)
	undo_button = _button(top, "元に戻す", undo_current)
	redo_button = _button(top, "やり直す", redo_current)
	var options := HFlowContainer.new()
	add_child(options)
	var label := Label.new()
	label.text = "消去後の下地:"
	options.add_child(label)
	options.add_child(base)
	base.item_selected.connect(func(index: int): canvas.finish_stroke(); canvas.base_terrain = _terrains[index]; _update_status())
	var zoom := OptionButton.new()
	for value in [0.5, 0.75, 1.0, 1.5, 2.0]:
		zoom.add_item("%d%%" % roundi(value * 100))
		zoom.set_item_metadata(zoom.item_count - 1, value)
	zoom.select(2)
	zoom.item_selected.connect(func(index: int):
		canvas.finish_stroke()
		var scroll := canvas.get_parent() as ScrollContainer
		var ratio: float = zoom.get_item_metadata(index) / canvas.zoom
		var offset := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical) * ratio
		canvas.zoom = zoom.get_item_metadata(index)
		canvas.update_extent()
		scroll.set_deferred("scroll_horizontal", roundi(offset.x))
		scroll.set_deferred("scroll_vertical", roundi(offset.y))
	)
	options.add_child(zoom)
	_button(options, "素材一覧を更新", refresh_palette)
	_button(options, "検証", _validate)
	var help := Label.new()
	help.text = "地形: 左で配置・右で下地 / NPC: 左で選択・配置、右で削除 / 中ドラッグ・スクロールバー: 移動"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	palette.custom_minimum_size.x = 245
	palette.fixed_icon_size = Vector2i(40, 40)
	palette.icon_mode = ItemList.ICON_MODE_LEFT
	palette.item_selected.connect(func(index: int): canvas.finish_stroke(); canvas.brush = _terrains[index]; _update_status())
	split.add_child(palette)
	var content := HSplitContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	canvas = Canvas.new()
	canvas.tile_size = (load("res://data/config.tres") as GameConfig).tile_size
	scroll.add_child(canvas)
	canvas.cell_hovered.connect(func(cell: Vector2i): _hover = cell; _update_status())
	canvas.operation_failed.connect(_show_notice)
	canvas.npc_cell_clicked.connect(_npc_cell)
	npc_scroll.custom_minimum_size.x = 400
	content.add_child(npc_scroll)
	npc_side = VBoxContainer.new()
	npc_side.custom_minimum_size.x = 380
	npc_scroll.add_child(npc_side)
	npc_side.add_child(_npc_label("NPC一覧"))
	npc_list.custom_minimum_size.y = 105
	npc_side.add_child(npc_list)
	npc_list.item_selected.connect(func(index: int): _select_npc(npc_list.get_item_metadata(index)))
	var npc_actions := HFlowContainer.new()
	npc_side.add_child(npc_actions)
	_button(npc_actions, "NPC追加", _new_npc)
	_button(npc_actions, "移動", _move_npc)
	_button(npc_actions, "複製", _duplicate_npc)
	_button(npc_actions, "削除", _delete_npc)
	_button(npc_actions, "ID修復", _repair_npc_ids)
	npc_detail = NpcPanel.new()
	npc_side.add_child(npc_detail)
	npc_detail.operation_failed.connect(_show_notice)
	npc_scroll.visible = false
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	messages.custom_minimum_size.y = 90
	messages.scroll_active = true
	add_child(messages)
	_setup_dialogs()
	document.changed.connect(_update_status)
	document.changed.connect(_refresh_npc_listing)
	document.committed.connect(_on_committed)
	_open_now(MAP_PATHS[0])
	_recovery_pending = FileAccess.file_exists(recovery_info_path)
	if _recovery_pending:
		_notice = "未保存の復旧データがあります。復元するか破棄するまで編集を開始できません。"
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recovery_dialog.call_deferred("popup_centered", Vector2i(600, 180))
		_update_status()

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _npc_label(value: String) -> Label:
	var result := Label.new()
	result.text = value
	return result

func flush_text() -> void:
	if is_instance_valid(npc_detail):
		npc_detail.flush_text()

func undo_current() -> void:
	flush_text()
	document.undo()

func redo_current() -> void:
	flush_text()
	document.redo()

func _selected_npc() -> NpcData:
	if document.data == null:
		return null
	for npc in document.data.npcs:
		if npc != null and npc.id == selected_npc_id:
			return npc
	return null

func _refresh_npc_listing() -> void:
	if not is_instance_valid(npc_list) or document.data == null:
		return
	npc_list.clear()
	for index in document.data.npcs.size():
		var npc := document.data.npcs[index]
		if npc == null:
			npc_list.add_item("(欠落したNPC Resource) [%d]" % index)
			npc_list.set_item_metadata(npc_list.item_count - 1, "__missing__%d" % index)
			continue
		npc_list.add_item("%s  %s" % [npc.id, str(npc.cell)])
		npc_list.set_item_metadata(npc_list.item_count - 1, npc.id)
		if npc.id == selected_npc_id:
			npc_list.select(npc_list.item_count - 1)
	canvas.selected_npc_id = selected_npc_id
	canvas.queue_redraw()
	if is_instance_valid(npc_detail):
		npc_detail.refresh()

func _select_npc(id: String) -> void:
	flush_text()
	selected_npc_id = id
	pending_npc = null
	moving_npc_id = ""
	npc_detail.set_target(document, id)
	_refresh_npc_listing()

func _new_npc() -> void:
	if _recovery_pending:
		return
	flush_text()
	var npc := NpcData.new()
	npc.id = document.new_id("npc")
	npc.texture = load("res://assets/art/npc.svg")
	npc.dialogue = DialogueData.new()
	var node := DialogueNodeData.new()
	node.id = "node_1"
	node.text = "こんにちは。"
	npc.dialogue.start_node_id = node.id
	npc.dialogue.nodes.append(node)
	pending_npc = npc
	moving_npc_id = ""
	_show_notice("配置先のセルを左クリックしてください。")

func _move_npc() -> void:
	if _recovery_pending:
		return
	flush_text()
	if _selected_npc() == null:
		return
	moving_npc_id = selected_npc_id
	pending_npc = null
	_show_notice("移動先のセルを左クリックしてください。")

func _duplicate_npc() -> void:
	if _recovery_pending:
		return
	flush_text()
	var npc := _selected_npc()
	if npc == null:
		return
	var source: Array[NpcData] = [npc]
	pending_npc = Document.copy_npcs(source)[0]
	pending_npc.id = document.new_id("npc")
	moving_npc_id = ""
	_show_notice("複製先のセルを左クリックしてください。")

func _delete_npc() -> void:
	if _recovery_pending:
		return
	flush_text()
	if selected_npc_id.begins_with("__missing__"):
		var index := int(selected_npc_id.trim_prefix("__missing__"))
		if index >= 0 and index < document.data.npcs.size() and document.data.npcs[index] == null:
			var before := document._snapshot()
			document.data.npcs.remove_at(index)
			document.commit_npcs(before, "欠落したNPCを削除")
			_select_npc("")
		return
	var npc := _selected_npc()
	if npc == null:
		return
	var before := document._snapshot()
	document.data.npcs.erase(npc)
	document.commit_npcs(before, "NPCを削除")
	_select_npc("")

func _repair_npc_ids() -> void:
	if _recovery_pending:
		return
	flush_text()
	var before := document._snapshot()
	var seen: Dictionary = {}
	for npc in document.data.npcs:
		if npc == null:
			continue
		if npc.id.strip_edges().is_empty() or seen.has(npc.id):
			npc.id = document.new_id("npc")
		seen[npc.id] = true
	document.commit_npcs(before, "NPCのIDを修復")
	_select_npc("")

func _npc_cell(cell: Vector2i, erase: bool) -> void:
	if _recovery_pending:
		return
	flush_text()
	if erase:
		var existing := document.npc_at(cell)
		if existing != null:
			var before := document._snapshot()
			document.data.npcs.erase(existing)
			document.commit_npcs(before, "NPCを削除")
			if selected_npc_id == existing.id:
				_select_npc("")
		return
	if pending_npc != null or not moving_npc_id.is_empty():
		var issue := document.placement_error(cell, moving_npc_id)
		if not issue.is_empty():
			_show_notice("配置できません: " + issue)
			return
		var before := document._snapshot()
		var placed_id: String
		if pending_npc != null:
			pending_npc.cell = cell
			placed_id = pending_npc.id
			document.data.npcs.append(pending_npc)
			pending_npc = null
		else:
			placed_id = moving_npc_id
			for npc in document.data.npcs:
				if npc != null and npc.id == moving_npc_id:
					npc.cell = cell
					break
			moving_npc_id = ""
		document.commit_npcs(before, "NPCを配置・移動")
		_select_npc(placed_id)
		return
	var target := document.npc_at(cell)
	_select_npc(target.id if target != null else "")

func _setup_dialogs() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.tres ; MapData Resource"])
	file_dialog.file_selected.connect(request_open)
	add_child(file_dialog)
	switch_dialog.title = "未保存の変更"
	switch_dialog.dialog_text = "現在のマップに変更があります。保存してから開きますか？"
	switch_dialog.ok_button_text = "保存して開く"
	switch_dialog.cancel_button_text = "キャンセル"
	switch_dialog.add_button("破棄して開く", true, "discard")
	switch_dialog.confirmed.connect(func():
		if save_current():
			_open_now(_pending_path)
	)
	switch_dialog.custom_action.connect(func(action: StringName):
		if action == &"discard":
			if _open_now(_pending_path):
				clear_recovery()
			switch_dialog.hide()
	)
	add_child(switch_dialog)
	recovery_dialog.title = "マップの復旧データ"
	recovery_dialog.dialog_text = "前回の未保存データが残っています。復元すると編集を続けられます。\n元マップが外部で変更されている場合は上書き保存を止めます。"
	recovery_dialog.ok_button_text = "復元"
	recovery_dialog.cancel_button_text = "後で"
	recovery_dialog.add_button("復旧データを破棄", true, "discard")
	recovery_dialog.confirmed.connect(_restore_recovery)
	recovery_dialog.custom_action.connect(func(action: StringName):
		if action == &"discard":
			clear_recovery()
			_recovery_pending = false
			canvas.mouse_filter = Control.MOUSE_FILTER_STOP
			recovery_dialog.hide()
			_show_notice("復旧データを破棄しました。")
	)
	add_child(recovery_dialog)

func request_open(path: String) -> void:
	flush_text()
	canvas.finish_stroke()
	_select_current_map()
	if _recovery_pending:
		recovery_dialog.popup_centered(Vector2i(600, 180))
		return
	_pending_path = path
	if document.is_dirty():
		switch_dialog.popup_centered(Vector2i(520, 150))
	else:
		_open_now(path)

func _open_now(path: String) -> bool:
	flush_text()
	if not document.open(path):
		_show_notice(document.last_error)
		return false
	canvas.set_document(document)
	selected_npc_id = ""
	pending_npc = null
	moving_npc_id = ""
	npc_detail.set_target(document, "")
	_refresh_npc_listing()
	canvas.get_parent().scroll_horizontal = 0
	canvas.get_parent().scroll_vertical = 0
	_select_current_map()
	canvas.brush = null
	canvas.base_terrain = null
	_notice = ""
	refresh_palette()
	_validate()
	return true

func _select_current_map() -> void:
	for index in maps.item_count:
		if maps.get_item_metadata(index) == document.path:
			maps.select(index)
			return
	if not document.path.is_empty():
		maps.add_item(document.path.get_file())
		maps.set_item_metadata(maps.item_count - 1, document.path)
		maps.select(maps.item_count - 1)

static func terrain_paths(directory: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() in ["tres", "res"]:
			result.append(directory.path_join(filename))
	for subdir in DirAccess.get_directories_at(directory):
		result.append_array(terrain_paths(directory.path_join(subdir)))
	result.sort()
	return result

func refresh_palette() -> void:
	canvas.finish_stroke()
	var previous_brush := canvas.brush
	var previous_base := canvas.base_terrain
	_terrains.clear()
	_palette_errors.clear()
	for path in terrain_paths(terrain_directory):
		var terrain := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as TerrainData
		if terrain != null:
			_terrains.append(terrain)
		else:
			_palette_errors.append("TerrainData を読み込めません: " + path)
	if document.data != null:
		for terrain in document.data.terrains.values():
			if terrain is TerrainData:
				var found := false
				for other in _terrains:
					found = found or Document.same_terrain(terrain, other)
				if not found:
					_terrains.append(terrain)
	palette.clear()
	base.clear()
	canvas.brush = null
	canvas.base_terrain = null
	var valid: Array[int] = []
	for index in _terrains.size():
		var terrain := _terrains[index]
		var duplicate_id := false
		for other in _terrains:
			if other != terrain and other.id == terrain.id:
				duplicate_id = true
		var disabled := duplicate_id or terrain.texture == null or terrain.id.is_empty()
		palette.add_item("%s · %s" % [terrain.id, "通行可" if terrain.walkable else "通行不可"], terrain.texture)
		palette.set_item_disabled(index, disabled)
		palette.set_item_tooltip(index, terrain.resource_path)
		base.add_item(terrain.id)
		base.set_item_disabled(index, disabled)
		if disabled:
			_palette_errors.append("素材 %s: IDの重複・空欄、またはテクスチャ欠落。配置不可。" % terrain.resource_path)
		else:
			valid.append(index)
	for index in valid:
		var terrain := _terrains[index]
		if canvas.brush == null or Document.same_terrain(terrain, previous_brush):
			canvas.brush = terrain
			palette.select(index)
		var preferred := "floor" if document.data != null and document.data.id == "dungeon" else "plain"
		if Document.same_terrain(terrain, previous_base) or (previous_base == null and (canvas.base_terrain == null and terrain.walkable or terrain.id == preferred)):
			canvas.base_terrain = terrain
			base.select(index)
	if canvas.base_terrain == null:
		base.select(-1)
	_update_status()
	_validate()

func registered_maps() -> Dictionary:
	var result: Dictionary = {}
	for path in MAP_PATHS:
		var map := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
		if map != null:
			result[map.id] = map
	return result

func _validate() -> void:
	_report = Validator.validate(document.data, registered_maps())
	_update_status()

func _on_committed() -> void:
	_validate()
	checkpoint()

func _show_notice(message: String) -> void:
	_notice = message
	_update_status()

func _update_status() -> void:
	if not is_instance_valid(canvas) or document.data == null:
		return
	status.text = "%s | %d × %d | セル %s | 地形: %s | 下地: %s | %s" % [document.data.display_name, document.data.width, document.data.height, str(_hover), canvas.brush.id if canvas.brush != null else "未選択", canvas.base_terrain.id if canvas.base_terrain != null else "未選択（消去不可）", "● 未保存" if document.is_dirty() else "保存済み"]
	undo_button.disabled = not document.history.has_undo() or _recovery_pending
	redo_button.disabled = not document.history.has_redo() or _recovery_pending
	save_button.disabled = _recovery_pending
	edit_kind.disabled = _recovery_pending
	var lines: PackedStringArray = []
	if not _notice.is_empty():
		lines.append(_notice)
	lines.append_array(_palette_errors)
	for error in _report.errors:
		lines.append("保存不可: " + error)
	for warning in _report.warnings:
		lines.append("要確認（保存可）: " + warning)
	if lines.is_empty():
		lines.append("形式・動線の検証に問題はありません。保存後にゲームを起動し直してください。")
	messages.text = "\n".join(lines)

func save_current() -> bool:
	if _recovery_pending:
		return false
	canvas.finish_stroke()
	flush_text()
	if not document.save(registered_maps()):
		_show_notice(document.last_error)
		checkpoint()
		return false
	clear_recovery()
	_show_notice("保存しました: " + document.path)
	map_saved.emit(document.path)
	return true

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _recovery_pending or not event is InputEventKey or not event.pressed or event.echo or not event.is_command_or_control_pressed():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not is_ancestor_of(focus) or focus is LineEdit or focus is TextEdit:
		return
	if event.keycode == KEY_S:
		save_current()
	elif event.keycode == KEY_Z:
		if event.shift_pressed:
			redo_current()
		else:
			undo_current()
	else:
		return
	get_viewport().set_input_as_handled()

func checkpoint() -> bool:
	if _recovery_pending:
		return true
	if not document.is_dirty():
		clear_recovery()
		return true
	var error := ResourceSaver.save(Document.copy_map(document.data), recovery_map_path)
	var info := ConfigFile.new()
	info.set_value("recovery", "path", document.path)
	info.set_value("recovery", "baseline_hash", document.baseline_hash)
	if error == OK:
		error = info.save(recovery_info_path)
	if error != OK:
		_show_notice("復旧データの保存に失敗しました: " + error_string(error))
		push_error(_notice)
	return error == OK

func clear_recovery() -> void:
	if FileAccess.file_exists(recovery_info_path):
		DirAccess.remove_absolute(recovery_info_path)
	if FileAccess.file_exists(recovery_map_path):
		DirAccess.remove_absolute(recovery_map_path)

func _restore_recovery() -> void:
	var info := ConfigFile.new()
	var restored := ResourceLoader.load(recovery_map_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	if info.load(recovery_info_path) != OK or restored == null:
		_show_notice("復旧データを読み込めません。user://map_editor_recovery.* を確認してください。")
		return
	var source_path: String = info.get_value("recovery", "path", "")
	if not _open_now(source_path):
		# Deleted source: retain the recovered map so it remains inspectable.
		document.data = Document.copy_map(restored)
		document.path = source_path
		document.history.clear_history()
		document._saved = {}
	document.data = Document.copy_map(restored)
	document.baseline_hash = info.get_value("recovery", "baseline_hash", "")
	_recovery_pending = false
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.set_document(document)
	selected_npc_id = ""
	npc_detail.set_target(document, "")
	_refresh_npc_listing()
	_select_current_map()
	refresh_palette()
	_show_notice("未保存データを復元しました。保存前に内容を確認してください。")
