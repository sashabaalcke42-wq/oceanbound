class_name GridRaycast
## Finds the first occupied grid cell along a ray, stepping cell by cell
## (Amanatides and Woo). Coordinates are in cells: cell (i, j, k) spans
## i - 0.5 to i + 0.5 on each axis.

## Returns {"hit": bool, "cell": Vector3i, "normal": Vector3i}. `normal` is
## the face of the hit cell the ray came in through.
static func cast(origin: Vector3, dir: Vector3, occupied: Dictionary, max_steps := 256) -> Dictionary:
	var cell := Vector3i(roundi(origin.x), roundi(origin.y), roundi(origin.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3.INF
	var t_delta := Vector3.INF
	for a in 3:
		if dir[a] != 0.0:
			var boundary := cell[a] + 0.5 * step[a]
			t_max[a] = (boundary - origin[a]) / dir[a]
			t_delta[a] = absf(1.0 / dir[a])
	var normal := Vector3i.ZERO
	for i in max_steps:
		if occupied.has(cell):
			return {"hit": true, "cell": cell, "normal": normal}
		var axis := 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {"hit": false, "cell": Vector3i.ZERO, "normal": Vector3i.ZERO}
