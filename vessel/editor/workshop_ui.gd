extends Control
## Panels for the boat workshop: block palette, colours, live stats, the
## tutorial card, and save / load / launch. Built in code; reads from and
## calls into workshop.gd.

const DESIGN_DIR := "user://designs/"

var _build_btn: Button
var _delete_btn: Button
var workshop: Node

var _blocks_box: VBoxContainer
var _block_buttons := {}  # StringName -> Button
var _swatches: Array[Button] = []
var _stats: RichTextLabel
var _tutorial: Label
var _tutorial_panel: PanelContainer
var _name_edit: LineEdit
var _load_popup: PopupMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_left_panel()
	_build_right_panel()
	_build_tutorial_panel()
	_build_bottom_bar()
	Inventory.changed.connect(func(_id, _c): refresh())
	refresh()


func refresh() -> void:
	if workshop == null or _stats == null:
		return
	if _build_btn:
		var deleting: bool = workshop.get(&"delete_mode")
		_build_btn.set_pressed_no_signal(not deleting)
		_delete_btn.set_pressed_no_signal(deleting)
		_delete_btn.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.5) if deleting else Color(0.85, 0.85, 0.85))
	for id: StringName in _block_buttons:
		var def := BlockLibrary.get_block(id)
		var b: Button = _block_buttons[id]
		b.text = "%s   x%d" % [def.display_name, Inventory.count(id)]
		b.button_pressed = id == workshop.get(&"selected_block")
	for i in _swatches.size():
		_swatches[i].text = "[x]" if i == workshop.get(&"color_index") else ""
	_refresh_stats()
	var t: String = workshop.call(&"tutorial_text")
	_tutorial_panel.visible = t != ""
	_tutorial.text = t
	var design: VesselDesign = workshop.get(&"editor").design
	if not _name_edit.has_focus():
		_name_edit.text = design.design_name


func _refresh_stats() -> void:
	var a: Dictionary = workshop.call(&"analysis")
	var lines: PackedStringArray = []
	var design: VesselDesign = workshop.get(&"editor").design
	lines.append("[b]%s[/b]" % design.design_name)
	lines.append("%d blocks" % design.blocks.size())
	var st: Dictionary = a["stats"]
	var est: Dictionary = a["estimates"]
	if not st.is_empty():
		lines.append("Length %.2f m, beam %.2f m" % [st["length"], st["beam"]])
		lines.append("Weight %.0f kg (%.0f kg with you aboard)" % [st["mass"], st["mass"] + 80.0])
		lines.append("Can carry up to %.0f kg" % st["displacement_kg"])
	if not est.is_empty():
		lines.append("Draft %.0f cm, freeboard %.0f cm" % [est["draft"] * 100.0, est["freeboard"] * 100.0])
		lines.append("Top speed about %.0f knots" % est["top_speed_kn"])
	if not st.is_empty():
		lines.append("Fuel %.0f L, seats %d" % [st["fuel_capacity"], st["seats"]])
	for p: String in a["problems"]:
		lines.append("[color=#ff8a7a]%s[/color]" % p)
	for w: String in a["warnings"]:
		lines.append("[color=#ffd27a]%s[/color]" % w)
	if (a["problems"] as Array).is_empty():
		lines.append("[color=#8af0a0]Ready to launch.[/color]")
	_stats.text = "\n".join(lines)


