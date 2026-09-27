class_name Npc
extends StaticBody2D

const HALF_COLLISION := Vector2(12, 9)

var data: NpcData
var art: Sprite2D

func setup(source: NpcData, tile_size: int) -> void:
	data = source
	position = (Vector2(source.cell) + Vector2.ONE * 0.5) * tile_size
	z_index = roundi(position.y)
	collision_layer = 1
	collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = HALF_COLLISION * 2.0
	collision.shape = shape
	add_child(collision)
	art = Sprite2D.new()
	art.texture = source.texture
	art.modulate = source.tint
	art.position = Vector2(0, -15)
	add_child(art)
