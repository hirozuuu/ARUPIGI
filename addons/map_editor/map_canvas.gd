@tool
extends Control

signal cell_hovered(cell: Vector2i)
signal operation_failed(message: String)
signal npc_cell_clicked(cell: Vector2i, erase: bool)
const Document = preload("res://addons/map_editor/map_edit_document.gd")
var document: Document
var brush: TerrainData
var base_terrain: TerrainData
var erase_mode: bool = false
var npc_mode: bool = false
var selected_npc_id: String = ""
var tile_size: int = 48
var zoom: float = 1.0
var hover := Vector2i(-1, -1)
var _button: MouseButton = MOUSE_BUTTON_NONE
var _panning: bool = false
var _markers: Dictionary = {}

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for kind in ["town", "dungeon", "forest", "exit", "heal"]:
		_markers[kind] = load("res://assets/art/%s_marker.svg" % kind)
	get_window().focus_exited.connect(finish_stroke)
	mouse_exited.connect(func():
		hover = Vector2i(-1, -1)
		queue_redraw()
	)

func set_document(value: Document) -> void:
	finish_stroke()
	if document != null and document.changed.is_connected(queue_redraw):
		document.changed.disconnect(queue_redraw)
	document = value
	if document != null:
		document.changed.connect(queue_redraw)
	update_extent()

func update_extent() -> void:
	custom_minimum_size = Vector2(document.data.width, document.data.height) * tile_size * zoom if document != null and document.data != null else Vector2(1, 1)
	queue_redraw()

func cell_at_local(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / (tile_size * zoom)), floori(point.y / (tile_size * zoom)))

func finish_stroke() -> void:
	if document != null:
		document.end_stroke()
	_button = MOUSE_BUTTON_NONE
	_panning = false

func _input(event: InputEvent) -> void:
	# _input sees releases even when outside the canvas or its ScrollContainer.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == _button or event.button_index == MOUSE_BUTTON_MIDDLE:
			finish_stroke()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		finish_stroke()

func _gui_input(event: InputEvent) -> void:
	if document == null or document.data == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			grab_focus()
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				grab_focus()
				if npc_mode:
					npc_cell_clicked.emit(cell_at_local(event.position), erase_mode or event.button_index == MOUSE_BUTTON_RIGHT)
					accept_event()
					return
				var terrain := base_terrain if erase_mode or event.button_index == MOUSE_BUTTON_RIGHT else brush
				if document.begin_stroke(terrain):
					_button = event.button_index
					document.paint_to(cell_at_local(event.position))
				else:
					operation_failed.emit(document.last_error)
			else:
				finish_stroke()
			accept_event()
	if event is InputEventMouseMotion:
		if _panning and get_parent() is ScrollContainer:
			var scroll := get_parent() as ScrollContainer
			scroll.scroll_horizontal -= roundi(event.relative.x)
			scroll.scroll_vertical -= roundi(event.relative.y)
		hover = cell_at_local(event.position)
		cell_hovered.emit(hover)
		if _button != MOUSE_BUTTON_NONE:
			var visible_area: Rect2 = get_parent().get_global_rect() if get_parent() is Control else get_global_rect()
			var pointer: Vector2 = get_global_transform() * event.position
			document.paint_to(hover if visible_area.has_point(pointer) else Vector2i(-1, -1))
		queue_redraw()

func _draw() -> void:
	if document == null or document.data == null:
		return
	var map := document.data
	var side := tile_size * zoom
	# Bounds-safe even when malformed resources are opened for diagnosis.
	for y in mini(map.height, map.rows.size()):
		for x in mini(map.width, map.rows[y].length()):
			var rect := Rect2(Vector2(x, y) * side, Vector2.ONE * side)
			var terrain = map.terrains.get(map.rows[y][x])
			if terrain is TerrainData and terrain.texture != null:
				draw_texture_rect(terrain.texture, rect, false)
			else:
				draw_rect(rect, Color.MAGENTA)
	for x in maxi(map.width + 1, 0):
		draw_line(Vector2(x * side, 0), Vector2(x * side, map.height * side), Color(0, 0, 0, 0.22))
	for y in maxi(map.height + 1, 0):
		draw_line(Vector2(0, y * side), Vector2(map.width * side, y * side), Color(0, 0, 0, 0.22))
	for portal in map.portals:
		if portal.get("cell") is Vector2i:
			var kind: String = str(portal.get("target_map", "exit")) if map.id == "world" else "exit"
			draw_texture_rect(_markers.get(kind, _markers.get("exit")), Rect2(Vector2(portal.cell) * side, Vector2.ONE * side), false)
	for cell in map.healing_cells:
		draw_texture_rect(_markers.heal, Rect2(Vector2(cell) * side, Vector2.ONE * side), false)
	for spawn_id in map.spawns:
		var cell = map.spawns[spawn_id]
		if cell is Vector2i:
			var center := (Vector2(cell) + Vector2.ONE * 0.5) * side
			draw_circle(center, side * 0.27, Color(0.1, 0.3, 0.9, 0.7))
			draw_string(get_theme_default_font(), center + Vector2(-side * 0.2, 5), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, roundi(side * 0.4)), Color.WHITE)
	for npc in map.npcs:
		if npc == null or npc.texture == null:
			continue
		var rect := Rect2(Vector2(npc.cell) * side, Vector2.ONE * side)
		draw_texture_rect(npc.texture, rect, false, npc.tint)
		if npc.id == selected_npc_id:
			draw_rect(rect.grow(-2), Color.GOLD, false, 3.0)
	if document.in_bounds(hover):
		draw_rect(Rect2(Vector2(hover) * side, Vector2.ONE * side), Color.YELLOW, false, 2.0)
