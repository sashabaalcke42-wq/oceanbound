extends CanvasLayer
## Testing cheats, on F1: money, parts, fuel, weather, teleports, and
## getting the boat upright or home. The game stops while it is open.

signal closed

var world: Node

var _status: Label
var _calm := false


func _ready() -> void:
	layer = 21
	_calm = world.get_meta(&"cheat_calm", false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.11, 0.1, 0.97)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override(&"panel", style)
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Cheats (F1)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 26)
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	col.add_child(grid)
	_button(grid, "+ $1,000", func(): _money(1000))
	_button(grid, "+ $10,000", func(): _money(10000))
	_button(grid, "Give 10 of every part", give_parts)
	_button(grid, "Fill fuel and bail dry", refuel)
	_button(grid, "Right the boat", right_boat)
	_button(grid, "Boat back to my berth", boat_home)
	_button(grid, "Teleport me to my dock", func(): _teleport(&"home_dock"))
	_button(grid, "Teleport me to town", func(): _teleport(&"town_quay"))
	_button(grid, "Toggle calm weather", toggle_calm)
	_button(grid, "Close", close).grab_focus()

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1.0, 0.85, 0.6)
	col.add_child(_status)

	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_mouse") or event.is_action_pressed(&"cheat_menu"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()


func _money(amount: int) -> void:
	Economy.earn(amount, "Cheat")
	_status.text = "Balance $%d" % Economy.balance


func give_parts() -> void:
	for def in BlockLibrary.all_blocks():
		Inventory.add(def.id, 10)
	_status.text = "Added 10 of every part."


func _boat() -> RigidBody3D:
	var b: Variant = world.get(&"player_boat")
	return b if is_instance_valid(b) else null


func refuel() -> void:
	var boat := _boat()
	if boat == null:
		_status.text = "You have no boat in the water."
		return
	boat.set(&"fuel_l", float(boat.get(&"stats")["fuel_capacity"]))
	boat.set(&"water_l", 0.0)
	_status.text = "Tank full, bilge dry."


## Stand the boat upright where it is, floating, and stopped.
func right_boat() -> void:
	var boat := _boat()
	if boat == null:
		_status.text = "You have no boat in the water."
		return
	var at := boat.global_position
	at.y = Waves.height_at(at.x, at.z) + VesselBuilder.float_height(boat.get(&"stats"))
	boat.global_transform = Transform3D(Basis(Vector3.UP, boat.global_rotation.y), at)
	_stop(boat)
	_status.text = "Boat set upright."


func boat_home() -> void:
	var boat := _boat()
	if boat == null:
		_status.text = "You have no boat in the water."
		return
	var player := _player()
	if player and player.get(&"riding") == boat or player and player.get(&"state") == 1:
		_teleport(&"home_dock")
	var at := (world.get(&"dock").get(&"berth") as Marker3D).global_transform
	at.origin.y = VesselBuilder.float_height(boat.get(&"stats"))
	boat.global_transform = at
	_stop(boat)
	boat.call(&"moor_here")
	_status.text = "Boat tied up at your berth."


func _stop(boat: RigidBody3D) -> void:
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	boat.set(&"water_l", 0.0)


func _player() -> CharacterBody3D:
	return world.get_tree().get_first_node_in_group(&"player") as CharacterBody3D


func _teleport(place: StringName) -> void:
	var player := _player()
	if player == null or not Locations.has(place):
		return
	if player.get(&"state") == 1:
		player.call(&"leave_helm")
	player.call(&"_set_riding", null)
	player.global_position = Locations.position_of(place) + Vector3.UP * 1.5
	player.velocity = Vector3.ZERO
	_status.text = "Teleported to %s." % Locations.name_of(place)


func toggle_calm() -> void:
	_calm = not _calm
	world.set_meta(&"cheat_calm", _calm)
	Waves.amplitude_scale = 0.0 if _calm else 1.0
	Waves.wind_speed = 0.0 if _calm else 5.0
	_status.text = "Flat calm, no wind." if _calm else "Normal weather."


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 42)
	b.add_theme_font_size_override(&"font_size", 17)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
