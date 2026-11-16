class_name VesselDesign
extends RefCounted
## A boat as the player designed it: a list of placed blocks on the grid.
## This is the only thing saved for a design; everything else (mesh, mass,
## buoyancy, thrust) is rebuilt from it by VesselBuilder.

const FORMAT_VERSION := 1
## Edge length of one grid cell in metres.
const CELL := 0.25

var design_name := "Unnamed boat"
## Each entry: {"id": StringName, "cell": Vector3i, "rot": int, "color": Color}.
## `cell` is the block's origin cell; multi-cell blocks extend from it along
## their rotated size.
var blocks: Array[Dictionary] = []


func add_block(id: StringName, cell: Vector3i, rot := 0, color := Color(0, 0, 0, 0)) -> void:
	var c := color
	if c.a == 0.0:
		var def := BlockLibrary.get_block(id)
		c = def.default_color if def else Color.WHITE
	blocks.append({"id": id, "cell": cell, "rot": rot, "color": c})


## Every grid cell a placed block covers.
static func cells_of(entry: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var def := BlockLibrary.get_block(entry["id"])
	var size := def.size if def else Vector3i.ONE
	for x in size.x:
		for y in size.y:
			for z in size.z:
				out.append(entry["cell"] + Orientations.rotate_cell(entry["rot"], Vector3i(x, y, z)))
	return out


func to_dict() -> Dictionary:
	var list := []
	for b in blocks:
		var c: Vector3i = b["cell"]
		list.append({
			"id": String(b["id"]),
			"cell": [c.x, c.y, c.z],
			"rot": b["rot"],
			"color": (b["color"] as Color).to_html(false),
		})
	return {"format": FORMAT_VERSION, "name": design_name, "blocks": list}


static func from_dict(d: Dictionary) -> VesselDesign:
	var design := VesselDesign.new()
	design.design_name = d.get("name", "Unnamed boat")
	for b in d.get("blocks", []):
		var c: Array = b["cell"]
		design.blocks.append({
			"id": StringName(b["id"]),
			"cell": Vector3i(int(c[0]), int(c[1]), int(c[2])),
			"rot": int(b.get("rot", 0)),
			"color": Color.html(b.get("color", "ffffff")),
		})
	return design


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


static func load_json(path: String) -> VesselDesign:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("VesselDesign: could not read %s" % path)
		return null
	return from_dict(data)
