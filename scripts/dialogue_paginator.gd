@tool
class_name DialoguePaginator
extends RefCounted

const CLOSING := "、。，．！？!?,.;:：；」』】）》）］｝ぁぃぅぇぉゃゅょっー"
const OPENING := "「『【《（［｛"

static func paginate(value: String, font: Font, size_px: int, width: float) -> Array[String]:
	var lines: Array[String] = []
	for paragraph in value.replace("\r\n", "\n").split("\n", true):
		if paragraph.is_empty():
			lines.append("")
			continue
		var line := ""
		for i in paragraph.length():
			var char := paragraph.substr(i, 1)
			if not line.is_empty() and font.get_string_size(line + char, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > width:
				# Prefer keeping punctuation off the next line without exceeding the frame.
				if CLOSING.contains(char) and line.length() > 1:
					var moved := line.substr(line.length() - 1)
					line = line.substr(0, line.length() - 1)
					lines.append(line)
					line = moved
				elif OPENING.contains(line.substr(line.length() - 1)) and line.length() > 1:
					var moved := line.substr(line.length() - 1)
					lines.append(line.substr(0, line.length() - 1))
					line = moved
				else:
					lines.append(line)
					line = ""
			line += char
		lines.append(line)
	while lines.size() > 1 and lines[-1].is_empty():
		lines.pop_back()
	var pages: Array[String] = []
	for i in range(0, lines.size(), 2):
		pages.append("\n".join(lines.slice(i, mini(i + 2, lines.size()))))
	if pages.is_empty():
		pages.append("")
	return pages
