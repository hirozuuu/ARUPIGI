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
var map_name: String = ""
var selected: int = 0
var notice: String = ""
var enemy: EnemyData
var enemy_hp: int = 0
var battle_text: String = ""
var battle_phase: String = "command"
var flash: float = 0.0
var fade: float = 0.0
var battle_rect: Rect2

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	if screen == "battle":
		_draw_battle()
	else:
		draw_set_transform(Vector2.ZERO, 0, size / Vector2(960, 640))
		panel(Rect2(22, 20, 240, 87))
		text_at(map_name, Vector2(40, 53), 22)
		text_at("旅人  HP  %02d / %02d" % [hp, max_hp], Vector2(40, 84), 20, GOLD)
		panel(Rect2(730, 22, 208, 48))
		text_at("Esc  旅のメニュー", Vector2(747, 54), 19)
		if not notice.is_empty():
			panel(Rect2(150, 536, 660, 66))
			centered(notice, 578, 21)
		else:
			panel(Rect2(224, 570, 512, 46))
			centered("WASD / 矢印  移動     印を踏むと出入り・回復", 600, 18, MUTED)
		if screen == "menu":
			draw_rect(Rect2(0, 0, 960, 640), Color(0.035, 0.06, 0.07, 0.76))
			panel(Rect2(214, 100, 532, 380))
			text_at("旅のメニュー", Vector2(255, 156), 30)
			text_at("旅人   HP  %d / %d" % [hp, max_hp], Vector2(255, 204), 24, GOLD)
			draw_line(Vector2(255, 227), Vector2(705, 227), MUTED, 1)
			text_at("WASD / 矢印キー ： 歩く・戦闘の行動を選ぶ", Vector2(255, 266), 20)
			text_at("Enter ： 決定     Esc ： メニューを閉じる", Vector2(255, 302), 20)
			text_at("町の泉の印で回復。セーブ機能はありません。", Vector2(255, 343), 18, MUTED)
			option("ゲームに戻る", 264, 410, 0)
	if fade > 0:
		draw_rect(Rect2(0, 0, 960, 640), Color(0.035, 0.05, 0.065, fade))

func _draw_battle() -> void:
	var r := battle_rect
	var shade := Color(0.035, 0.06, 0.07, 0.62)
	draw_rect(Rect2(0, 0, size.x, maxf(0.0, r.position.y)), shade)
	draw_rect(Rect2(0, r.end.y, size.x, maxf(0.0, size.y - r.end.y)), shade)
	draw_rect(Rect2(0, r.position.y, maxf(0.0, r.position.x), r.size.y), shade)
	draw_rect(Rect2(r.end.x, r.position.y, maxf(0.0, size.x - r.end.x), r.size.y), shade)
	var scale_factor := minf(size.x / 960.0, size.y / 640.0)
	draw_rect(r, PAPER, false, maxf(2.0, 3.0 * scale_factor))
	var origin := Vector2((size.x - 960.0 * scale_factor) * 0.5, 0.0)
	draw_set_transform(origin, 0.0, Vector2.ONE * scale_factor)
	panel(Rect2(28, 24, 240, 75))
	text_at("旅人  HP  %02d / %02d" % [hp, max_hp], Vector2(45, 71), 22, GOLD)
	if enemy != null:
		draw_rect(Rect2(382, 43, 196, 43), Color(0.035, 0.06, 0.07, 0.72))
		centered(enemy.display_name, 79, 25)
	panel(Rect2(28, 440, 272, 172))
	option("こうげき", 55, 492, 0)
	option("にげる", 55, 538, 1)
	text_at("WASD / 矢印  移動・上下で選択", Vector2(48, 575), 15, MUTED)
	text_at("Enter  決定", Vector2(80, 599), 16, MUTED)
	panel(Rect2(319, 440, 613, 172))
	text_at(battle_text, Vector2(344, 482), 22)
	if battle_phase == "result":
		text_at("Enter を押して旅に戻る  ▸", Vector2(565, 588), 19, GOLD)
	elif battle_phase == "command":
		text_at("行動を選んでください", Vector2(344, 588), 19, MUTED)
