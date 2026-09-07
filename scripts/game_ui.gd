class_name GameUI
extends Control

const PAPER := Color("efe5cb")
const INK := Color("172d32")
const MUTED := Color("afb9ac")
const GOLD := Color("edc77d")
var font: Font = preload("res://assets/fonts/ui_font.tres")
var screen: String = "title"
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
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(960, 640))
	if screen == "title":
		_draw_title()
	elif screen == "battle":
		_draw_battle()
	else:
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
			panel(Rect2(214, 100, 532, 440))
			text_at("旅のメニュー", Vector2(255, 156), 30)
			text_at("旅人   HP  %d / %d" % [hp, max_hp], Vector2(255, 204), 24, GOLD)
			draw_line(Vector2(255, 227), Vector2(705, 227), MUTED, 1)
			text_at("WASD / 矢印キー ： 歩く・項目を選ぶ", Vector2(255, 266), 20)
			text_at("Enter ： 決定     Esc ： メニューを閉じる", Vector2(255, 302), 20)
			text_at("町の泉の印で回復。セーブ機能はありません。", Vector2(255, 343), 18, MUTED)
			option("ゲームに戻る", 264, 410, 0)
			option("タイトルに戻る", 264, 462, 1)
	if fade > 0:
		draw_rect(Rect2(0, 0, 960, 640), Color(0.035, 0.05, 0.065, fade))

func _draw_title() -> void:
	draw_rect(Rect2(0, 0, 960, 640), PAPER)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 370), Vector2(160, 326), Vector2(350, 379), Vector2(540, 331), Vector2(790, 353), Vector2(960, 297), Vector2(960, 640), Vector2(0, 640)]), Color("b5c39e"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 476), Vector2(270, 401), Vector2(495, 470), Vector2(740, 403), Vector2(960, 450), Vector2(960, 640), Vector2(0, 640)]), Color("819c7b"))
	for i in 20:
		var x := float(i * 51 + 14)
		var y := float(435 + (i * 37) % 169)
		draw_polyline(PackedVector2Array([Vector2(x - 5, y - 8), Vector2(x, y), Vector2(x + 5, y - 12)]), Color("536d5c"), 2, true)
	centered("A  S M A L L  H A N D - D R A W N  A D V E N T U R E", 88, 16, Color("597263"))
	centered("ARUPIGI", 208, 82, INK)
	centered("あるぴぎ  ─  小さな旅のはじまり", 263, 24, INK)
	draw_polyline(PackedVector2Array([Vector2(325, 282), Vector2(480, 287), Vector2(635, 281)]), Color("947d55"), 2, true)
	draw_texture_rect(preload("res://assets/art/player.svg"), Rect2(448, 310, 64, 80), false)
	panel(Rect2(330, 410, 300, 85))
	option("はじめる", 393, 463, 0)
	centered("Enter  決定", 532, 20, INK)
	centered("草原を歩き、町で休み、岩の洞へ。", 590, 18, INK)

func _draw_battle() -> void:
	draw_rect(Rect2(0, 0, 960, 640), Color("263c40"))
	for i in 12:
		var x := float(i * 95 - 60)
		draw_polyline(PackedVector2Array([Vector2(x, 345), Vector2(x + 65, 250 + i % 3 * 19), Vector2(x + 136, 345)]), Color("53625d"), 2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 354), Vector2(210, 336), Vector2(490, 351), Vector2(730, 331), Vector2(960, 351), Vector2(960, 640), Vector2(0, 640)]), Color("657966"))
	panel(Rect2(28, 24, 258, 75))
	text_at("旅人   HP  %02d / %02d" % [hp, max_hp], Vector2(47, 71), 23, GOLD)
	text_at("小さな旅の戦い", Vector2(721, 64), 20, MUTED)
	if enemy != null:
		centered(enemy.display_name, 146, 28)
		draw_set_transform(Vector2.ZERO, 0, size / Vector2(960, 640))
		draw_style_box(_panel_style(Color("455d50")), Rect2(372, 353, 216, 16))
		var tint := Color(1.0, 0.6, 0.5) if flash > 0.0 else Color.WHITE
		if battle_phase != "result" or enemy_hp > 0:
			draw_texture_rect(enemy.texture, Rect2(370, 172, 220, 210), false, tint)
	panel(Rect2(28, 423, 272, 188))
	option("こうげき", 55, 484, 0)
	option("にげる", 55, 536, 1)
	text_at("Enter  決定", Vector2(80, 578), 17, MUTED)
	panel(Rect2(319, 423, 613, 188))
	text_at(battle_text, Vector2(344, 478), 23)
	if battle_phase == "result":
		text_at("Enter を押して旅に戻る  ▸", Vector2(565, 579), 20, GOLD)
	elif battle_phase == "command":
		text_at("行動を選んでください", Vector2(344, 572), 19, MUTED)
