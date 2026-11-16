class_name VesselBuilder
## Turns a VesselDesign into a live Vessel: one RigidBody3D with a merged
## mesh, box colliders, mass properties, buoyancy columns and engines, all
## worked out from the blocks. Every boat in the game goes through here.

const CELL := VesselDesign.CELL
const WATER_DENSITY := 1025.0
## Buoyant cells are grouped into columns this many cells wide, which keeps
## the number of wave samples per boat low.
const COLUMN_GROUP := 2

const VESSEL_SCRIPT := preload("res://vessel/vessel.gd")


## Build a vessel node from a design. Returns null and a reason in `problems`
## if the design cannot float or be driven.
static func build(design: VesselDesign, problems: Array[String] = []) -> RigidBody3D:
	var occupancy := {}  # Vector3i -> block index
	for i in design.blocks.size():
		var entry := design.blocks[i]
		if BlockLibrary.get_block(entry["id"]) == null:
			problems.append("Unknown block '%s'." % entry["id"])
			continue
		for c in VesselDesign.cells_of(entry):
			if occupancy.has(c):
				problems.append("Two blocks overlap at %s." % c)
			occupancy[c] = i
	if design.blocks.is_empty():
		problems.append("The design has no blocks.")
	if not problems.is_empty():
		return null

	var stats := compute_stats(design)
	if stats["buoyant_volume"] <= 0.0:
		problems.append("There are no hull blocks to keep it afloat.")
	if stats["displacement_kg"] < stats["mass"] * 1.15:
		problems.append("It is too heavy for its hull and would sink. Add hull blocks.")
	if not problems.is_empty():
		return null

	var vessel := RigidBody3D.new()
	vessel.set_script(VESSEL_SCRIPT)
	vessel.name = design.design_name.validate_node_name()
	vessel.collision_layer = 1 << 1
	vessel.collision_mask = (1 << 0) | (1 << 1)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Hull"
	mesh_instance.mesh = _build_mesh(design, occupancy)
	vessel.add_child(mesh_instance)

	for aabb in _collision_boxes(design):
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		col.shape = box
		col.position = aabb.get_center()
		vessel.add_child(col)

	vessel.call(&"setup", design, stats)
	return vessel


