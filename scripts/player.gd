class_name Player
extends CharacterBody2D

var art: Sprite2D
var walk_time: float = 0.0
var facing := Vector2.DOWN

func _ready() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	collision.shape = shape
	add_child(collision)
	art = Sprite2D.new()
	art.texture = preload("res://assets/art/player.svg")
	art.position = Vector2(0, -15)
	add_child(art)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

func move_player(direction: Vector2, speed: float, delta: float) -> float:
	var before := position
	velocity = direction.limit_length(1.0) * speed
	move_and_slide()
	var distance := before.distance_to(position)
	if distance > 0.01:
		facing = direction
		walk_time += delta * 12.0
		art.position.y = -15.0 + sin(walk_time) * 2.0
		art.rotation = sin(walk_time) * 0.045
		if absf(direction.x) > 0.1:
			art.flip_h = direction.x < 0.0
		art.modulate = Color(0.86, 0.93, 1.0) if direction.y < -0.1 else Color.WHITE
	else:
		art.position.y = -15
		art.rotation = 0
	return distance
