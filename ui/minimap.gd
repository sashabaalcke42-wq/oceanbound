extends Control
## A north-up chart in the bottom-right corner of the screen: the island,
## the named places, your boat, and you as an arrow. It zooms out as you go
## faster. M opens the whole chart in the middle of the screen.

const SIZE := 230.0
const BIG_SIZE := 680.0
const IMAGE_SIZE := 512
const ZOOM_FOOT := 260.0   # metres across, on foot
const ZOOM_FAST := 700.0   # metres across, at speed

var big := false
var _tex: ImageTexture
var _island: Node
var _span := ZOOM_FOOT
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_font = ThemeDB.fallback_font
	_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map_toggle"):
		big = not big
		_layout()


func _layout() -> void:
	var s := BIG_SIZE if big else SIZE
	if big:
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		position -= Vector2(s, s) * 0.5
	else:
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		position -= Vector2(s + 24, s + 24)
	size = Vector2(s, s)


func _process(delta: float) -> void:
	if _tex == null:
		_island = get_tree().get_first_node_in_group(&"island")
		if _island == null or not _island.has_method(&"map_image"):
			return
		_tex = ImageTexture.create_from_image(_island.call(&"map_image", IMAGE_SIZE))
	var p := _player()
	if p:
		var boat: Node = p.call(&"current_boat")
		var speed: float = (boat as RigidBody3D).linear_velocity.length() if boat else 0.0
		var want := lerpf(ZOOM_FOOT, ZOOM_FAST, clampf(speed / 7.0, 0.0, 1.0))
		# Out at sea, zoom out until the nearest named place is on the chart,
		# so it never shows only empty water.
		var nearest := INF
		for id in Locations.ids():
			var d := Locations.position_of(id) - p.global_position
			nearest = minf(nearest, Vector2(d.x, d.z).length())
		if nearest < INF:
			want = maxf(want, nearest * 2.4)
		want = minf(want, float(_island.get(&"world_size")) * 0.9)
		_span = lerpf(_span, want, 1.0 - exp(-1.5 * delta))
	queue_redraw()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


func _draw() -> void:
	var s := size.x
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.3, 0.5))
	if _tex == null:
		return
	var p := _player()
	if p == null:
		return
	var world: float = _island.get(&"world_size")
	# Which part of the chart to show, in chart pixels.
	var centre_uv: Vector2 = _island.call(&"map_uv", p.global_position)
	var span_uv := (world if big else _span) / world
	if big:
		centre_uv = Vector2(0.5, 0.5)
		span_uv = 0.75
	var src := Rect2((centre_uv - Vector2(span_uv, span_uv) * 0.5) * IMAGE_SIZE, Vector2(span_uv, span_uv) * IMAGE_SIZE)
	draw_texture_rect_region(_tex, Rect2(Vector2.ZERO, size), src)

	var to_screen := func(at: Vector3) -> Vector2:
		var uv: Vector2 = _island.call(&"map_uv", at)
		return (uv - (centre_uv - Vector2(span_uv, span_uv) * 0.5)) / span_uv * s

	# Places, with the job's target in gold; off-chart ones pinned to the edge.
	var target: StringName = &""
	if Jobs.active != null:
		var obj := Jobs.active.current_objective()
		if not obj.is_empty():
			target = obj["location"]
	var font_size := 15 if big else 12
	for id in Locations.ids():
		var at: Vector2 = to_screen.call(Locations.position_of(id))
		var gold: bool = id == target
		var col := Color(1.0, 0.82, 0.3) if gold else (Color(0.6, 0.95, 1.0) if id == &"town_quay" else Color.WHITE)
		var inside := Rect2(Vector2(6, 6), size - Vector2(12, 12)).has_point(at)
		if not inside:
			if not (gold or id == &"town_quay"):
				continue
			at = at.clamp(Vector2(6, 6), size - Vector2(6, 6))
		draw_circle(at, 6.0 if gold else 4.5, Color(0, 0, 0, 0.7))
		draw_circle(at, 4.5 if gold else 3.2, col)
		var near_you := at.distance_to(to_screen.call(p.global_position)) < 30.0
		if inside and not near_you and (big or gold or id == &"town_quay" or id == &"home_dock"):
			var label := Locations.name_of(id)
			var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var lp := Vector2(clampf(at.x - w * 0.5, 2, s - w - 2), at.y - 8)
			draw_string_outline(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8))
			draw_string(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# Your boat, when you are not aboard it.
	for b in get_tree().get_nodes_in_group(&"player_boat"):
		if b != p.call(&"current_boat"):
			_draw_arrow(to_screen.call((b as Node3D).global_position), -(b as Node3D).global_basis.z, 6.0, Color(0.95, 0.5, 0.3))

	# You, pointing the way the camera looks.
	var cam := get_viewport().get_camera_3d()
	var look := -cam.global_basis.z if cam else Vector3.FORWARD
	_draw_arrow(to_screen.call(p.global_position), look, 9.0 if big else 8.0, Color(1, 1, 1))

	# North marker and a frame.
	draw_string_outline(_font, Vector2(s * 0.5 - 5, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, Vector2(s * 0.5 - 5, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.4, 0.35))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8), false, 3.0)
	if big:
		var hint := "M to close"
		draw_string_outline(_font, Vector2(10, s - 12), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(10, s - 12), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _draw_arrow(at: Vector2, dir3: Vector3, r: float, col: Color) -> void:
	var d := Vector2(dir3.x, dir3.z)
	d = d.normalized() if d.length() > 0.01 else Vector2.UP
	var side := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([at + d * r, at - d * r * 0.6 + side * r * 0.65, at - d * r * 0.25, at - d * r * 0.6 - side * r * 0.65])
	var outline := PackedVector2Array()
	for q in pts:
		outline.append(q)
	outline.append(pts[0])
	draw_colored_polygon(pts, col)
	draw_polyline(outline, Color(0, 0, 0, 0.85), 1.5)
