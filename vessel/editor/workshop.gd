extends Node3D
## The boat workshop: a 3D grid editor for the player's boat.
##
## Owns the orbit camera, the live preview of the design, the placement ghost,
## the tutorial's blueprint outline and mouse/keyboard editing. The rules of
## editing live in DesignEditor; the panels live in workshop_ui.gd.
##
## Mouse: left click places (drag for a rectangle), right click removes,
## right-drag orbits, wheel zooms. Keys: R rotates, T tilts, Ctrl+Z / Ctrl+Y
## undo and redo, Esc closes.

signal closed
signal launch_requested(design: VesselDesign)

const CELL := VesselDesign.CELL
const ORBIT_SPEED := 0.008
const DRAG_THRESHOLD := 6.0

const COLORS: Array[Color] = [
	Color(0, 0, 0, 0),  # the block's own colour
	Color(0.93, 0.93, 0.9), Color(0.75, 0.15, 0.12), Color(0.12, 0.2, 0.42),
	Color(0.2, 0.42, 0.25), Color(0.95, 0.75, 0.15), Color(0.12, 0.12, 0.13),
]

# Tilts the player can cycle through with T: which way the block's top faces.
var _tilts: Array[Basis] = [
	Basis(),
	Basis(Vector3.RIGHT, PI * 0.5), Basis(Vector3.RIGHT, PI),
	Basis(Vector3.RIGHT, -PI * 0.5), Basis(Vector3.FORWARD, PI * 0.5),
	Basis(Vector3.FORWARD, -PI * 0.5),
]

var editor: DesignEditor
var facility: Dictionary
var selected_block: StringName = &"hull_aluminium"
var color_index := 0
var yaw_steps := 0
var tilt_index := 0

## Tutorial state. step_index is -1 when the tutorial is off.
var blueprint: VesselDesign
var steps: Array[Dictionary] = []
var step_index := -1

var _camera: Camera3D
var _cam_yaw := 0.8
var _cam_pitch := -0.55
var _cam_dist := 7.0
var _preview: MeshInstance3D
var _outline: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_mat := StandardMaterial3D.new()
var _grid: MeshInstance3D
var _ui: Control

var _hover_valid := false
var _hover_target := Vector3i.ZERO  # anchor target cell
var _hover_block := Vector3i.ZERO  # existing block under the mouse (for removal)
var _hover_has_block := false
var _drag_start: Variant = null  # Vector3i target where a left-drag began
var _rmb_down_at: Variant = null  # Vector2 where the right button went down
var _orbiting := false


## Open the workshop on `design` (edited in place) at this node's transform.
func open(design: VesselDesign, p_facility: Dictionary, with_tutorial: bool) -> void:
	facility = p_facility
	editor = DesignEditor.new(design, facility["min"], facility["max"])
	editor.changed.connect(_on_design_changed)

	_camera = Camera3D.new()
	_camera.far = 3000.0
	add_child(_camera)
	_camera.current = true

	_preview = MeshInstance3D.new()
	add_child(_preview)
	_outline = MeshInstance3D.new()
	var outline_mat := StandardMaterial3D.new()
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.5)
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Drawn over the water (which is also transparent) so it is never hidden.
	outline_mat.render_priority = 10
	outline_mat.no_depth_test = true
	_outline.material_override = outline_mat
	add_child(_outline)

	_ghost = MeshInstance3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.no_depth_test = true
	_ghost_mat.render_priority = 11
	_ghost.material_override = _ghost_mat
	_ghost.mesh = BoxMesh.new()
	add_child(_ghost)
	_build_grid()

	if with_tutorial:
		blueprint = StarterKit.blueprint()
		steps = StarterKit.tutorial_steps()
		step_index = 0
		_enter_step()
		# Coming back to a half-built boat: skip the steps already done.
		_advance_tutorial()

	_ui = preload("res://vessel/editor/workshop_ui.gd").new()
	_ui.set(&"workshop", self)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(_ui)
	_on_design_changed()


func close() -> void:
	closed.emit()
	queue_free()


func current_rot() -> int:
	return Orientations.index_of(Basis(Vector3.UP, yaw_steps * PI * 0.5) * _tilts[tilt_index])


func current_color() -> Color:
	return COLORS[color_index]


