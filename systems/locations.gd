extends Node
## Named places in the world that jobs and the HUD can point at: docks,
## jetties, the town quay. The world registers them as it builds itself.

signal registered(id: StringName)

## Default distance (metres, horizontal) that counts as "arrived".
const ARRIVE_RADIUS := 14.0

var _places: Dictionary = {}  # StringName -> {name, position, radius}


func register(id: StringName, display_name: String, position: Vector3, radius := ARRIVE_RADIUS) -> void:
	_places[id] = {"name": display_name, "position": position, "radius": radius}
	registered.emit(id)


func has(id: StringName) -> bool:
	return _places.has(id)


func name_of(id: StringName) -> String:
	return _places[id]["name"] if _places.has(id) else String(id)


func position_of(id: StringName) -> Vector3:
	return _places[id]["position"] if _places.has(id) else Vector3.ZERO


func is_at(id: StringName, where: Vector3) -> bool:
	if not _places.has(id):
		return false
	var p: Vector3 = _places[id]["position"]
	return Vector2(where.x - p.x, where.z - p.z).length() <= _places[id]["radius"]


func ids() -> Array:
	return _places.keys()


func clear() -> void:
	_places.clear()
