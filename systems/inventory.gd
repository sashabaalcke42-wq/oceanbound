extends Node
## What the player owns but has not fitted to a boat, as item id -> count.
## For now this holds boat blocks; step 3 adds shop goods, fish and money.

signal changed(id: StringName, count: int)

var _counts: Dictionary = {}  # StringName -> int


func count(id: StringName) -> int:
	return _counts.get(id, 0)


func add(id: StringName, amount := 1) -> void:
	if amount <= 0:
		return
	_counts[id] = count(id) + amount
	changed.emit(id, _counts[id])


## Takes `amount` away. Returns false (and changes nothing) if there are not enough.
func remove(id: StringName, amount := 1) -> bool:
	if amount <= 0:
		return true
	if count(id) < amount:
		return false
	_counts[id] = count(id) - amount
	if _counts[id] == 0:
		_counts.erase(id)
	changed.emit(id, count(id))
	return true


func all() -> Dictionary:
	return _counts.duplicate()


func clear() -> void:
	var ids := _counts.keys()
	_counts.clear()
	for id in ids:
		changed.emit(id, 0)


func to_dict() -> Dictionary:
	var out := {}
	for id in _counts:
		out[String(id)] = _counts[id]
	return out


func from_dict(d: Dictionary) -> void:
	clear()
	for id in d:
		add(StringName(id), int(d[id]))
