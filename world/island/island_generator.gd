extends Node3D
## Generates the starting island: terrain mesh, collision, placeholder trees,
## and a sheltered stretch of coast where the marina goes.
##
## The island is generated from a fixed seed, so it is the same every run.
## Later it can be replaced by a hand-sculpted terrain without touching other
## systems, as long as `height_at()` and `harbour_site()` keep working.

signal generated

@export var seed_value := 1207
@export var world_size := 2000.0
@export var resolution := 251
## Rough radius of the island's coastline in metres.
@export var radius := 620.0
@export var peak_height := 72.0
@export var seabed_depth := -28.0
## Compass direction (degrees, 0 = +X, 90 = +Z) of the harbour coast.
@export var harbour_angle := 90.0
@export var tree_count := 900

const SAND := Color(0.83, 0.77, 0.6)
const WET_SAND := Color(0.6, 0.55, 0.42)
const GRASS := Color(0.34, 0.5, 0.25)
const DRY_GRASS := Color(0.55, 0.56, 0.32)
const ROCK := Color(0.45, 0.43, 0.4)
const SEABED := Color(0.42, 0.4, 0.33)

var _heights := PackedFloat32Array()
var _spacing := 0.0
var _origin := 0.0
var _shape_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group(&"island")
	generate()


func generate() -> void:
	_shape_noise.seed = seed_value
	_shape_noise.frequency = 0.0022
	_shape_noise.fractal_octaves = 3
	_detail_noise.seed = seed_value + 1
	_detail_noise.frequency = 0.012
	_detail_noise.fractal_octaves = 4

	_spacing = world_size / float(resolution - 1)
	_origin = -world_size * 0.5
	_heights.resize(resolution * resolution)
	for j in resolution:
		for i in resolution:
			var x := _origin + i * _spacing
			var z := _origin + j * _spacing
			_heights[j * resolution + i] = _raw_height(x, z)

	var mesh := _build_mesh()
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	terrain.material_override = mat
	add_child(terrain)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	# Solid from both sides, so nothing that ends up under the ground can
	# wander about inside the hill.
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)
	add_child(body)

	_scatter_trees()
	generated.emit()


