class_name BattleArena
extends Node2D
## One fixed world-space arena shared by the physics bodies and the overlay.

const BASE_RECT := Rect2(280.0, 20.0, 400.0, 400.0)
const BASE_ENEMY_CENTER := Vector2(480.0, 150.0)
const BASE_ENEMY_SIZE := 96.0
const BATTLE_LAYER := 2

var world_rect: Rect2
var enemy_rect: Rect2
var walls: Array[StaticBody2D] = []
var enemy_body: StaticBody2D
var enemy_art: Sprite2D
var active := false

func _ready() -> void:
	visible = false
	for side in 4:
		var wall := StaticBody2D.new()
		wall.collision_layer = 0
		wall.collision_mask = 0
		var collision := CollisionShape2D.new()
		collision.shape = RectangleShape2D.new()
		wall.add_child(collision)
		add_child(wall)
		walls.append(wall)
	enemy_body = StaticBody2D.new()
	enemy_body.collision_layer = 0
	enemy_body.collision_mask = 0
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	enemy_body.add_child(collision)
	add_child(enemy_body)
	enemy_art = Sprite2D.new()
	enemy_body.add_child(enemy_art)

func begin(foe: EnemyData) -> void:
	# canvas_items + keep が960×640の論理画面全体を等方的に拡縮する。
	# ウィンドウのリサイズではワールド座標やカメラ倍率を変更しない。
	var screen_enemy := Rect2(BASE_ENEMY_CENTER - Vector2.ONE * BASE_ENEMY_SIZE * 0.5, Vector2.ONE * BASE_ENEMY_SIZE)
	var inverse := get_global_transform_with_canvas().affine_inverse()
	world_rect = Rect2(inverse * BASE_RECT.position, inverse * BASE_RECT.end - inverse * BASE_RECT.position)
	enemy_rect = Rect2(inverse * screen_enemy.position, inverse * screen_enemy.end - inverse * screen_enemy.position)
	# Place thin walls just outside the visible square, so the player's foot circle
	# can touch the line without crossing it.
	var t := maxf(1.0, world_rect.size.x / 200.0)
	_set_wall(0, Vector2(world_rect.position.x - t * 0.5, world_rect.get_center().y), Vector2(t, world_rect.size.y + 2.0 * t))
	_set_wall(1, Vector2(world_rect.end.x + t * 0.5, world_rect.get_center().y), Vector2(t, world_rect.size.y + 2.0 * t))
	_set_wall(2, Vector2(world_rect.get_center().x, world_rect.position.y - t * 0.5), Vector2(world_rect.size.x + 2.0 * t, t))
	_set_wall(3, Vector2(world_rect.get_center().x, world_rect.end.y + t * 0.5), Vector2(world_rect.size.x + 2.0 * t, t))
	enemy_body.position = enemy_rect.get_center()
	(enemy_body.get_child(0) as CollisionShape2D).shape.size = enemy_rect.size
	enemy_art.texture = foe.texture
	var texture_size := enemy_art.texture.get_size()
	enemy_art.scale = Vector2.ONE * minf(enemy_rect.size.x / texture_size.x, enemy_rect.size.y / texture_size.y)
	enemy_art.modulate = Color.WHITE
	active = true
	visible = true
	for wall in walls:
		wall.collision_layer = BATTLE_LAYER
	set_enemy_active(true)

func _set_wall(index: int, center: Vector2, shape_size: Vector2) -> void:
	walls[index].position = center
	(walls[index].get_child(0) as CollisionShape2D).shape.size = shape_size

func set_enemy_active(enabled: bool) -> void:
	enemy_art.visible = enabled and active
	enemy_body.collision_layer = BATTLE_LAYER if enabled and active else 0

func end() -> void:
	active = false
	visible = false
	for wall in walls:
		wall.collision_layer = 0
	set_enemy_active(false)

func screen_rect() -> Rect2:
	var transform := get_global_transform_with_canvas()
	return Rect2(transform * world_rect.position, transform * world_rect.end - transform * world_rect.position)
