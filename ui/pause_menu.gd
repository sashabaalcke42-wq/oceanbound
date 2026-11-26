extends CanvasLayer
## The pause menu, on Esc: carry on, save, save and quit, start a new game
## or quit. The game stops while it is open.

signal resumed

var world: Node

var _status: Label
var _confirm_new: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.13, 0.17, 0.97)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = Vector2(380, 0)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 30)
	col.add_child(title)
	_button(col, "Continue", resume).grab_focus()
	_button(col, "Save game", func(): _save())
	_button(col, "Save and quit", func():
		if _save():
			get_tree().quit())
	_confirm_new = _button(col, "New game", _new_game)
	_button(col, "Quit without saving", func():
		world.set(&"skip_autosave", true)
		get_tree().quit())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.75, 0.9, 1.0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var hint := Label.new()
	hint.text = "Your game also saves itself when you close the window."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.6)
	col.add_child(hint)

	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_mouse"):
		get_viewport().set_input_as_handled()
		resume()


func resume() -> void:
	if is_queued_for_deletion():
		return
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()
	queue_free()


func _save() -> bool:
	var ok := SaveGame.save(world)
	_status.text = "Saved." if ok else "Could not save the game."
	return ok


## Asks once, then starts over.
func _new_game() -> void:
	if _confirm_new.text == "New game":
		_confirm_new.text = "Really start over? Click again"
		return
	SaveGame.delete()
	world.set(&"skip_autosave", true)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override(&"font_size", 18)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
