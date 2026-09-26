class_name MapController
extends Node2D

var data: MapData
var tile_size: int = 48
var markers: Dictionary = {}

func load_map(map_data: MapData, size: int) -> void:
	data = map_data
	tile_size = size
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for y in range(-1, data.height + 1):
		for x in range(-1, data.width + 1):
			if not data.is_walkable(Vector2i(x, y)):
				var body := StaticBody2D.new()
				body.collision_layer = 1
				body.collision_mask = 0
				var collision := CollisionShape2D.new()
				var shape := RectangleShape2D.new()
				shape.size = Vector2.ONE * tile_size
				collision.shape = shape
				body.position = (Vector2(x, y) + Vector2.ONE * 0.5) * tile_size
				body.add_child(collision)
				add_child(body)
	for kind in ["town", "dungeon", "exit", "heal"]:
		markers[kind] = load("res://assets/art/%s_marker.svg" % kind)
	queue_redraw()

func trigger_at(point: Vector2) -> Dictionary:
	var cell := data.cell_at(point, tile_size)
	for portal in data.portals:
		if portal.cell == cell:
			return portal
	return {}

func _draw() -> void:
	if data == null:
		return
	for y in data.height:
		for x in data.width:
			var terrain: TerrainData = data.terrains[data.rows[y].substr(x, 1)]
			draw_texture_rect(terrain.texture, Rect2(Vector2(x, y) * tile_size, Vector2.ONE * tile_size), false)
	for portal in data.portals:
		var kind: String = portal.target_map if data.id == "world" else "exit"
		draw_texture_rect(markers[kind], Rect2(Vector2(portal.cell) * tile_size, Vector2.ONE * tile_size), false)
	for cell in data.healing_cells:
		draw_texture_rect(markers.heal, Rect2(Vector2(cell) * tile_size, Vector2.ONE * tile_size), false)