func select_block(id: StringName) -> void:
	selected_block = id
	_ui.call(&"refresh")


func analysis() -> Dictionary:
	return VesselBuilder.analyse(editor.design)


func request_launch() -> void:
	var a := analysis()
	if not (a["problems"] as Array).is_empty():
		EventBus.notify.emit("Not ready to launch: " + (a["problems"] as Array)[0])
		return
	launch_requested.emit(editor.design)


func skip_tutorial() -> void:
	step_index = -1
	blueprint = null
	GameState.tutorial_done = true
	_outline.mesh = null
	_ui.call(&"refresh")


## Text for the tutorial panel, or "" when there is no tutorial.
func tutorial_text() -> String:
	if step_index < 0:
		return ""
	if step_index >= steps.size():
		return "Your tinny is complete. Press Launch to put her in the water."
	var s := steps[step_index]
	var p := editor.blueprint_progress(blueprint, s["covers"])
	return "Step %d of %d: %s  (%d / %d)\n%s" % [
		step_index + 1, steps.size(), s["title"], p.x, p.y, s["hint"]]


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var target := global_transform * _focus_point()
	var offset := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0)) * Vector3(0, 0, _cam_dist)
	_camera.global_position = target + offset
	_camera.look_at(target)
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if editor == null:
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _rmb_down_at != null and (event.position - (_rmb_down_at as Vector2)).length() > DRAG_THRESHOLD:
			_orbiting = true
		if _orbiting:
			_cam_yaw -= event.relative.x * ORBIT_SPEED
			_cam_pitch = clampf(_cam_pitch - event.relative.y * ORBIT_SPEED, -1.45, 0.3)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed and _hover_valid:
				_drag_start = _hover_target
			elif not e.pressed and _drag_start != null:
				_place_from_drag()
				_drag_start = null
		MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_rmb_down_at = e.position
				_orbiting = false
			else:
				if not _orbiting and _hover_has_block:
					editor.remove_at(_hover_block)
				_rmb_down_at = null
				_orbiting = false
		MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(_cam_dist * 0.9, 2.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(_cam_dist * 1.1, 25.0)


func _on_key(e: InputEventKey) -> void:
	if e.is_command_or_control_pressed() and e.keycode == KEY_Z:
		if e.shift_pressed:
			editor.redo()
		else:
			editor.undo()
	elif e.is_command_or_control_pressed() and e.keycode == KEY_Y:
		editor.redo()
	elif e.keycode == KEY_R:
		yaw_steps = (yaw_steps + 1) % 4
	elif e.keycode == KEY_T:
		tilt_index = (tilt_index + 1) % _tilts.size()
	elif e.keycode == KEY_C:
		color_index = (color_index + 1) % COLORS.size()
		_ui.call(&"refresh")
	elif e.keycode == KEY_ESCAPE:
		close()


func _place_from_drag() -> void:
	var start: Vector3i = _drag_start
	var def := BlockLibrary.get_block(selected_block)
	if def == null:
		return
	var problem := ""
	if def.size == Vector3i.ONE and start != _hover_target and _hover_valid:
		var placed := editor.place_many(selected_block, _rect_cells(start, _hover_target), current_rot(), current_color())
		if placed == 0:
			problem = "Nothing could be placed there."
	else:
		problem = editor.place(selected_block, DesignEditor.origin_for_target(selected_block, start, current_rot()),
				current_rot(), current_color())
	if problem != "":
		EventBus.notify.emit(problem)


## Cells of the rectangle between two cells, on the starting cell's layer.
func _rect_cells(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
			out.append(Vector3i(x, a.y, z))
	return out


func _update_hover() -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := global_transform.affine_inverse() * _camera.project_ray_origin(mouse)
	var dir := (global_transform.basis.inverse() * _camera.project_ray_normal(mouse)).normalized()
	var hit := GridRaycast.cast(origin / CELL, dir, editor.occupancy(), 400)
	_hover_has_block = hit["hit"]
	if hit["hit"]:
		_hover_block = hit["cell"]
		_hover_target = hit["cell"] + hit["normal"]
		_hover_valid = true
	else:
		# Otherwise the floor of the build area (the bottom of layer 0).
		var floor_y := -0.5
		_hover_valid = dir.y < -0.0001 and origin.y / CELL > floor_y
		if _hover_valid:
			var t := (floor_y - origin.y / CELL) / dir.y
			var p := origin / CELL + dir * t
			_hover_target = Vector3i(roundi(p.x), 0, roundi(p.z))
			_hover_valid = editor.in_bounds(_hover_target)
	_update_ghost()


func _update_ghost() -> void:
	_ghost.visible = _hover_valid and not _orbiting
	if not _ghost.visible:
		return
	var rot := current_rot()
	var cells: Array[Vector3i] = []
	var problem := ""
	var def := BlockLibrary.get_block(selected_block)
	if _drag_start != null and def.size == Vector3i.ONE:
		cells = _rect_cells(_drag_start, _hover_target)
		problem = "" if Inventory.count(selected_block) >= 1 else "none left"
	else:
		var origin := DesignEditor.origin_for_target(selected_block, _hover_target, rot)
		cells = VesselDesign.cells_of({"id": selected_block, "cell": origin, "rot": rot})
		problem = editor.placement_problem(selected_block, origin, rot)
	var lo: Vector3i = cells[0]
	var hi: Vector3i = cells[0]
	for c in cells:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	var size := Vector3(hi - lo + Vector3i.ONE) * CELL
	(_ghost.mesh as BoxMesh).size = size * 1.02
	_ghost.position = (Vector3(lo + hi) * 0.5) * CELL
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, 0.35) if problem == "" else Color(1.0, 0.3, 0.25, 0.35)


func _on_design_changed() -> void:
	_preview.mesh = VesselBuilder.mesh_for(editor.design)
	if step_index >= 0:
		_advance_tutorial()
	if _ui:
		_ui.call(&"refresh")


func _advance_tutorial() -> void:
	while step_index < steps.size():
		var p := editor.blueprint_progress(blueprint, steps[step_index]["covers"])
		if p.x < p.y:
			break
		step_index += 1
		if step_index < steps.size():
			EventBus.notify.emit("Nice work. Next: " + steps[step_index]["title"].to_lower() + ".")
			_enter_step()
		else:
			GameState.tutorial_done = true
			EventBus.notify.emit("Your tinny is complete. Press Launch to put her in the water.")
	_update_outline()


func _enter_step() -> void:
	var s := steps[step_index]
	selected_block = s["block"]
	# Match the blueprint's rotation for this block so the first try fits.
	for bp in blueprint.blocks:
		if bp["id"] == selected_block and (s["covers"] as Callable).call(bp):
			for t in _tilts.size():
				for y in 4:
					if Orientations.index_of(Basis(Vector3.UP, y * PI * 0.5) * _tilts[t]) == bp["rot"]:
						tilt_index = t
						yaw_steps = y
			break
	_update_outline()


## The blue outline of the blueprint blocks this step still needs.
func _update_outline() -> void:
	if step_index < 0 or step_index >= steps.size():
		_outline.mesh = null
		return
	var remaining := VesselDesign.new()
	for bp in blueprint.blocks:
		if (steps[step_index]["covers"] as Callable).call(bp) and not editor.matches_blueprint_entry(bp):
			remaining.blocks.append(bp)
	_outline.mesh = VesselBuilder.mesh_for(remaining)


func _focus_point() -> Vector3:
	var lo := Vector3(facility["min"])
	var hi := Vector3(facility["max"])
	return Vector3((lo.x + hi.x) * 0.5, 0.5, (lo.z + hi.z) * 0.5) * CELL


## A faint grid on the build floor showing the facility's limits.
func _build_grid() -> void:
	var lo: Vector3i = facility["min"]
	var hi: Vector3i = facility["max"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var y := -0.5 * CELL
	for x in range(lo.x, hi.x + 2):
		st.add_vertex(Vector3((x - 0.5) * CELL, y, (lo.z - 0.5) * CELL))
		st.add_vertex(Vector3((x - 0.5) * CELL, y, (hi.z + 0.5) * CELL))
	for z in range(lo.z, hi.z + 2):
		st.add_vertex(Vector3((lo.x - 0.5) * CELL, y, (z - 0.5) * CELL))
		st.add_vertex(Vector3((hi.x + 0.5) * CELL, y, (z - 0.5) * CELL))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid = MeshInstance3D.new()
	_grid.mesh = st.commit()
	_grid.material_override = mat
	add_child(_grid)
