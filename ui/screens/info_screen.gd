extends Screen
## A screen of plain text, for places that do not do anything yet.

var _lines: Array


func _init(p_title: String, p_subtitle: String, lines: Array) -> void:
	title = p_title
	subtitle = p_subtitle
	_lines = lines


func _fill() -> void:
	for l: Array in _lines:
		add_row(l[0], l[1])
