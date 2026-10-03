class_name Exploration
extends Node2D

var map: MapController
var player: Player
var camera: Camera2D
var arena: BattleArena
var saved_collision_mask: int = 1
var last_healing_cell := Vector2i(-999, -999)
var camera_return_start := Vector2.ZERO
var camera_return_progress := 1.0
var camera_return_distance := 1.0
var npcs: Array[Npc] = []
var overlap_exceptions: Array[Npc] = []
const TALK_RADIUS_TILES := 1.25
const TALK_DOT := 0.5

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
	for npc in npcs:
		if is_instance_valid(npc):
			player.remove_collision_exception_with(npc)
			remove_child(npc)
			npc.queue_free()
	npcs.clear()
	overlap_exceptions.clear()
	map.load_map(map_data, config.tile_size)
	player.position = point
	player.z_index = roundi(point.y)
	player.velocity = Vector2.ZERO
	last_healing_cell = Vector2i(-999, -999)
	camera.position = Vector2.ZERO
	camera_return_progress = 1.0
	camera.reset_smoothing()
	camera.force_update_scroll()
	var accepted: Dictionary = {}
	var accepted_ids: Dictionary = {}
	var sorted: Array[NpcData] = map_data.npcs.duplicate()
	sorted.sort_custom(func(a: NpcData, b: NpcData):
		if a == null:
			return false
		if b == null:
			return true
		return a.id < b.id
	)
	for npc_data in sorted:
		if npc_data == null:
			push_warning("空のNPCを生成しません: " + map_data.id)
			continue
		if npc_data.id.strip_edges().is_empty() or accepted_ids.has(npc_data.id) or npc_data.texture == null:
			push_warning("NPC %s を生成しません: IDまたは画像が無効です。" % npc_data.id)
			continue
		var issue := MapValidator.npc_placement_issue(map_data, npc_data.cell, accepted)
		if not issue.is_empty():
			push_warning("NPC %s を生成しません: %s" % [npc_data.id, issue])
			continue
		accepted[npc_data.cell] = true
		accepted_ids[npc_data.id] = true
		var npc := Npc.new()
		add_child(npc)
		npc.setup(npc_data, config.tile_size)
		npcs.append(npc)

func step(delta: float, move_speed: float) -> float:
	_release_overlap_exceptions()
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var distance := player.move_player(direction, move_speed, delta)
	if not arena.active and distance > 0.01 and camera_return_progress < 1.0:
		# 実際に歩いた距離だけ進め、停止中や壁にぶつかった間は画面を動かさない。
		camera_return_progress = minf(1.0, camera_return_progress + distance / camera_return_distance)
		camera.position = camera_return_start * (1.0 - smoothstep(0.0, 1.0, camera_return_progress))
		camera.force_update_scroll()
	return distance

func talk_target() -> Npc:
	if map == null or map.data == null:
		return null
	var options: Array[Npc] = []
	for npc in npcs:
		var offset := npc.position - player.position
		if offset.length() > map.tile_size * TALK_RADIUS_TILES or offset.is_zero_approx():
			continue
		if player.facing.normalized().dot(offset.normalized()) < TALK_DOT:
			continue
		var query := PhysicsRayQueryParameters2D.create(player.global_position, npc.global_position, 1, [player.get_rid(), npc.get_rid()])
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		options.append(npc)
	options.sort_custom(func(a: Npc, b: Npc):
		var da := player.position.distance_squared_to(a.position)
		var db := player.position.distance_squared_to(b.position)
		return a.data.id < b.data.id if is_equal_approx(da, db) else da < db
	)
	return options[0] if not options.is_empty() else null

func begin_battle(foe: EnemyData) -> void:
	camera_return_progress = 1.0
	camera.reparent(self, true)
	camera.force_update_scroll()
	arena.begin(foe)
	saved_collision_mask = player.collision_mask
	player.collision_mask = BattleArena.BATTLE_LAYER

func end_battle() -> void:
	arena.end()
	player.collision_mask = saved_collision_mask
	for npc in npcs:
		if _overlaps_npc(npc):
			player.add_collision_exception_with(npc)
			overlap_exceptions.append(npc)
	player.velocity = Vector2.ZERO
	camera.reparent(player, true)
	camera_return_start = camera.position
	camera_return_progress = 0.0 if not camera_return_start.is_zero_approx() else 1.0
	# 補間の始点・終点で速度を滑らかにし、移動距離が十分なら必ず基準位置に着く。
	camera_return_distance = maxf(map.tile_size * 4.0, camera_return_start.length() * 1.5)
	camera.force_update_scroll()

func _release_overlap_exceptions() -> void:
	for npc in overlap_exceptions.duplicate():
		if not is_instance_valid(npc) or not _overlaps_npc(npc, 3.0):
			if is_instance_valid(npc):
				player.remove_collision_exception_with(npc)
			overlap_exceptions.erase(npc)

func _overlaps_npc(npc: Npc, margin: float = 0.0) -> bool:
	var offset := player.position - npc.position
	var nearest := Vector2(clampf(offset.x, -Npc.HALF_COLLISION.x, Npc.HALF_COLLISION.x), clampf(offset.y, -Npc.HALF_COLLISION.y, Npc.HALF_COLLISION.y))
	return offset.distance_squared_to(nearest) <= pow(Player.COLLISION_RADIUS + margin, 2.0)

func newly_healing() -> bool:
	var cell := map.data.cell_at(player.position, map.tile_size)
	if not map.data.healing_cells.has(cell):
		last_healing_cell = Vector2i(-999, -999)
		return false
	if last_healing_cell == cell:
		return false
	last_healing_cell = cell
	return true