func _build_left_panel() -> void:
	var panel := _panel(Control.PRESET_TOP_LEFT, Vector2(300, 0))
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_title("Blocks"))
	_blocks_box = VBoxContainer.new()
	box.add_child(_blocks_box)
	var group := ButtonGroup.new()
	var defs := BlockLibrary.all_blocks()
	defs.sort_custom(func(a: BlockDef, b: BlockDef): return [a.category, a.display_name] < [b.category, b.display_name])
	for def in defs:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = def.description
		b.pressed.connect(func(): workshop.call(&"select_block", def.id))
		_blocks_box.add_child(b)
		_block_buttons[def.id] = b
	box.add_child(_title("Colour (C)"))
	var row := HBoxContainer.new()
	box.add_child(row)
	var colors: Array = workshop.get_script().get_script_constant_map()["COLORS"]
	for i in colors.size():
		var s := Button.new()
		s.custom_minimum_size = Vector2(32, 32)
		var c: Color = colors[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = c if c.a > 0.0 else Color(0.5, 0.5, 0.5)
		sb.set_corner_radius_all(4)
		s.add_theme_stylebox_override(&"normal", sb)
		s.add_theme_stylebox_override(&"hover", sb)
		s.add_theme_stylebox_override(&"pressed", sb)
		s.tooltip_text = "Each block's own colour" if c.a == 0.0 else ""
		s.pressed.connect(func():
			workshop.set(&"color_index", i)
			refresh())
		row.add_child(s)
		_swatches.append(s)


func _build_right_panel() -> void:
	var panel := _panel(Control.PRESET_TOP_RIGHT, Vector2(340, 0))
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.custom_minimum_size = Vector2(320, 0)
	panel.add_child(_stats)


func _build_tutorial_panel() -> void:
	_tutorial_panel = _panel(Control.PRESET_CENTER_TOP, Vector2(560, 0))
	var box := VBoxContainer.new()
	_tutorial_panel.add_child(box)
	_tutorial = Label.new()
	_tutorial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial.custom_minimum_size = Vector2(540, 0)
	box.add_child(_tutorial)
	var skip := Button.new()
	skip.text = "Skip the tutorial"
	skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip.pressed.connect(func(): workshop.call(&"skip_tutorial"))
	box.add_child(skip)


func _build_bottom_bar() -> void:
	var panel := _panel(Control.PRESET_CENTER_BOTTOM, Vector2(900, 0))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(220, 0)
	_name_edit.placeholder_text = "Boat name"
	_name_edit.text_submitted.connect(func(t: String): _rename(t))
	_name_edit.focus_exited.connect(func(): _rename(_name_edit.text))
	row.add_child(_name_edit)
	_build_btn = _button(row, "Build", func(): workshop.call(&"set_delete_mode", false))
	_build_btn.toggle_mode = true
	_build_btn.tooltip_text = "Left click places the selected piece (X switches)"
	_delete_btn = _button(row, "Delete", func(): workshop.call(&"set_delete_mode", true))
	_delete_btn.toggle_mode = true
	_delete_btn.tooltip_text = "Left click removes the piece under the mouse; drag to remove a rectangle (X switches)"
	_button(row, "Undo", func(): workshop.get(&"editor").undo())
	_button(row, "Redo", func(): workshop.get(&"editor").redo())
	_button(row, "Clear", func(): workshop.get(&"editor").clear_all())
	_button(row, "Save design", _save)
	_button(row, "Load design", _show_load)
	var launch := _button(row, "Launch", func(): workshop.call(&"request_launch"))
	launch.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.65))
	_button(row, "Close", func(): workshop.call(&"close"))
	var help := Label.new()
	help.text = "Left click: place, or in Delete mode remove (drag for a rectangle)   X: build / delete   Right click: remove   Right drag: orbit   Wheel: zoom   R: rotate   T: tilt   Ctrl+Z: undo"
	help.add_theme_font_size_override(&"font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	box.add_child(help)
	_load_popup = PopupMenu.new()
	_load_popup.id_pressed.connect(_on_load_chosen)
	add_child(_load_popup)


func _rename(t: String) -> void:
	var clean := t.strip_edges()
	if clean != "":
		workshop.get(&"editor").design.design_name = clean
	refresh()


func _save() -> void:
	var design: VesselDesign = workshop.get(&"editor").design
	DirAccess.make_dir_recursive_absolute(DESIGN_DIR)
	var path := DESIGN_DIR + design.design_name.validate_filename() + ".json"
	var err := design.save_json(path)
	EventBus.notify.emit("Saved \"%s\"." % design.design_name if err == OK else "Could not save the design.")


func _show_load() -> void:
	_load_popup.clear()
	var files := DirAccess.get_files_at(DESIGN_DIR) if DirAccess.dir_exists_absolute(DESIGN_DIR) else PackedStringArray()
	var i := 0
	for f in files:
		if f.ends_with(".json"):
			_load_popup.add_item(f.get_basename(), i)
			_load_popup.set_item_metadata(i, DESIGN_DIR + f)
			i += 1
	if i == 0:
		EventBus.notify.emit("No saved designs yet.")
		return
	_load_popup.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()) - Vector2i(0, 40 + 24 * i), Vector2i(260, 0)))


func _on_load_chosen(id: int) -> void:
	var path: String = _load_popup.get_item_metadata(_load_popup.get_item_index(id))
	var d := VesselDesign.load_json(path)
	if d == null:
		EventBus.notify.emit("That design could not be read.")
		return
	var problem: String = workshop.get(&"editor").load_design(d)
	EventBus.notify.emit(problem if problem != "" else "Loaded \"%s\"." % d.design_name)


func _panel(preset: Control.LayoutPreset, min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.13, 0.82)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override(&"panel", sb)
	p.custom_minimum_size = min_size
	add_child(p)
	p.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	match preset:
		Control.PRESET_CENTER_BOTTOM:
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
			p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_TOP:
			p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_TOP_RIGHT:
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return p


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override(&"font_size", 18)
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
