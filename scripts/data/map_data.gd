@tool
class_name MapData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var width: int = 0
@export var height: int = 0
# Keep a packed default: editor placeholders otherwise discard rows during export.
@export var rows: PackedStringArray = PackedStringArray()
@export var terrains: Dictionary = {}
@export var spawns: Dictionary = {}
@export var portals: Array[Dictionary] = []
@export var healing_cells: Array[Vector2i] = []
@export var encounters_enabled: bool = false
@export var enemies: Array[EnemyData] = []
@export var npcs: Array[NpcData] = []


func cell_at(position: Vector2, tile_size: int) -> Vector2i:
	return Vector2i(floori(position.x / tile_size), floori(position.y / tile_size))


func is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	if cell.y >= rows.size() or cell.x >= rows[cell.y].length():
		return false
	var terrain := terrains.get(rows[cell.y][cell.x]) as TerrainData
	return terrain != null and terrain.walkable


func spawn_position(spawn_id: String, tile_size: int) -> Vector2:
	assert(spawns.has(spawn_id), "Unknown spawn '%s' on map '%s'" % [spawn_id, id])
	var cell: Vector2i = spawns.get(spawn_id, Vector2i.ZERO)
	return (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size
