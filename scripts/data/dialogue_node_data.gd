@tool
class_name DialogueNodeData
extends Resource

@export var id: String = ""
@export var editor_label: String = ""
@export_multiline var text: String = ""
@export var next_node_id: String = ""
@export var choices: Array[DialogueChoiceData] = []
