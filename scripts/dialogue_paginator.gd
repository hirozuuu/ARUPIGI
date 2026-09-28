@tool
class_name DialoguePaginator
extends RefCounted

const CLOSING := "、。，．！？!?,.;:：；」』】）》）］｝ぁぃぅぇぉゃゅょっー"
const OPENING := "「『【《（［｛"

static func paginate(value: String, font: Font, size_px: int, width: float) -> Array[String]:
	var lines := wrap_lines(value, font, size_px, width)
	var pages: Array[String] = []
	for i in range(0, lines.size(), 2):
		pages.append("\n".join(lines.slice(i, mini(i + 2, lines.size()))))
	return pages

static func wrap_lines(value: String, font: Font, size_px: int, width: float) -> Array[String]:
	var lines: Array[String] = []
	for paragraph in value.replace("\r\n", "\n").split("\n", true):
		if paragraph.is_empty():
			lines.append("")
			continue
		var start := 0
		while start < paragraph.length():
			var end := start + 1
			while end < paragraph.length() and font.get_string_size(paragraph.substr(start, end - start + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= width:
				end += 1
			if end < paragraph.length():
				var boundary := end
				while boundary > start and (OPENING.contains(paragraph[boundary - 1]) or CLOSING.contains(paragraph[boundary])):
					boundary -= 1
				# 禁則を満たせない連続記号でも、空行や幅超過を作らず前へ進む。
				if boundary > start:
					end = boundary
			lines.append(paragraph.substr(start, end - start))
			start = end
	while lines.size() > 1 and lines[-1].is_empty():
		lines.pop_back()
	return lines
