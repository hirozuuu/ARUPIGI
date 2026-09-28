@tool
class_name NpcData
extends Resource

@export var id: String = ""
@export var cell: Vector2i = Vector2i.ZERO
@export var texture: Texture2D
@export var tint: Color = Color.WHITE
@export var dialogue: DialogueData
