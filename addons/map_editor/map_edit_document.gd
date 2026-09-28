@tool
extends RefCounted
## Owns containers, never mutates the shared map or external terrain/enemy resources.
signal changed
signal committed

const Validator = preload("res://scripts/data/map_validator.gd")
const KEYS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
var data: MapData
var path: String = ""
var baseline_hash: String = ""
var history := UndoRedo.new()
var last_error: String = ""
var _saved: Dictionary = {}
var _before: Dictionary = {}
var _stroke_terrain: TerrainData
var _stroke_key: String = ""
var _last_cell := Vector2i(-1, -1)
var _active: bool = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		history.clear_history()
		history.free()

static func copy_map(source: MapData) -> MapData:
	var result := source.duplicate(false) as MapData
	result.rows = source.rows.duplicate()
	result.terrains = source.terrains.duplicate()
	result.spawns = source.spawns.duplicate(true)
	result.portals = source.portals.duplicate(true)
	result.healing_cells = source.healing_cells.duplicate()
	result.enemies = source.enemies.duplicate()
	result.npcs = copy_npcs(source.npcs)
	return result

static func copy_npcs(source: Array[NpcData]) -> Array[NpcData]:
	var result: Array[NpcData] = []
	for npc in source:
		if npc == null:
			result.append(null)
			continue
		var copied := npc.duplicate(false) as NpcData
		if npc.dialogue != null:
			copied.dialogue = npc.dialogue.duplicate(false) as DialogueData
			copied.dialogue.nodes = []
			for node in npc.dialogue.nodes:
				if node == null:
					copied.dialogue.nodes.append(null)
					continue
				var node_copy := node.duplicate(false) as DialogueNodeData
				node_copy.choices = []
				for choice in node.choices:
					node_copy.choices.append(choice.duplicate(false) as DialogueChoiceData if choice != null else null)
				copied.dialogue.nodes.append(node_copy)
		result.append(copied)
	return result

func open(file_path: String) -> bool:
	last_error = ""
	if not FileAccess.file_exists(file_path):
		return _fail("ファイルがありません: " + file_path)
	var source := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	if source == null:
		return _fail("MapData を読み込めません: " + file_path)
	end_stroke()
	data = copy_map(source)
	path = file_path
	baseline_hash = FileAccess.get_sha256(path)
	history.clear_history()
	_saved = _snapshot()
	changed.emit()
	return true

func _snapshot() -> Dictionary:
	return {"rows": data.rows.duplicate(), "terrains": data.terrains.duplicate(), "npcs": copy_npcs(data.npcs)}

static func same_state(a: Dictionary, b: Dictionary) -> bool:
	return storage_value(a) == storage_value(b)

func is_dirty() -> bool:
	return data != null and not same_state(_snapshot(), _saved)

func in_bounds(cell: Vector2i) -> bool:
	return data != null and cell.x >= 0 and cell.y >= 0 and cell.x < data.width and cell.y < data.height

static func same_terrain(a: TerrainData, b: TerrainData) -> bool:
	return a == b or (a != null and b != null and not a.resource_path.is_empty() and a.resource_path == b.resource_path)

func key_for(terrain: TerrainData) -> String:
	for key in data.terrains:
		if key is String and key.length() == 1 and same_terrain(data.terrains[key] as TerrainData, terrain):
			return key
	for key in KEYS:
		if not data.terrains.has(key):
			return key
	return ""

func begin_stroke(terrain: TerrainData) -> bool:
	end_stroke()
	last_error = ""
	if data == null or not Validator.validate(data, {}, false).errors.is_empty():
		return _fail("形式不正のマップは編集できません。検証メッセージを確認してください。")
	if terrain == null or terrain.texture == null or terrain.id.is_empty():
		return _fail("有効な地形を選択してください。")
	for existing in data.terrains.values():
		if existing is TerrainData and existing.id == terrain.id and not same_terrain(existing, terrain):
			return _fail("地形IDが重複しています: " + terrain.id)
	_stroke_key = key_for(terrain)
	if _stroke_key.is_empty():
		return _fail("未使用の英数字キーがありません。配置を中止しました。")
	_before = _snapshot()
	_stroke_terrain = terrain
	_active = true
	_last_cell = Vector2i(-1, -1)
	return true

func paint_to(cell: Vector2i) -> void:
	if not _active:
		return
	if not in_bounds(cell):
		_last_cell = Vector2i(-1, -1)
		return
	var start := _last_cell if in_bounds(_last_cell) else cell
	# Integer Bresenham: no holes even when mouse motion skips several cells.
	var delta := Vector2i(absi(cell.x - start.x), absi(cell.y - start.y))
	var step := Vector2i(1 if start.x < cell.x else -1, 1 if start.y < cell.y else -1)
	var error := delta.x - delta.y
	while true:
		_paint(start)
		if start == cell:
			break
		var twice := error * 2
		if twice > -delta.y:
			error -= delta.y
			start.x += step.x
		if twice < delta.x:
			error += delta.x
			start.y += step.y
	_last_cell = cell
	changed.emit()

