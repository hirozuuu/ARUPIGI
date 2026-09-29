@tool
class_name MapValidator
extends RefCounted
## Data-only validation, shared by the editor and game integration tests.

static func validate(map: MapData, registered_maps: Dictionary = {}, include_npcs: bool = true) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if map == null:
		return {"errors": PackedStringArray(["MapData を読み込めません。"]), "warnings": warnings}
	if map.width <= 0 or map.height <= 0 or map.rows.size() != map.height:
		errors.append("幅・高さは正の値、行数は高さと一致する必要があります。")
	for y in map.rows.size():
		if map.rows[y].length() != map.width:
			errors.append("行 %d の文字数が幅 %d と一致しません。" % [y, map.width])
		for x in map.rows[y].length():
			var terrain = map.terrains.get(map.rows[y][x])
			if not terrain is TerrainData or terrain.texture == null:
				errors.append("(%d, %d): 地形 '%s' またはテクスチャがありません。" % [x, y, map.rows[y][x]])
	for key in map.terrains:
		if not key is String or key.length() != 1:
			errors.append("地形対応キー '%s' は1文字である必要があります。" % str(key))
	# Invalid structure must never reach drawing or pathfinding.
	if not errors.is_empty():
		return {"errors": errors, "warnings": warnings}
	if include_npcs:
		var seen_ids: Dictionary = {}
		var seen_cells: Dictionary = {}
		for npc in map.npcs:
			if npc == null:
				errors.append("NPC Resourceがありません。")
				continue
			if npc.id.strip_edges().is_empty() or seen_ids.has(npc.id):
				errors.append("NPCのIDが空か重複しています: %s" % npc.id)
			seen_ids[npc.id] = true
			if npc.texture == null:
				errors.append("NPC %s の画像がありません。" % npc.id)
			var dialogue_report := DialogueValidator.validate(npc.dialogue)
			for error in dialogue_report.errors:
				errors.append("NPC %s: %s" % [npc.id, error])
			for warning in dialogue_report.warnings:
				warnings.append("NPC %s: %s" % [npc.id, warning])
			var issue := npc_placement_issue(map, npc.cell, seen_cells)
			if not issue.is_empty():
				warnings.append("NPC %s %s: %s" % [npc.id, str(npc.cell), issue])
			seen_cells[npc.cell] = true
	var important: Array[Dictionary] = []
	var spawn_ids: Array = map.spawns.keys()
	spawn_ids.sort()
	if spawn_ids.is_empty():
		warnings.append("出現位置がありません。")
	for spawn_id in spawn_ids:
		important.append({"label": "出現位置 %s" % str(spawn_id), "cell": map.spawns[spawn_id]})
	for portal in map.portals:
		var cell = portal.get("cell")
		important.append({"label": "出入口", "cell": cell})
		for spawn_id in spawn_ids:
			if cell is Vector2i and map.spawns[spawn_id] is Vector2i and cell == map.spawns[spawn_id]:
				warnings.append("%s: 出入口と出現位置 %s が重なっています。" % [str(cell), str(spawn_id)])
		var target = registered_maps.get(portal.get("target_map", ""))
		if not target is MapData or not target.spawns.has(portal.get("target_spawn", "")):
			warnings.append("%s: 移動先マップまたは出現位置が登録されていません。" % str(cell))
	for cell in map.healing_cells:
		important.append({"label": "回復地点", "cell": cell})
	var base_id: String = ""
	if not spawn_ids.is_empty():
		base_id = str(spawn_ids[0])
	if map.id == "world":
		base_id = "start"
	elif map.id in ["town", "dungeon", "forest"]:
		base_id = "entry"
	var base = map.spawns.get(base_id)
	var visited: Dictionary = {}
	if base is Vector2i and map.is_walkable(base):
		var frontier: Array[Vector2i] = [base]
		visited[base] = true
		var cursor: int = 0
		while cursor < frontier.size():
			var cell: Vector2i = frontier[cursor]
			cursor += 1
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + direction
				if map.is_walkable(next) and not visited.has(next):
					visited[next] = true
					frontier.append(next)
	else:
		warnings.append("基準の出現位置 %s (%s) が不正または通行不可です。到達探索を省略しました。" % [base_id, str(base)])
	for item in important:
		if not item.cell is Vector2i or not map.is_walkable(item.cell):
			warnings.append("%s %s: 範囲外または通行不可です。" % [item.label, str(item.cell)])
		elif not visited.is_empty() and not visited.has(item.cell):
			warnings.append("%s %s: 基準の出現位置から到達できません。" % [item.label, str(item.cell)])
	if include_npcs and not map.npcs.is_empty() and base is Vector2i and map.is_walkable(base):
		var occupied: Dictionary = {}
		for npc in map.npcs:
			if npc != null and map.is_walkable(npc.cell):
				occupied[npc.cell] = true
		var open_cells: Dictionary = {}
		var queue: Array[Vector2i] = [base]
		if not occupied.has(base):
			open_cells[base] = true
		var cursor := 0
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + direction
				if map.is_walkable(next) and not occupied.has(next) and not open_cells.has(next):
					open_cells[next] = true
					queue.append(next)
		for item in important:
			if item.cell is Vector2i and visited.has(item.cell) and not open_cells.has(item.cell):
				warnings.append("NPCの配置で %s %s への通路が塞がる可能性があります。" % [item.label, str(item.cell)])
		for npc in map.npcs:
			if npc == null or not map.is_walkable(npc.cell):
				continue
			var can_talk := false
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				can_talk = can_talk or open_cells.has(npc.cell + direction)
			if not can_talk:
				warnings.append("NPC %s に話しかける位置へ到達できません。" % npc.id)
	if map.encounters_enabled:
		if map.enemies.is_empty():
			warnings.append("遭遇が有効ですが、敵候補がありません。")
		for enemy in map.enemies:
			if enemy == null or enemy.texture == null or enemy.max_hp <= 0 or enemy.attack_min < 0 or enemy.attack_max < enemy.attack_min:
				warnings.append("遭遇の敵候補に無効なデータがあります。")
	return {"errors": errors, "warnings": warnings}

static func npc_placement_issue(map: MapData, cell: Vector2i, occupied: Dictionary = {}) -> String:
	if not map.is_walkable(cell):
		return "範囲外または通行不可です。"
	if occupied.has(cell):
		return "別のNPCと重なっています。"
	for spawn in map.spawns.values():
		if spawn is Vector2i and spawn == cell:
			return "出現位置と重なっています。"
	for portal in map.portals:
		if portal.get("cell") is Vector2i and portal.get("cell") == cell:
			return "出入口と重なっています。"
	if map.healing_cells.has(cell):
		return "回復地点と重なっています。"
	return ""
