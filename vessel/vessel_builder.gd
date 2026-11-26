class_name VesselBuilder
## Turns a VesselDesign into a live Vessel: one RigidBody3D with a merged
## mesh, box colliders, mass properties, buoyancy columns and engines, all
## worked out from the blocks. Every boat in the game goes through here.

const CELL := VesselDesign.CELL
## Outboards, in the block's own frame: the motor swings about its shaft, and
## a tiller outboard's handle ends here. The driver's seat must be within
## TILLER_REACH of the handle (measured flat).
const OUTBOARD_PIVOT := Vector3(0, 0, 0.03)
const TILLER_GRIP := Vector3(0, 3 * CELL + 0.15, -0.44)
const TILLER_REACH := 0.8
## The helm seat's wheel centre, from the middle of the seat's two cells.
const HELM_WHEEL := Vector3(0, 0.42, -0.3)
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
	mesh_instance.mesh = _build_mesh(design, occupancy, true)
	vessel.add_child(mesh_instance)
	# Each outboard on its own pivot, so it swings with the steering.
	for i in stats["engines"].size():
		var e: Dictionary = stats["engines"][i]
		var pivot := Node3D.new()
		pivot.name = "Outboard%d" % i
		pivot.position = e["pivot"]
		var motor := MeshInstance3D.new()
		motor.mesh = block_mesh(design.blocks[e["block"]])
		motor.position = -(e["pivot"] as Vector3)
		pivot.add_child(motor)
		if e["tiller"]:
			var grip := Marker3D.new()
			grip.name = "TillerGrip"
			grip.position = e["grip"]
			motor.add_child(grip)
		vessel.add_child(pivot)

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
	var wheel_seat := Vector3.INF
	var wheel_grips: Array[Vector3] = []  # left and right hand on the helm wheel
	var seat_spots: Array[Vector3] = []  # where someone would sit, feet on the floor
	var seats := 0
	var pump_lps := 0.0
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
		pump_lps += def.pump_lph / 3600.0
		# Feet on the floor at the bottom of the seat's cell; the sitting pose
		# puts the hips on the cushion (see the seat models).
		if def.seats > 0:
			seat_spots.append(center + Vector3(0, -CELL * 0.5, 0))
			if def.is_helm and wheel_seat == Vector3.INF:
				wheel_seat = seat_spots[-1]
				var seat_xf := Transform3D(Orientations.basis(entry["rot"]), Vector3(entry["cell"]) * CELL)
				var wheel := Vector3(0.5 * CELL, 0, 0) + HELM_WHEEL
				wheel_grips = [seat_xf * (wheel + Vector3(-0.075, 0, 0)), seat_xf * (wheel + Vector3(0.075, 0, 0))]
		if def.thrust_n > 0.0:
			var lowest: Vector3i = cells[0]
			var highest: Vector3i = cells[0]
			for c in cells:
				if c.y < lowest.y:
					lowest = c
				if c.y > highest.y:
					highest = c
			var b := Orientations.basis(entry["rot"])
			var block_xf := Transform3D(b, Vector3(entry["cell"]) * CELL)
			engines.append({
				"tiller": def.tiller,
				# The motor swings about its shaft, and the tiller handle is
				# where the driver's hand goes (both in the boat's frame).
				"pivot": block_xf * OUTBOARD_PIVOT,
				"grip": block_xf * TILLER_GRIP,
				"block": design.blocks.find(entry),
				"pos": Vector3(lowest) * CELL,
				"head": Vector3(highest) * CELL,
				"pitch_speed": def.prop_pitch_speed_ms,
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

	# Where the driver sits. A tiller boat is driven from the seat nearest the
	# tiller handle, if it is within reach; anything else from the helm seat.
	var tillers := engines.filter(func(e): return e["tiller"])
	if not tillers.is_empty():
		var grip: Vector3 = tillers[0]["grip"]
		var best := INF
		for spot in seat_spots:
			var d := Vector2(spot.x - grip.x, spot.z - grip.z).length()
			if d <= TILLER_REACH and d < best:
				best = d
				helm_pos = spot
				has_helm = true
	elif wheel_seat != Vector3.INF:
		helm_pos = wheel_seat
		has_helm = true
	var bilge := _bilge(enclosed, hull_cells)
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
		"tiller_count": tillers.size(),
		"remote_count": engines.size() - tillers.size(),
		"has_wheel": wheel_seat != Vector3.INF,
		"wheel_grips": wheel_grips,
		"helm_position": helm_pos,
		"seats": seats,
		"pump_lps": pump_lps,
		# Where water can slop in over the side, and where it collects.
		"openings": bilge["openings"],
		"bilge_center": bilge["center"],
		"bilge_extent": bilge["extent"],
		"bilge_capacity_l": enclosed.size() * CELL * CELL * CELL * 1000.0,
	}


## The open top of a boat (cells of enclosed air with nothing above them),
## grouped into a few sample points along the gunwale height, plus the centre
## and half-size of the space water would fill.
static func _bilge(enclosed: Array[Vector3i], hull_cells: Dictionary) -> Dictionary:
	var enclosed_set := {}
	for c in enclosed:
		enclosed_set[c] = true
	var groups := {}  # Vector2i -> {top, x, z, n}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var sum := Vector3.ZERO
	for c in enclosed:
		var p := Vector3(c) * CELL
		sum += p
		lo = lo.min(p)
		hi = hi.max(p)
		var above := c + Vector3i(0, 1, 0)
		if enclosed_set.has(above) or hull_cells.has(above):
			continue
		var key := Vector2i(floori(c.x / 3.0), floori(c.z / 3.0))
		if not groups.has(key):
			groups[key] = {"top": -INF, "x": 0.0, "z": 0.0, "n": 0}
		var g: Dictionary = groups[key]
		g["top"] = maxf(g["top"], p.y + CELL * 0.5)
		g["x"] += p.x
		g["z"] += p.z
		g["n"] += 1
	var openings: Array[Dictionary] = []
	for key in groups:
		var g: Dictionary = groups[key]
		openings.append({
			"pos": Vector3(g["x"] / g["n"], g["top"], g["z"] / g["n"]),
			"area": g["n"] * CELL * CELL,
		})
	if enclosed.is_empty():
		return {"openings": openings, "center": Vector3.ZERO, "extent": Vector3.ZERO}
	return {
		"openings": openings,
		"center": sum / enclosed.size(),
		"extent": (hi - lo) * 0.5 + Vector3.ONE * CELL * 0.5,
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


## How high above sea level to put a boat's origin so it starts out floating
## at its waterline in calm water, rather than dropping in with a splash.
static func float_height(stats: Dictionary) -> float:
	var bottom := INF
	for col: Dictionary in stats["columns"]:
		bottom = minf(bottom, (col["pos"] as Vector3).y - (col["half_height"] as float))
	if bottom == INF:
		return 0.0
	var draft: float = stats["mass"] / (WATER_DENSITY * maxf(stats["waterplane_area"], 0.01))
	return -bottom - draft


## A design checked the way the workshop shows it: problems that stop a
## launch, warnings that do not, and estimates of how the boat will sit and go.
static func analyse(design: VesselDesign) -> Dictionary:
	var problems: Array[String] = []
	var warnings: Array[String] = []
	var out := {"problems": problems, "warnings": warnings, "stats": {}, "estimates": {}}
	if design.blocks.is_empty():
		problems.append("Place some blocks to start a boat.")
		return out
	var stats := compute_stats(design)
	out["stats"] = stats
	if not _is_connected(design):
		problems.append("Some blocks are not attached to the rest of the boat.")
	if stats["buoyant_volume"] <= 0.0:
		problems.append("There are no hull blocks to keep it afloat.")
		return out
	var tillers: int = stats["tiller_count"]
	var remotes: int = stats["remote_count"]
	if tillers > 0 and remotes > 0:
		problems.append("Tiller and remote outboards can't be mixed on one boat. Use one kind.")
	elif tillers > 1:
		problems.append("A boat takes only one tiller outboard. Use remote outboards for twin motors.")
	elif tillers == 1 and not stats["has_helm"]:
		problems.append("The driver must sit within reach of the tiller. Put a seat just in front of the motor.")
	elif remotes > 0 and not stats["has_wheel"]:
		problems.append("Remote outboards are steered from a helm seat with a wheel. Add one.")
	elif not stats["has_helm"]:
		problems.append("It needs a helm seat to drive from.")

	# Calm-water estimates, with one person aboard.
	var loaded: float = stats["mass"] + 80.0
	var hull_bottom := INF
	var gunwale := INF
	for col: Dictionary in stats["columns"]:
		var p: Vector3 = col["pos"]
		hull_bottom = minf(hull_bottom, p.y - col["half_height"])
		gunwale = minf(gunwale, p.y + col["half_height"])
	var area: float = maxf(stats["waterplane_area"], 0.01)
	var draft := loaded / (WATER_DENSITY * area)
	var waterline := hull_bottom + draft
	var freeboard := gunwale - waterline
	if stats["displacement_kg"] < loaded * 1.15 or freeboard <= 0.02:
		problems.append("It is too heavy for its hull and would sink. Add hull blocks.")
	elif freeboard < 0.15:
		warnings.append("It sits very low in the water. Waves may swamp it.")

	# Side-to-side balance with you at the helm: how far the weight sits off
	# the middle of the hull, and roughly how much the boat will lean for it
	# (small-angle stability from the waterplane's width).
	var buoy_x := 0.0
	var vol_sum := 0.0
	for col: Dictionary in stats["columns"]:
		buoy_x += (col["pos"] as Vector3).x * col["volume"]
		vol_sum += col["volume"]
	buoy_x /= maxf(vol_sum, 0.0001)
	var com_x: float = (stats["center_of_mass"].x * stats["mass"] + stats["helm_position"].x * 80.0) / loaded
	var beam: float = maxf(stats["beam"], CELL)
	var metacentre := beam * beam / (12.0 * maxf(draft, 0.02))
	var lean_deg := rad_to_deg(atan((com_x - buoy_x) / metacentre))
	if absf(lean_deg) > 3.0:
		warnings.append("It leans %.0f° to the %s. Move weight across to balance it." % [
				absf(lean_deg), "right" if lean_deg > 0.0 else "left"])

	var engines: Array = stats["engines"]
	if engines.is_empty():
		warnings.append("It has no engine.")
	else:
		if stats["fuel_capacity"] <= 0.0:
			warnings.append("It has no fuel tank, so the engine will not run.")
		for e: Dictionary in engines:
			var prop_y: float = (e["pos"] as Vector3).y
			if prop_y > waterline - 0.05:
				warnings.append("A propeller would be out of the water. Mount the engine lower.")
				break

	# Top speed where thrust balances drag (see vessel.gd for the model).
	var prof: Dictionary = VESSEL_SCRIPT.DEFAULT_PROFILE
	var k: float = prof["drag_forward"] * area * prof["planing_drag_factor"]
	var c: float = prof["drag_lateral_linear"] * area * 0.05
	var thrust: float = stats["total_thrust"]
	# Propeller thrust falls off linearly towards its pitch speed:
	# k v^2 + c v = T (1 - v / p), a quadratic in v.
	var pitch := 1000.0
	for e: Dictionary in engines:
		pitch = minf(pitch, e.get("pitch_speed", 14.0))
	var b := c + thrust / pitch
	var top := (-b + sqrt(b * b + 4.0 * k * thrust)) / (2.0 * k) if thrust > 0.0 else 0.0
	out["estimates"] = {
		"loaded_mass": loaded,
		"draft": draft,
		"freeboard": freeboard,
		"lean_deg": lean_deg,
		"top_speed_kn": top * 1.944,
	}
	return out


static func _is_connected(design: VesselDesign) -> bool:
	var cells := {}
	for e in design.blocks:
		for c in VesselDesign.cells_of(e):
			cells[c] = true
	if cells.is_empty():
		return true
	var start: Vector3i = cells.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector3i] = [start]
	while not stack.is_empty():
		var c: Vector3i = stack.pop_back()
		for d in _FACE_DIRS:
			var n: Vector3i = c + d
			if cells.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == cells.size()


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


## The merged mesh for a design, as shown in the world and in the workshop.
static func mesh_for(design: VesselDesign) -> ArrayMesh:
	var occupancy := {}
	for i in design.blocks.size():
		for c in VesselDesign.cells_of(design.blocks[i]):
			occupancy[c] = i
	return _build_mesh(design, occupancy)


## Just one block's model, in the boat's frame (for the outboards, which are
## separate so they can swing as you steer).
static func block_mesh(entry: Dictionary) -> ArrayMesh:
	var d := VesselDesign.new()
	d.blocks.append(entry)
	return mesh_for(d)


static func _build_mesh(design: VesselDesign, occupancy: Dictionary, skip_engines := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.35
	mat.roughness = 0.45
	st.set_material(mat)
	if design.blocks.is_empty():
		return ArrayMesh.new()

	for entry in design.blocks:
		var def := BlockLibrary.get_block(entry["id"])
		if skip_engines and def.thrust_n > 0.0:
			continue
		st.set_color(entry["color"])
		if def.shape == BlockDef.Shape.WEDGE:
			_add_wedge(st, Vector3(entry["cell"]) * CELL, Orientations.basis(entry["rot"]))
		elif _add_detailed(st, entry):
			pass
		elif def.size == Vector3i.ONE:
			_add_cube(st, entry["cell"], design, occupancy)
		else:
			var aabb := _block_aabb(entry)
			_add_box(st, aabb.get_center(), aabb.size)
	return st.commit()


# --- Detailed pieces ----------------------------------------------------------
# Equipment is modelled in the block's own frame, so the shape shows which way
# it faces: -Z is the front of the boat, +Y is up, and (0, 0, 0) is the centre
# of the block's origin cell (its other cells lie along +X, +Y and +Z).

const _DARK := Color(0.12, 0.12, 0.13)
const _METAL := Color(0.55, 0.57, 0.6)
const _BRONZE := Color(0.85, 0.62, 0.25)
const _WHITE := Color(0.95, 0.95, 0.92)


## Adds a recognisable model for equipment blocks. Returns false for blocks
## that are drawn as plain cubes or boxes.
static func _add_detailed(st: SurfaceTool, entry: Dictionary) -> bool:
	var xf := Transform3D(Orientations.basis(entry["rot"]), Vector3(entry["cell"]) * CELL)
	var col: Color = entry["color"]
	var C := CELL
	match String(entry["id"]):
		"outboard_15hp", "outboard_15hp_remote":
			# Four cells tall: propeller at the bottom (y 0), powerhead on top
			# (y 3), standing just above the transom. Thrust pushes the boat
			# towards -Z, so the propeller sits at the back (+Z).
			var tiller: bool = BlockLibrary.get_block(entry["id"]).tiller
			var trim := _DARK if not tiller else col.lightened(0.25)
			_obox(st, xf, Vector3(0, 3 * C + 0.13, 0.04), Vector3(0.2, 0.24, 0.28), col)  # cowling
			_obox(st, xf, Vector3(0, 3 * C + 0.26, 0.04), Vector3(0.17, 0.03, 0.24), trim)  # cap
			_arrow(st, xf, Vector3(0, 3 * C + 0.277, 0.03), 0.14, _WHITE if tiller else _DARK)  # points forward
			_obox(st, xf, Vector3(0, 3 * C + 0.06, 0.04), Vector3(0.205, 0.02, 0.285), trim)  # cowling seam
			_obox(st, xf, Vector3(0, 3 * C - 0.04, 0.03), Vector3(0.13, 0.12, 0.16), _DARK)  # midsection
			_obox(st, xf, Vector3(0, 3 * C + 0.1, -0.13), Vector3(0.12, 0.1, 0.08), _METAL)  # clamp over the transom
			_obox(st, xf, Vector3(0, 3 * C + 0.02, -0.2), Vector3(0.1, 0.03, 0.03), _METAL)  # clamp screws
			if tiller:
				_obox(st, xf, Vector3(0, TILLER_GRIP.y, -0.25), Vector3(0.04, 0.04, 0.3), _DARK)  # tiller arm
				_obox(st, xf, TILLER_GRIP + Vector3(0, 0, 0.02), Vector3(0.055, 0.055, 0.1), Color(0.2, 0.2, 0.21))  # twist grip
				_obox(st, xf, Vector3(0.03, TILLER_GRIP.y + 0.015, -0.13), Vector3(0.025, 0.025, 0.025), Color(0.85, 0.12, 0.1))  # kill switch
			else:
				# Steering link and the cable running forward to the wheel.
				_obox(st, xf, Vector3(0, 3 * C + 0.0, -0.13), Vector3(0.03, 0.03, 0.12), _METAL)
				_obox(st, xf, Vector3(0, 3 * C + 0.0, -0.26), Vector3(0.025, 0.025, 0.14), _DARK)
			_obox(st, xf, Vector3(0, 1.5 * C, 0.03), Vector3(0.06, 0.62, 0.09), _DARK)  # shaft
			_obox(st, xf, Vector3(0, 0.08, 0.03), Vector3(0.16, 0.015, 0.2), _DARK)  # cavitation plate
			_obox(st, xf, Vector3(0, -0.02, 0.03), Vector3(0.075, 0.075, 0.22), _DARK)  # gearcase
			_obox(st, xf, Vector3(0, -0.07, 0.06), Vector3(0.02, 0.06, 0.1), _DARK)  # skeg
			_obox(st, xf, Vector3(0, -0.02, 0.155), Vector3(0.04, 0.04, 0.04), _BRONZE)  # hub
			for i in 3:
				var blade := Basis(Vector3.BACK, i * TAU / 3.0 + 0.3)
				_obox(st, xf, Vector3(0, -0.02, 0.16) + blade * Vector3(0, 0.07, 0), Vector3(0.05, 0.12, 0.012),
						_BRONZE, blade * Basis(Vector3.UP, 0.35))
			return true
		"seat_helm":
			# Two cells wide (along +X): a seat facing forward with a backrest
			# behind and a wheel on a console in front.
			var mid := Vector3(0.5 * C, 0, 0)
			_obox(st, xf, mid + Vector3(0, 0.05, 0.02), Vector3(0.44, 0.09, 0.2), col)  # cushion
			_obox(st, xf, mid + Vector3(0, 0.2, 0.11), Vector3(0.44, 0.22, 0.04), col)  # backrest
			_obox(st, xf, mid + Vector3(0, -0.055, 0.02), Vector3(0.34, 0.13, 0.16), _DARK)  # pedestal
			# The console stands out in front, between the driver's knees, with
			# the wheel at chest height (see HELM_WHEEL).
			_obox(st, xf, mid + Vector3(0, 0.09, -0.38), Vector3(0.06, 0.43, 0.06), _METAL)  # post
			_obox(st, xf, mid + Vector3(0, 0.33, -0.38), Vector3(0.16, 0.09, 0.1), _METAL)  # dash
			_obox(st, xf, mid + HELM_WHEEL + Vector3(0, 0, -0.05), Vector3(0.03, 0.03, 0.08), _DARK)  # column
			_ring(st, xf, mid + HELM_WHEEL, 0.08, _DARK)  # wheel
			_obox(st, xf, mid + HELM_WHEEL, Vector3(0.03, 0.03, 0.03), _METAL)  # wheel hub
			return true
		"bench_seat":
			# Plank at the same height as the helm cushion, so sitting looks right.
			_obox(st, xf, Vector3(0, 0.07, 0), Vector3(0.25, 0.05, 0.2), col)  # plank
			for lx in [-0.09, 0.09]:
				_obox(st, xf, Vector3(lx, -0.03, 0), Vector3(0.03, 0.15, 0.16), col.darkened(0.3))
			return true
		"fuel_tank_12l":
			var mid := Vector3(0.5 * C, 0, 0)
			_obox(st, xf, mid + Vector3(0, -0.01, 0), Vector3(0.46, 0.21, 0.22), col)  # tank
			_obox(st, xf, mid + Vector3(0, 0.1, 0), Vector3(0.4, 0.02, 0.16), col.darkened(0.15))  # top
			_obox(st, xf, mid + Vector3(0.15, 0.12, 0.04), Vector3(0.05, 0.04, 0.05), _DARK)  # filler cap
			_obox(st, xf, mid + Vector3(-0.17, 0.12, -0.02), Vector3(0.03, 0.03, 0.03), _METAL)  # fuel line
			_obox(st, xf, mid + Vector3(-0.02, 0.13, 0), Vector3(0.18, 0.025, 0.03), _DARK)  # handle
			return true
		"bilge_pump":
			_obox(st, xf, Vector3(0, -0.06, 0), Vector3(0.12, 0.12, 0.12), col)  # pump body
			_obox(st, xf, Vector3(0, -0.11, 0), Vector3(0.15, 0.02, 0.15), _DARK)  # strainer
			_obox(st, xf, Vector3(0, 0.03, 0), Vector3(0.03, 0.08, 0.03), _DARK)  # outlet hose
			return true
	return false


## A box in a block's frame, optionally turned by `turn` about its own centre.
static func _obox(st: SurfaceTool, xf: Transform3D, center: Vector3, size: Vector3, color: Color,
		turn := Basis.IDENTITY) -> void:
	st.set_color(color)
	var h := size * 0.5
	for n: Vector3i in _FACE_DIRS:
		var nf := Vector3(n)
		var u := Vector3(nf.y, nf.z, nf.x).abs()
		var v := nf.cross(u)
		var c := nf * h
		var hu := u * h
		var hv := v * h
		var pts := [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
		for i in 4:
			pts[i] = xf * (center + turn * (pts[i] as Vector3))
		_add_quad(st, pts[0], pts[1], pts[2], pts[3], xf.basis * (turn * nf))


## A flat arrow on a top face, pointing towards -Z.
static func _arrow(st: SurfaceTool, xf: Transform3D, at: Vector3, length: float, color: Color) -> void:
	st.set_color(color)
	var w := length * 0.45
	var tip := xf * (at + Vector3(0, 0, -length * 0.5))
	var l := xf * (at + Vector3(-w, 0, 0))
	var r := xf * (at + Vector3(w, 0, 0))
	_add_tri(st, tip, l, r, xf.basis * Vector3.UP)
	_obox(st, xf, at + Vector3(0, -0.002, length * 0.22), Vector3(w * 0.7, 0.004, length * 0.45), color)


## A steering wheel facing the seat (+Z), as eight short bars.
static func _ring(st: SurfaceTool, xf: Transform3D, center: Vector3, radius: float, color: Color) -> void:
	var seg := 2.0 * radius * sin(PI / 8.0)
	for i in 8:
		var a := i * TAU / 8.0
		var b := Basis(Vector3.BACK, a)
		_obox(st, xf, center + b * Vector3(0, radius, 0), Vector3(seg * 1.1, 0.018, 0.018), color, b)


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
