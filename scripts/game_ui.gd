class_name GameUI
extends Control

const PAPER := Color("efe5cb")
const INK := Color("172d32")
const MUTED := Color("afb9ac")
const GOLD := Color("edc77d")
var font: Font = preload("res://assets/fonts/ui_font.tres")
var screen: String = "exploration"
var hp: int = 30
var max_hp: int = 30
var level: int = 1
var experience: int = 0
var next_level_experience: int = 10
var selected: int = 0
var notice: String = ""
var battle_text: String = ""
var battle_phase: String = "command"
var flash: float = 0.0
var fade: float = 0.0
var battle_rect: Rect2
var battle_boundary_visible := true
var talk_available := false
var dialogue_view: DialogueView

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_view = DialogueView.new()
	add_child(dialogue_view)
	dialogue_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_view.visible = false

func text_at(value: String, point: Vector2, size_px: int = 22, color: Color = PAPER) -> void:
	var line_index := 0
	for line in value.split("\n"):
		draw_string(font, point + Vector2(0, line_index * (size_px + 12)), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
		line_index += 1

func centered(value: String, y: float, size_px: int, color: Color = PAPER) -> void:
	text_at(value, Vector2((960.0 - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x) / 2.0, y), size_px, color)

func panel(rect: Rect2, color: Color = INK) -> void:
	draw_style_box(_panel_style(color), rect)
	var r := rect.grow(-6)
	draw_polyline(PackedVector2Array([r.position + Vector2(1, 2), Vector2(r.end.x - 2, r.position.y), r.end + Vector2(0, -1), Vector2(r.position.x - 1, r.end.y), r.position + Vector2(1, 2)]), Color("929d89"), 1.0, true)

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = PAPER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style

func option(value: String, x: float, y: float, index: int) -> void:
	if selected == index:
		draw_colored_polygon(PackedVector2Array([Vector2(x, y - 15), Vector2(x + 11, y - 8), Vector2(x, y - 1)]), GOLD)
	text_at(value, Vector2(x + 25, y), 24, GOLD if selected == index else PAPER)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(960, 640))
	if screen == "battle":
		_draw_battle()
	elif screen == "menu":
		draw_rect(Rect2(0, 0, 960, 640), Color(0.035, 0.06, 0.07, 0.76))
		panel(Rect2(260, 154, 440, 332))
		text_at("旅のメニュー", Vector2(300, 210), 30)
		text_at("HP  %02d / %02d" % [hp, max_hp], Vector2(300, 258), 24, GOLD)
		text_at("Lv. %d" % level, Vector2(300, 298), 24, GOLD)
		text_at(_experience_text(), Vector2(300, 332), 22)
		draw_line(Vector2(300, 358), Vector2(660, 358), MUTED, 1)
		option("ゲームに戻る", 310, 420, 0)
	elif screen == "exploration":
		_draw_status()
		if talk_available:
			panel(Rect2(215, 556, 530, 60))
			centered("Enter  話す", 594, 21, GOLD)
		elif not notice.is_empty():
			panel(Rect2(150, 536, 660, 66))
			centered(notice, 578, 21)
	if fade > 0:
		draw_rect(Rect2(0, 0, 960, 640), Color(0.035, 0.05, 0.065, fade))

func _experience_text() -> String:
	if next_level_experience == 0:
		return "EXP %d（MAX）" % experience
	return "EXP %d / %d" % [experience, next_level_experience]


func _draw_status() -> void:
	panel(Rect2(28, 24, 236, 118))
	text_at("HP  %02d / %02d" % [hp, max_hp], Vector2(45, 60), 22, GOLD)
	text_at("Lv. %d" % level, Vector2(45, 89), 20, GOLD)
	text_at(_experience_text(), Vector2(45, 118), 18)


func _draw_battle() -> void:
	var r := battle_rect
	var shade := Color(0.035, 0.06, 0.07, 0.62)
	draw_rect(Rect2(0, 0, size.x, maxf(0.0, r.position.y)), shade)
	draw_rect(Rect2(0, r.end.y, size.x, maxf(0.0, size.y - r.end.y)), shade)
	draw_rect(Rect2(0, r.position.y, maxf(0.0, r.position.x), r.size.y), shade)
	draw_rect(Rect2(r.end.x, r.position.y, maxf(0.0, size.x - r.end.x), r.size.y), shade)
	if battle_boundary_visible:
		draw_rect(r, PAPER, false, 3.0)
	_draw_status()
	if battle_phase == "command":
		panel(Rect2(28, 440, 272, 130))
		option("こうげき", 55, 492, 0)
		option("にげる", 55, 538, 1)
		panel(Rect2(319, 440, 613, 130))
		text_at(battle_text, Vector2(344, 482), 22)
	else:
		panel(Rect2(28, 440, 904, 130))
		text_at(battle_text, Vector2(53, 482), 22)