func _paint(cell: Vector2i) -> void:
	var current := data.terrains.get(data.rows[cell.y][cell.x]) as TerrainData
	if same_terrain(current, _stroke_terrain):
		return
	data.terrains[_stroke_key] = _stroke_terrain
	var row := data.rows[cell.y]
	data.rows[cell.y] = row.substr(0, cell.x) + _stroke_key + row.substr(cell.x + 1)

func end_stroke() -> void:
	if not _active:
		return
	_active = false
	var after := _snapshot()
	if same_state(after, _before):
		return
	history.create_action("地形を配置")
	history.add_do_method(_restore.bind(after))
	history.add_undo_method(_restore.bind(_before))
	history.commit_action(false)
	_before = {}
	changed.emit()
	committed.emit()

func _restore(state: Dictionary) -> void:
	data.rows = state.rows.duplicate()
	data.terrains = state.terrains.duplicate()
	data.npcs = copy_npcs(state.npcs)
	changed.emit()

func commit_npcs(before: Dictionary, description: String) -> void:
	var after := _snapshot()
	if same_state(before, after):
		return
	history.create_action(description)
	history.add_do_method(_restore.bind(after))
	history.add_undo_method(_restore.bind(before))
	history.commit_action(false)
	changed.emit()
	committed.emit()

func npc_at(cell: Vector2i) -> NpcData:
	for npc in data.npcs:
		if npc != null and npc.cell == cell:
			return npc
	return null

func placement_error(cell: Vector2i, except_id: String = "") -> String:
	var occupied: Dictionary = {}
	for npc in data.npcs:
		if npc != null and npc.id != except_id:
			occupied[npc.cell] = true
	return Validator.npc_placement_issue(data, cell, occupied)

func new_id(prefix: String) -> String:
	var used: Dictionary = {}
	for npc in data.npcs:
		if npc != null:
			used[npc.id] = true
	var index := 1
	while used.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]

func undo() -> void:
	end_stroke()
	history.undo()
	committed.emit()

func redo() -> void:
	end_stroke()
	history.redo()
	committed.emit()

func _fail(message: String) -> bool:
	last_error = message
	return false

# Compare storage values recursively while retaining external resource identities.
static func storage_value(value: Variant) -> Variant:
	if value is Resource:
		if not value.resource_path.is_empty() and not value.resource_path.contains("::"):
			return value.resource_path
		var properties: Dictionary = {}
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name != "resource_path":
				properties[property.name] = storage_value(value.get(property.name))
		return properties
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = storage_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(storage_value(item))
		return result
	return value

static func map_values(map: MapData) -> Dictionary:
	var result: Dictionary = {}
	for property in map.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			result[property.name] = storage_value(map.get(property.name))
	return result

func save(registered_maps: Dictionary = {}) -> bool:
	end_stroke()
	last_error = ""
	var report := Validator.validate(data, registered_maps)
	if not report.errors.is_empty():
		return _fail("保存できません:\n" + "\n".join(report.errors))
	if baseline_hash.is_empty() or FileAccess.get_sha256(path) != baseline_hash:
		return _fail("保存先が外部で変更または削除されました。作業内容を保持しています。再読み込みしてください。")
	var temp := path.get_base_dir().path_join("." + path.get_file().get_basename() + ".map-editor-%d.tres" % Time.get_ticks_usec())
	var output := copy_map(data)
	var error := ResourceSaver.save(output, temp)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return _fail("一時ファイルの保存に失敗しました: " + error_string(error))
	# Keep the original UID so uid:// references continue to resolve after replacement.
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID:
		error = ResourceSaver.set_uid(temp, uid)
	var verified := ResourceLoader.load(temp, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	if error != OK or verified == null or map_values(verified) != map_values(data):
		DirAccess.remove_absolute(temp)
		return _fail("一時ファイルの再読み込み確認に失敗しました。元ファイルは保持しています。")
	if FileAccess.get_sha256(path) != baseline_hash:
		DirAccess.remove_absolute(temp)
		return _fail("保存中に外部変更を検出しました。作業内容を保持しています。")
	error = _replace_file(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return _fail("ファイルの置き換えに失敗しました: " + error_string(error))
	baseline_hash = FileAccess.get_sha256(path)
	_saved = _snapshot()
	ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	changed.emit()
	committed.emit()
	return true

func _replace_file(from: String, to: String) -> Error:
	# Same-directory rename replaces atomically; no delete-first window on failure.
	return DirAccess.rename_absolute(from, to)
