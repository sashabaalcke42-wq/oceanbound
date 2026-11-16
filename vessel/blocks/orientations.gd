class_name Orientations
## The 24 ways a block can be rotated on the grid, as integer bases.
## Designs store an index into this table; index 0 is no rotation.

static var _bases: Array[Basis] = []


static func count() -> int:
	_ensure()
	return _bases.size()


static func basis(index: int) -> Basis:
	_ensure()
	return _bases[clampi(index, 0, _bases.size() - 1)]


## Index of the orientation closest to `b`.
static func index_of(b: Basis) -> int:
	_ensure()
	var best := 0
	var best_score := -INF
	for i in _bases.size():
		var o := _bases[i]
		var score := o.x.dot(b.x) + o.y.dot(b.y) + o.z.dot(b.z)
		if score > best_score:
			best_score = score
			best = i
	return best


## Rotate a grid offset by an orientation, staying on integer cells.
static func rotate_cell(index: int, cell: Vector3i) -> Vector3i:
	var v := basis(index) * Vector3(cell)
	return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))


static func _ensure() -> void:
	if not _bases.is_empty():
		return
	for i in 4:
		for j in 4:
			for k in 4:
				var b := Basis.from_euler(Vector3(i, j, k) * PI * 0.5)
				b = Basis(_round_vec(b.x), _round_vec(b.y), _round_vec(b.z))
				var seen := false
				for o in _bases:
					if o.is_equal_approx(b):
						seen = true
						break
				if not seen:
					_bases.append(b)


static func _round_vec(v: Vector3) -> Vector3:
	return Vector3(roundf(v.x), roundf(v.y), roundf(v.z))