## Everything about a design's performance that can be known without
## simulating it. Also used by the construction editor's stats panel.
static func compute_stats(design: VesselDesign) -> Dictionary:
	var mass := 0.0
	var moment := Vector3.ZERO
	var point_masses: Array = []  # [mass, position]
	var columns := {}  # Vector2i -> {vol, x, z, bottom, top, area}
	var hull_cells := {}  # Vector3i -> fill fraction (1 cube, 0.5 wedge)
	var waterplane := {}  # Vector2i (single cell) -> true
	var engines: Array[Dictionary] = []
	var fuel := 0.0
	var helm_pos := Vector3.ZERO
	var has_helm := false
	var seats := 0
	var min_z := INF
	var max_z := -INF
	var min_x := INF
	var max_x := -INF

	for entry in design.blocks:
		var def := BlockLibrary.get_block(entry["id"])
		if def == null:
			continue
		var cells := VesselDesign.cells_of(entry)
		var center := _block_aabb(entry).get_center()
		mass += def.mass_kg
		moment += center * def.mass_kg
		point_masses.append([def.mass_kg, center])
		fuel += def.fuel_capacity_l
		seats += def.seats
		if def.is_helm and not has_helm:
			has_helm = true
			# Feet a little below the seat top, as if sitting.
			helm_pos = center + Vector3(0, CELL * 0.5 - 0.3, 0)
		if def.thrust_n > 0.0:
			var lowest: Vector3i = cells[0]
			for c in cells:
				if c.y < lowest.y:
					lowest = c
			var b := Orientations.basis(entry["rot"])
			engines.append({
				"pos": Vector3(lowest) * CELL,
				"forward": b * Vector3.FORWARD,
				"thrust": def.thrust_n,
				"steer": deg_to_rad(def.steer_angle_deg),
				"burn": def.fuel_burn_lph,
			})
		if def.buoyant:
			var fill := 0.5 if def.shape == BlockDef.Shape.WEDGE else 1.0
			for c in cells:
				hull_cells[c] = fill

	# Air enclosed by the hull (inside an open boat, below the gunwale) floats
	# the boat as much as the hull itself does.
	var enclosed := find_enclosed_cells(hull_cells)
	var buoyant_cells := hull_cells.duplicate()
	for c in enclosed:
		buoyant_cells[c] = 1.0
	for c: Vector3i in buoyant_cells:
		var cell_vol: float = CELL * CELL * CELL * buoyant_cells[c]
		var key := Vector2i(floori(c.x / float(COLUMN_GROUP)), floori(c.z / float(COLUMN_GROUP)))
		var p := Vector3(c) * CELL
		if not columns.has(key):
			columns[key] = {"vol": 0.0, "x": 0.0, "z": 0.0, "bottom": INF, "top": -INF, "cells": {}}
		var col: Dictionary = columns[key]
		col["vol"] += cell_vol
		col["x"] += p.x * cell_vol
		col["z"] += p.z * cell_vol
		col["bottom"] = minf(col["bottom"], p.y - CELL * 0.5)
		col["top"] = maxf(col["top"], p.y + CELL * 0.5)
		col["cells"][Vector2i(c.x, c.z)] = true
		waterplane[Vector2i(c.x, c.z)] = true
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)

	var com := moment / mass if mass > 0.0 else Vector3.ZERO
	var buoy_columns: Array[Dictionary] = []
	var buoyant_volume := 0.0
	for key in columns:
		var col: Dictionary = columns[key]
		var vol: float = col["vol"]
		buoyant_volume += vol
		buoy_columns.append({
			"pos": Vector3(col["x"] / vol, (col["bottom"] + col["top"]) * 0.5, col["z"] / vol),
			"half_height": (col["top"] - col["bottom"]) * 0.5,
			"volume": vol,
			"area": col["cells"].size() * CELL * CELL,
		})

	return {
		"mass": mass,
		"center_of_mass": com,
		"point_masses": point_masses,
		"buoyant_volume": buoyant_volume,
		"hull_volume": hull_cells.values().reduce(func(a, f): return a + f * CELL * CELL * CELL, 0.0),
		"enclosed_cells": enclosed.size(),
		"displacement_kg": buoyant_volume * WATER_DENSITY,
		"columns": buoy_columns,
		"waterplane_area": waterplane.size() * CELL * CELL,
		"length": (max_z - min_z + CELL) if max_z >= min_z else 0.0,
		"beam": (max_x - min_x + CELL) if max_x >= min_x else 0.0,
		"engines": engines,
		"total_thrust": engines.reduce(func(acc, e): return acc + e["thrust"], 0.0),
		"fuel_capacity": fuel,
		"has_helm": has_helm,
		"helm_position": helm_pos,
		"seats": seats,
	}


## Cells of air sealed in by the hull: empty cells that water cannot reach
## sideways from outside, sitting on the hull or on other enclosed air.
## Worked out layer by layer from the bottom with a flood fill from outside.
static func find_enclosed_cells(hull_cells: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if hull_cells.is_empty():
		return out
	var lo: Vector3i = hull_cells.keys()[0]
	var hi: Vector3i = lo
	for c: Vector3i in hull_cells:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	var enclosed := {}
	for y in range(lo.y + 1, hi.y + 1):
		# Flood the layer from a ring just outside the hull's footprint.
		var wet := {}
		var stack: Array[Vector2i] = []
		for x in range(lo.x - 1, hi.x + 2):
			stack.append(Vector2i(x, lo.z - 1))
			stack.append(Vector2i(x, hi.z + 1))
		for z in range(lo.z - 1, hi.z + 2):
			stack.append(Vector2i(lo.x - 1, z))
			stack.append(Vector2i(hi.x + 1, z))
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			if wet.has(p) or p.x < lo.x - 1 or p.x > hi.x + 1 or p.y < lo.z - 1 or p.y > hi.z + 1:
				continue
			if hull_cells.has(Vector3i(p.x, y, p.y)):
				continue
			wet[p] = true
			stack.append(p + Vector2i(1, 0))
			stack.append(p + Vector2i(-1, 0))
			stack.append(p + Vector2i(0, 1))
			stack.append(p + Vector2i(0, -1))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.z, hi.z + 1):
				var c := Vector3i(x, y, z)
				if hull_cells.has(c) or wet.has(Vector2i(x, z)):
					continue
				var below := c - Vector3i(0, 1, 0)
				if hull_cells.has(below) or enclosed.has(below):
					enclosed[c] = true
					out.append(c)
	return out


