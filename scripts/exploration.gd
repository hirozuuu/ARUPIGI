class_name Exploration
extends Node2D

var map: MapController
var player: Player
var camera: Camera2D
var arena: BattleArena
var saved_collision_mask: int = 1
var last_healing_cell := Vector2i(-999, -999)

func _ready() -> void:
	map = MapController.new()
	add_child(map)
	arena = BattleArena.new()
	add_child(arena)
	player = Player.new()
	add_child(player)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	player.add_child(camera)

func enter(map_data: MapData, point: Vector2, config: GameConfig) -> void:
	map.load_map(map_data, config.tile_size)
	player.position = point
	player.velocity = Vector2.ZERO
	last_healing_cell = Vector2i(-999, -999)
	camera.reset_smoothing()
	camera.force_update_scroll()

func step(delta: float, config: GameConfig) -> float:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return player.move_player(direction, config.move_speed, delta)

func begin_battle(foe: EnemyData, view_size: Vector2) -> void:
	camera.reparent(self, true)
	camera.force_update_scroll()
	arena.begin(foe, camera, view_size)
	saved_collision_mask = player.collision_mask
	player.collision_mask = BattleArena.BATTLE_LAYER

func battle_step(delta: float, config: GameConfig) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.move_player(direction, config.move_speed, delta)

func end_battle() -> void:
	arena.end()
	player.collision_mask = saved_collision_mask
	player.velocity = Vector2.ZERO
	camera.reparent(player, false)
	camera.position = Vector2.ZERO
	camera.zoom = arena.initial_zoom
	camera.force_update_scroll()

func newly_healing() -> bool:
	var cell := map.data.cell_at(player.position, map.tile_size)
	if not map.data.healing_cells.has(cell):
		last_healing_cell = Vector2i(-999, -999)
		return false
	if last_healing_cell == cell:
		return false
	last_healing_cell = cell
	return true