## Terrain height at world (x, z), interpolated from the generated grid.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - _origin) / _spacing, 0.0, resolution - 1.001)
	var fz := clampf((z - _origin) / _spacing, 0.0, resolution - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := _heights[j * resolution + i]
	var h10 := _heights[j * resolution + i + 1]
	var h01 := _heights[(j + 1) * resolution + i]
	var h11 := _heights[(j + 1) * resolution + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Where the marina goes: the last dry point walking out from the centre
## along the harbour direction, and the outward direction (flat, unit length).
func harbour_site() -> Dictionary:
	return shore_site(harbour_angle)


## The shoreline in a compass direction (degrees, 0 = +X, 90 = +Z): the last
## dry point walking out from the centre, and the outward direction.
func shore_site(angle_deg: float) -> Dictionary:
	var dir := Vector3(cos(deg_to_rad(angle_deg)), 0, sin(deg_to_rad(angle_deg)))
	var shore := Vector3.ZERO
	var d := 0.0
	while d < world_size * 0.5:
		var p := dir * d
		if height_at(p.x, p.z) < 0.6:
			break
		shore = p
		d += 1.0
	shore.y = height_at(shore.x, shore.z)
	return {"shore": shore, "outward": dir}


## How deep the water is here (0 on land).
func depth_at(x: float, z: float) -> float:
	return maxf(-height_at(x, z), 0.0)


func _raw_height(x: float, z: float) -> float:
	var dist := Vector2(x, z).length()
	var angle := atan2(z, x)
	# Wobble the coastline so it is not a circle.
	var coast := radius * (1.0 + 0.28 * _shape_noise.get_noise_2d(cos(angle) * 300.0, sin(angle) * 300.0))
	var t := dist / coast
	# Smooth dome that drops below sea level just past the coast.
	var land := 1.0 - smoothstep(0.0, 1.0, t)
	var h := lerpf(seabed_depth, peak_height, pow(land, 1.6)) + 2.0
	# Ridges and hills inland, fading out near the shore so beaches stay gentle.
	var inland := smoothstep(1.0, 0.55, t)
	h += _detail_noise.get_noise_2d(x, z) * 22.0 * inland
	h += absf(_shape_noise.get_noise_2d(x * 3.0, z * 3.0)) * 30.0 * smoothstep(0.75, 0.2, t)
	# A sheltered, gently sloping harbour coast: flatten towards a shallow shelf.
	var harbour_dir := Vector2(cos(deg_to_rad(harbour_angle)), sin(deg_to_rad(harbour_angle)))
	var along := Vector2(x, z).dot(harbour_dir)
	var across := absf(Vector2(x, z).dot(Vector2(-harbour_dir.y, harbour_dir.x)))
	var harbour := smoothstep(140.0, 40.0, across) * smoothstep(coast * 0.55, coast * 0.85, along)
	var shelf := lerpf(3.5, -6.0, smoothstep(coast * 0.85, coast * 1.08, along))
	h = lerpf(h, shelf, harbour)
	return h


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in resolution:
		for i in resolution:
			var x := _origin + i * _spacing
			var z := _origin + j * _spacing
			var h := _heights[j * resolution + i]
			st.set_color(_color_for(h, _slope(i, j), x, z))
			st.set_uv(Vector2(i, j) / float(resolution - 1))
			st.add_vertex(Vector3(x, h, z))
	for j in resolution - 1:
		for i in resolution - 1:
			var a := j * resolution + i
			var b := a + 1
			var c := a + resolution
			var d := c + 1
			# Clockwise seen from above (Godot front faces are clockwise).
			st.add_index(a)
			st.add_index(b)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	return st.commit()


func _slope(i: int, j: int) -> float:
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, resolution - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, resolution - 1)
	var dx := (_heights[j * resolution + i1] - _heights[j * resolution + i0]) / ((i1 - i0) * _spacing)
	var dz := (_heights[j1 * resolution + i] - _heights[j0 * resolution + i]) / ((j1 - j0) * _spacing)
	return Vector2(dx, dz).length()


func _color_for(h: float, slope: float, x: float, z: float) -> Color:
	var n := _detail_noise.get_noise_2d(x * 4.0, z * 4.0) * 0.5 + 0.5
	if h < -0.4:
		return SEABED.lerp(WET_SAND, smoothstep(-6.0, -0.4, h))
	if h < 2.2 + n * 1.5:
		return WET_SAND.lerp(SAND, smoothstep(-0.4, 1.0, h))
	if slope > 0.75:
		return ROCK
	var grass := GRASS.lerp(DRY_GRASS, n * 0.7)
	return grass.lerp(ROCK, smoothstep(0.45, 0.75, slope) + smoothstep(45.0, 70.0, h) * 0.6)


## Placeholder trees: one MultiMesh of simple low-poly pines on gentle grass.
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var transforms: Array[Transform3D] = []
	var attempts := 0
	var harbour: Dictionary = harbour_site()
	var harbour_pos: Vector3 = harbour["shore"]
	while transforms.size() < tree_count and attempts < tree_count * 12:
		attempts += 1
		var x := rng.randf_range(-radius * 1.2, radius * 1.2)
		var z := rng.randf_range(-radius * 1.2, radius * 1.2)
		var h := height_at(x, z)
		if h < 4.0 or h > 60.0:
			continue
		var i := int((x - _origin) / _spacing)
		var j := int((z - _origin) / _spacing)
		if _slope(i, j) > 0.6:
			continue
		if Vector2(x - harbour_pos.x, z - harbour_pos.z).length() < 90.0:
			continue  # keep the town site clear
		var s := rng.randf_range(0.8, 1.5)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s))
		transforms.append(Transform3D(basis, Vector3(x, h - 0.3, z)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tree_mesh()
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	add_child(mmi)


func _tree_mesh() -> ArrayMesh:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.28
	trunk.height = 2.4
	trunk.radial_segments = 6
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 2.1
	crown.height = 6.5
	crown.radial_segments = 7
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.26, 0.18)
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.17, 0.33, 0.2)
	crown_mat.roughness = 0.9

	var st := SurfaceTool.new()
	var out := ArrayMesh.new()
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.2, 0)))
	st.set_material(trunk_mat)
	st.commit(out)
	st.clear()
	st.append_from(crown, 0, Transform3D(Basis(), Vector3(0, 5.2, 0)))
	st.set_material(crown_mat)
	st.commit(out)
	return out


## A top-down chart of the whole world, `size` pixels square, for the map:
## water shaded by depth, land by height, with a little hill shading.
func map_image(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var step := world_size / float(size)
	for py in size:
		var z := _origin + (py + 0.5) * step
		for px in size:
			var x := _origin + (px + 0.5) * step
			var h := height_at(x, z)
			var c: Color
			if h < 0.0:
				c = Color(0.55, 0.8, 0.85).lerp(Color(0.12, 0.3, 0.5), clampf(-h / 12.0, 0.0, 1.0))
			elif h < 2.5:
				c = SAND
			else:
				c = GRASS.lerp(DRY_GRASS, 0.3).lerp(ROCK, smoothstep(30.0, 65.0, h))
				# Light from the north-west.
				var shade := (height_at(x - step * 2.0, z - step * 2.0) - height_at(x + step * 2.0, z + step * 2.0)) / (step * 4.0)
				c = c.darkened(clampf(shade * 0.25, 0.0, 0.2)) if shade > 0.0 else c.lightened(clampf(-shade * 0.15, 0.0, 0.12))
			img.set_pixel(px, py, c)
	return img


## Map pixel coordinates (0..1 across the world) of a world position.
func map_uv(p: Vector3) -> Vector2:
	return Vector2((p.x - _origin) / world_size, (p.z - _origin) / world_size)
