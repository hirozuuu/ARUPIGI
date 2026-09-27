@tool
class_name DialogueValidator
extends RefCounted

static func validate(data: DialogueData) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if data == null:
		return {"errors": PackedStringArray(["会話データがありません。"]), "warnings": warnings}
	var nodes: Dictionary = {}
	for node in data.nodes:
		if node == null:
			errors.append("本文Resourceがありません。")
			continue
		if node.id.strip_edges().is_empty() or nodes.has(node.id):
			errors.append("本文IDが空か重複しています: %s" % node.id)
		else:
			nodes[node.id] = node
		if node.text.strip_edges().is_empty():
			errors.append("本文 %s の文章が空です。" % node.id)
		if not node.choices.is_empty() and not node.next_node_id.is_empty():
			errors.append("本文 %s に通常の移動先と選択肢が同時にあります。" % node.id)
		for choice in node.choices:
			if choice == null or choice.text.strip_edges().is_empty():
				errors.append("本文 %s に空の選択肢があります。" % node.id)
	if data.start_node_id.is_empty() or not nodes.has(data.start_node_id):
		errors.append("開始本文がありません: %s" % data.start_node_id)
	for node in data.nodes:
		if node == null:
			continue
		for target in _targets(node):
			if not target.is_empty() and not nodes.has(target):
				errors.append("本文 %s の移動先 %s がありません。" % [node.id, target])
	if not errors.is_empty():
		return {"errors": errors, "warnings": warnings}
	var reachable: Dictionary = {}
	var pending: Array[String] = [data.start_node_id]
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if reachable.has(id):
			continue
		reachable[id] = true
		for target in _targets(nodes[id]):
			if not target.is_empty() and not reachable.has(target):
				pending.append(target)
	for id in nodes:
		if not reachable.has(id):
			warnings.append("本文 %s は開始位置から使われていません。" % id)
	# Fixed point: a reachable node is escapable if one edge ends or leads to an escapable node.
	var escapable: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		for id in reachable:
			if escapable.has(id):
				continue
			for target in _targets(nodes[id]):
				if target.is_empty() or escapable.has(target):
					escapable[id] = true
					changed = true
					break
	for id in reachable:
		if not escapable.has(id):
			errors.append("本文 %s から会話を終了できません。" % id)
	return {"errors": errors, "warnings": warnings}

static func _targets(node: DialogueNodeData) -> Array[String]:
	var result: Array[String] = []
	if node.choices.is_empty():
		result.append(node.next_node_id)
	else:
		for choice in node.choices:
			if choice != null:
				result.append(choice.next_node_id)
	return result
