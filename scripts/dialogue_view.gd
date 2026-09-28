@tool
class_name DialogueView
extends Control

const PAPER := Color("efe5cb")
const INK := Color("172d32")
const GOLD := Color("edc77d")
const MUTED := Color("afb9ac")
const CHOICE_ROWS := 7
var font: Font = preload("res://assets/fonts/ui_font.tres")
var model: DialogueModel
var speaker: String = ""
var choice_scroll: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if focus_mode == Control.FOCUS_NONE else Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(480, 320)

func set_content(value: DialogueModel, name: String) -> void:
	model = value
	speaker = name
	choice_scroll = 0
	queue_redraw()

func sync_selection() -> void:
	if model == null or not model.choices_visible():
		return
	var start := 0
	for i in model.choice_index:
		start += _choice_lines(model.current.choices[i].text).size()
	var end := start + _choice_lines(model.current.choices[model.choice_index].text).size()
	var total := 0
	for choice in model.current.choices:
		total += _choice_lines(choice.text).size()
	if start < choice_scroll:
		choice_scroll = start
	elif end > choice_scroll + CHOICE_ROWS:
		choice_scroll = mini(start, end - CHOICE_ROWS)
	choice_scroll = clampi(choice_scroll, 0, maxi(0, total - CHOICE_ROWS))
	queue_redraw()

func scroll_choices(lines: int) -> void:
	if model == null or not model.choices_visible():
		return
	var total := 0
	for choice in model.current.choices:
		total += _choice_lines(choice.text).size()
	choice_scroll = clampi(choice_scroll + lines, 0, maxi(0, total - CHOICE_ROWS))
	queue_redraw()

func _choice_lines(value: String) -> Array[String]:
	return DialoguePaginator.wrap_lines(value, font, 19, 304)

func _panel(rect: Rect2) -> void:
	draw_rect(rect, INK)
	draw_rect(rect, PAPER, false, 2)

func _draw() -> void:
	if model == null or model.current == null:
		return
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(960, 640))
	_panel(Rect2(45, 395, 870, 195))
	_panel(Rect2(56, 346, 370, 48))
	var name := speaker
	while name.length() > 1 and font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x > 334:
		name = name.substr(0, name.length() - 2) + "…"
	draw_string(font, Vector2(74, 378), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GOLD)
	var lines := model.pages[model.page_index].split("\n", true)
	for i in mini(lines.size(), 2):
		draw_string(font, Vector2(70, 448 + i * 43), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, PAPER)
	var page_info := "%d / %d" % [model.page_index + 1, model.pages.size()]
	draw_string(font, Vector2(70, 566), page_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)
	draw_string(font, Vector2(652, 566), "↑↓ 選択  Enter 決定" if model.choices_visible() else "Enter 次へ ▸", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GOLD)
	if model.choices_visible():
		_draw_choices()

func _draw_choices() -> void:
	_panel(Rect2(490, 113, 425, 269))
	draw_string(font, Vector2(510, 143), "選択してください", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MUTED)
	var row := 0
	var total := 0
	for index in model.current.choices.size():
		var lines := _choice_lines(model.current.choices[index].text)
		for line_index in lines.size():
			if row >= choice_scroll and row < choice_scroll + CHOICE_ROWS:
				var y := 172 + (row - choice_scroll) * 28
				if index == model.choice_index and line_index == 0:
					draw_string(font, Vector2(505, y), "▸", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)
				draw_string(font, Vector2(532, y), lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, GOLD if index == model.choice_index else PAPER)
			row += 1
		total += lines.size()
	if choice_scroll > 0:
		draw_string(font, Vector2(875, 143), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
	if choice_scroll + CHOICE_ROWS < total:
		draw_string(font, Vector2(875, 368), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