## Collision boxes for a design. Runs of single-cell blocks along X are
## merged into one box each, which keeps the physics engine's work down.
static func _collision_boxes(design: VesselDesign) -> Array[AABB]:
	var out: Array[AABB] = []
	var singles := {}
	for entry in design.blocks:
		var def := BlockLibrary.get_block(entry["id"])
		if def.size == Vector3i.ONE:
			singles[entry["cell"]] = true
		else:
			out.append(_block_aabb(entry))
	var done := {}
	for c: Vector3i in singles:
		if done.has(c) or singles.has(c - Vector3i(1, 0, 0)):
			continue  # only start runs at their left end
		var end := c
		while singles.has(end + Vector3i(1, 0, 0)):
			end += Vector3i(1, 0, 0)
		for x in range(c.x, end.x + 1):
			done[Vector3i(x, c.y, c.z)] = true
		var lo := Vector3(c) * CELL - Vector3.ONE * CELL * 0.5
		out.append(AABB(lo, Vector3(end.x - c.x + 1, 1, 1) * CELL))
	return out


static func _block_aabb(entry: Dictionary) -> AABB:
	var cells := VesselDesign.cells_of(entry)
	var lo: Vector3i = cells[0]
	var hi: Vector3i = cells[0]
	for c in cells:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	var pos := Vector3(lo) * CELL - Vector3.ONE * CELL * 0.5
	return AABB(pos, Vector3(hi - lo + Vector3i.ONE) * CELL)


# --- Mesh -------------------------------------------------------------------

const _FACE_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func _build_mesh(design: VesselDesign, occupancy: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.35
	mat.roughness = 0.45
	st.set_material(mat)

	for entry in design.blocks:
		var def := BlockLibrary.get_block(entry["id"])
		st.set_color(entry["color"])
		if def.shape == BlockDef.Shape.WEDGE:
			_add_wedge(st, Vector3(entry["cell"]) * CELL, Orientations.basis(entry["rot"]))
		elif def.size == Vector3i.ONE:
			_add_cube(st, entry["cell"], design, occupancy)
		else:
			var aabb := _block_aabb(entry)
			_add_box(st, aabb.get_center(), aabb.size)
	return st.commit()


## A single-cell cube, skipping faces hidden against another full cube.
static func _add_cube(st: SurfaceTool, cell: Vector3i, design: VesselDesign, occupancy: Dictionary) -> void:
	var center := Vector3(cell) * CELL
	for dir in _FACE_DIRS:
		var n: Vector3i = cell + dir
		if occupancy.has(n):
			var other := design.blocks[occupancy[n]]
			var odef := BlockLibrary.get_block(other["id"])
			if odef.shape == BlockDef.Shape.CUBE and odef.size == Vector3i.ONE:
				continue
		_add_face(st, center, Vector3(CELL, CELL, CELL), Vector3(dir))


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	for dir in _FACE_DIRS:
		_add_face(st, center, size, Vector3(dir))


static func _add_face(st: SurfaceTool, center: Vector3, size: Vector3, n: Vector3) -> void:
	# Two axes spanning the face.
	var u := Vector3(n.y, n.z, n.x).abs()
	var v := n.cross(u)
	var half := size * 0.5
	var c := center + n * half
	var hu := u * half
	var hv := v * half
	_add_quad(st, c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv, n)


## Unit wedge: full bottom and back (+Z) faces, sloping down towards -Z.
static func _add_wedge(st: SurfaceTool, center: Vector3, b: Basis) -> void:
	var h := CELL * 0.5
	var pts := {
		"A": Vector3(-h, -h, -h), "B": Vector3(h, -h, -h),
		"C": Vector3(h, -h, h), "D": Vector3(-h, -h, h),
		"E": Vector3(-h, h, h), "F": Vector3(h, h, h),
	}
	for k in pts:
		pts[k] = center + b * pts[k]
	var slope_n := (b * Vector3(0, 1, -1)).normalized()
	_add_quad(st, pts["A"], pts["B"], pts["C"], pts["D"], b * Vector3.DOWN)
	_add_quad(st, pts["D"], pts["C"], pts["F"], pts["E"], b * Vector3.BACK)
	_add_quad(st, pts["A"], pts["B"], pts["F"], pts["E"], slope_n)
	_add_tri(st, pts["A"], pts["D"], pts["E"], b * Vector3.LEFT)
	_add_tri(st, pts["B"], pts["C"], pts["F"], b * Vector3.RIGHT)


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_add_tri(st, a, b, c, n)
	_add_tri(st, a, c, d, n)


## Adds a flat-shaded triangle, ordered so it faces along `n`.
## Godot treats clockwise triangles (seen from the front) as front faces.
static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n.normalized())
	if (b - a).cross(c - a).dot(n) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
