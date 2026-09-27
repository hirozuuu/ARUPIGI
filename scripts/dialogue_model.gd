@tool
class_name DialogueModel
extends RefCounted

var data: DialogueData
var current: DialogueNodeData
var page_index: int = 0
var choice_index: int = 0
var pages: Array[String] = []
var font: Font
var font_size: int = 23
var text_width: float = 820.0

func start(source: DialogueData, display_font: Font, width: float = 820.0, size_px: int = 23) -> bool:
	if not DialogueValidator.validate(source).errors.is_empty():
		return false
	data = source
	font = display_font
	text_width = width
	font_size = size_px
	return _enter(data.start_node_id)

func _enter(id: String) -> bool:
	if id.is_empty():
		current = null
		pages.clear()
		return false
	for node in data.nodes:
		if node != null and node.id == id:
			current = node
			page_index = 0
			choice_index = 0
			pages = DialoguePaginator.paginate(node.text, font, font_size, text_width)
			return true
	push_warning("会話の移動先がありません: " + id)
	current = null
	return false

func choices_visible() -> bool:
	return current != null and page_index == pages.size() - 1 and not current.choices.is_empty()

func select(delta: int) -> void:
	if choices_visible():
		choice_index = clampi(choice_index + delta, 0, current.choices.size() - 1)

func confirm() -> bool:
	if current == null:
		return false
	if page_index + 1 < pages.size():
		page_index += 1
		return true
	if not current.choices.is_empty():
		return _enter(current.choices[choice_index].next_node_id)
	return _enter(current.next_node_id)
