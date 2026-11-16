class_name DesignEditor
extends RefCounted
## The rules of editing a design, with no 3D or UI: placing and removing
## blocks against the player's inventory, the facility's size limit, undo and
## redo, and checking progress against a blueprint. The workshop scene drives
## this; tests drive it directly.

signal changed

var design: VesselDesign
var bounds_min: Vector3i
var bounds_max: Vector3i

var _occupancy := {}  # Vector3i -> index into design.blocks
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func _init(p_design: VesselDesign, p_min: Vector3i, p_max: Vector3i) -> void:
	design = p_design
	bounds_min = p_min
	bounds_max = p_max
	_rebuild_occupancy()


func occupancy() -> Dictionary:
	return _occupancy


func entry_at(cell: Vector3i) -> Dictionary:
	return design.blocks[_occupancy[cell]] if _occupancy.has(cell) else {}


## The origin cell for a block so that its anchor cell lands on `target`.
static func origin_for_target(id: StringName, target: Vector3i, rot: int) -> Vector3i:
	var def := BlockLibrary.get_block(id)
	var anchor := def.anchor if def else Vector3i.ZERO
	return target - Orientations.rotate_cell(rot, anchor)


func in_bounds(c: Vector3i) -> bool:
	return c.x >= bounds_min.x and c.y >= bounds_min.y and c.z >= bounds_min.z \
		and c.x <= bounds_max.x and c.y <= bounds_max.y and c.z <= bounds_max.z


## Why a block cannot go here, or "" if it can.
func placement_problem(id: StringName, origin: Vector3i, rot: int) -> String:
	if BlockLibrary.get_block(id) == null:
		return "Unknown block."
	if Inventory.count(id) < 1:
		return "You have none left."
	for c in VesselDesign.cells_of({"id": id, "cell": origin, "rot": rot}):
		if not in_bounds(c):
			return "Too big for this facility."
		if _occupancy.has(c):
			return "Something is already there."
	return ""


func place(id: StringName, origin: Vector3i, rot: int, color := Color(0, 0, 0, 0)) -> String:
	var problem := placement_problem(id, origin, rot)
	if problem != "":
		return problem
	var entry := _new_entry(id, origin, rot, color)
	_apply_add([entry])
	_push_undo({"op": "add", "entries": [entry]})
	return ""


## Places single-cell blocks at many origins as one undoable step. Skips any
## that do not fit or that the player has run out of. Returns how many it placed.
func place_many(id: StringName, origins: Array[Vector3i], rot: int, color := Color(0, 0, 0, 0)) -> int:
	var added: Array[Dictionary] = []
	for o in origins:
		if placement_problem(id, o, rot) != "":
			continue
		var entry := _new_entry(id, o, rot, color)
		_apply_add([entry])
		added.append(entry)
	if not added.is_empty():
		_push_undo({"op": "add", "entries": added})
	return added.size()


## Removes whatever block covers `cell`. Returns false if there is nothing.
func remove_at(cell: Vector3i) -> bool:
	if not _occupancy.has(cell):
		return false
	var entry := design.blocks[_occupancy[cell]]
	_apply_remove([entry])
	_push_undo({"op": "remove", "entries": [entry]})
	return true


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	if _undo.is_empty():
		return
	var action: Dictionary = _undo.pop_back()
	if action["op"] == "add":
		_apply_remove(action["entries"])
	else:
		_apply_add(action["entries"])
	_redo.append(action)


func redo() -> void:
	if _redo.is_empty():
		return
	var action: Dictionary = _redo.pop_back()
	if action["op"] == "add":
		_apply_add(action["entries"])
	else:
		_apply_remove(action["entries"])
	_undo.append(action)


## Returns every block to the inventory.
func clear_all() -> void:
	if design.blocks.is_empty():
		return
	var all: Array[Dictionary] = design.blocks.duplicate()
	_apply_remove(all)
	_push_undo({"op": "remove", "entries": all})


## Swap in another design, returning the current blocks to the inventory and
## taking the new design's blocks from it. Fails, changing nothing, if the
## player does not own enough blocks; the reason lists what is missing.
func load_design(other: VesselDesign) -> String:
	var need := {}
	for e in other.blocks:
		need[e["id"]] = need.get(e["id"], 0) + 1
	var have := {}
	for e in design.blocks:
		have[e["id"]] = have.get(e["id"], 0) + 1
	var missing: Array[String] = []
	for id in need:
		var short: int = need[id] - Inventory.count(id) - have.get(id, 0)
		if short > 0:
			var def := BlockLibrary.get_block(id)
			missing.append("%d x %s" % [short, def.display_name if def else String(id)])
	if not missing.is_empty():
		return "You need more blocks: %s." % ", ".join(missing)
	for e in design.blocks:
		Inventory.add(e["id"])
	for e in other.blocks:
		Inventory.remove(e["id"])
	design.design_name = other.design_name
	design.blocks = other.blocks.duplicate(true)
	_undo.clear()
	_redo.clear()
	_rebuild_occupancy()
	changed.emit()
	return ""


## How many of the blueprint's blocks picked by `covers` are placed exactly.
func blueprint_progress(blueprint: VesselDesign, covers: Callable) -> Vector2i:
	var done := 0
	var total := 0
	for bp in blueprint.blocks:
		if not covers.call(bp):
			continue
		total += 1
		if matches_blueprint_entry(bp):
			done += 1
	return Vector2i(done, total)


func matches_blueprint_entry(bp: Dictionary) -> bool:
	var e := entry_at(bp["cell"])
	if e.is_empty() or e["id"] != bp["id"] or e["cell"] != bp["cell"]:
		return false
	var def := BlockLibrary.get_block(bp["id"])
	if def.shape == BlockDef.Shape.WEDGE:
		return e["rot"] == bp["rot"]
	if def.size == Vector3i.ONE:
		return true
	var a := VesselDesign.cells_of(e)
	var b := VesselDesign.cells_of(bp)
	a.sort()
	b.sort()
	return a == b


func _new_entry(id: StringName, origin: Vector3i, rot: int, color: Color) -> Dictionary:
	var c := color
	if c.a == 0.0:
		c = BlockLibrary.get_block(id).default_color
	return {"id": id, "cell": origin, "rot": rot, "color": c}


func _apply_add(entries: Array) -> void:
	for e in entries:
		Inventory.remove(e["id"])
		design.blocks.append(e)
	_rebuild_occupancy()
	changed.emit()


func _apply_remove(entries: Array) -> void:
	for e in entries:
		for i in design.blocks.size():
			if is_same(design.blocks[i], e):
				design.blocks.remove_at(i)
				Inventory.add(e["id"])
				break
	_rebuild_occupancy()
	changed.emit()


func _push_undo(action: Dictionary) -> void:
	_undo.append(action)
	_redo.clear()


func _rebuild_occupancy() -> void:
	_occupancy.clear()
	for i in design.blocks.size():
		for c in VesselDesign.cells_of(design.blocks[i]):
			_occupancy[c] = i
