class_name Screen
extends CanvasLayer
## Base for the full-screen menus opened from the world: shops, the fish
## market, the job board. Builds a centred panel with a title, a scrolling
## list and a footer; subclasses fill the list in `refresh()`.
## Esc or the Close button emits `closed` and frees the screen.

signal closed

var title := ""
var subtitle := ""

var _list: VBoxContainer
var _footer: Label
var _subtitle_label: Label


func _ready() -> void:
	layer = 5
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.13, 0.17, 0.96)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = Vector2(720, 520)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override(&"font_size", 28)
	col.add_child(t)
	_subtitle_label = Label.new()
	_subtitle_label.text = subtitle
	_subtitle_label.modulate = Color(0.8, 0.85, 0.9)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_list)

	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	_footer = Label.new()
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_footer)
	var close_btn := Button.new()
	close_btn.text = "Close (Esc)"
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)

	Economy.balance_changed.connect(_on_balance_changed)
	refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


## Rebuild the list. Subclasses add rows with `add_row()`.
func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_fill()
	_footer.text = "Money: $%d" % Economy.balance


func _fill() -> void:
	pass


func set_subtitle(text: String) -> void:
	_subtitle_label.text = text


## A row: a heading, smaller detail text, and buttons on the right.
## `buttons` is an array of [label, Callable, enabled].
func add_row(heading: String, detail: String, buttons: Array = []) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override(&"font_size", 18)
	text.add_child(h)
	if detail != "":
		var d := Label.new()
		d.text = detail
		d.modulate = Color(0.75, 0.8, 0.85)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(380, 0)
		text.add_child(d)
	row.add_child(text)
	for b: Array in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(96, 36)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.disabled = b.size() > 2 and not b[2]
		var cb: Callable = b[1]
		btn.pressed.connect(func(): cb.call(); refresh())
		row.add_child(btn)
	_list.add_child(row)
	_list.add_child(HSeparator.new())


func add_heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 20)
	l.modulate = Color(0.95, 0.85, 0.55)
	_list.add_child(l)


func _on_balance_changed(_b: int) -> void:
	if _footer:
		_footer.text = "Money: $%d" % Economy.balance
