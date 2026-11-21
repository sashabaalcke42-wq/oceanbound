extends Node3D
## The player's personal dock: a timber walkway from the shore out over the
## water, with a berth alongside where their boat is launched and moored.
##
## Built from simple boxes as placeholder art. Other systems only use the
## markers it exposes: `player_spawn`, `berth`, and the disembark points.

const DECK_HEIGHT := 1.1
const WIDTH := 2.4
const BERTH_OFFSET := 2.0

@export var length := 26.0

var player_spawn: Marker3D
var berth: Marker3D
## Where the workshop builds and previews boats (beside the dock, at the berth).
var build_site: Marker3D
## Used with E to open the boat workshop.
var workshop_point: Interactable

var _timber := StandardMaterial3D.new()
var _pile := StandardMaterial3D.new()


## Place the dock so it starts at `shore` and runs out along `outward`.
func build(shore: Vector3, outward: Vector3) -> void:
	_timber.albedo_color = Color(0.55, 0.42, 0.3)
	_timber.roughness = 0.85
	_pile.albedo_color = Color(0.3, 0.24, 0.18)

	var start := Vector3(shore.x, 0.0, shore.z) - outward * 6.0
	global_position = start
	look_at(start + outward, Vector3.UP)  # local -Z now points out to sea

	var body := StaticBody3D.new()
	body.name = "DockBody"
	add_child(body)

	# Walkway planks: one box, with a short ramp up from the land.
	var deck_center := Vector3(0, DECK_HEIGHT, -length * 0.5)
	_add_box(body, deck_center, Vector3(WIDTH, 0.2, length), _timber)
	var ramp_len := 4.0
	var land_h := maxf(shore.y, 0.0)
	_add_box(body, Vector3(0, (DECK_HEIGHT + land_h) * 0.5, ramp_len * 0.5 - 0.2),
			Vector3(WIDTH, 0.2, ramp_len), _timber, atan2(DECK_HEIGHT - land_h, ramp_len))

	# Piles every 3 m along both sides, down to the seabed.
	var z := -1.0
	while z > -length:
		for side in [-1.0, 1.0]:
			_add_box(body, Vector3(side * (WIDTH * 0.5 - 0.1), DECK_HEIGHT - 3.0, z),
					Vector3(0.25, 6.0, 0.25), _pile)
		z -= 3.0
	# Bollards to tie up to.
	for bz in [-length * 0.35, -length * 0.8]:
		_add_box(body, Vector3(WIDTH * 0.5 - 0.25, DECK_HEIGHT + 0.3, bz), Vector3(0.25, 0.4, 0.25), _pile)

	player_spawn = _marker("PlayerSpawn", Vector3(0, DECK_HEIGHT + 1.0, -3.0))
	berth = _marker("Berth", Vector3(WIDTH * 0.5 + BERTH_OFFSET, 0.6, -length * 0.6))
	build_site = _marker("BuildSite", Vector3(WIDTH * 0.5 + BERTH_OFFSET, 0.35, -length * 0.6))

	# A workbench at the shore end of the dock, where the workshop opens.
	var bench_mat := StandardMaterial3D.new()
	bench_mat.albedo_color = Color(0.42, 0.3, 0.2)
	_add_box(body, Vector3(-WIDTH * 0.5 + 0.45, DECK_HEIGHT + 0.5, -5.0), Vector3(0.7, 0.9, 1.6), bench_mat)
	var vice_mat := StandardMaterial3D.new()
	vice_mat.albedo_color = Color(0.2, 0.35, 0.55)
	_add_box(body, Vector3(-WIDTH * 0.5 + 0.45, DECK_HEIGHT + 1.05, -5.4), Vector3(0.3, 0.2, 0.3), vice_mat)
	workshop_point = Interactable.new()
	workshop_point.name = "Workshop"
	workshop_point.prompt = "Open the boat workshop"
	var wshape := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.6, 2.0, 2.4)
	wshape.shape = wbox
	workshop_point.add_child(wshape)
	workshop_point.position = Vector3(-WIDTH * 0.5 + 0.45, DECK_HEIGHT + 0.8, -5.0)
	add_child(workshop_point)

	var pump := preload("res://world/marina/fuel_pump.gd").new()
	pump.name = "FuelPump"
	pump.position = Vector3(WIDTH * 0.5 - 0.35, DECK_HEIGHT + 0.1, -length * 0.45)
	add_child(pump)

	# Where a player at the helm can step off onto the dock.
	for dz in [-length * 0.3, -length * 0.6, -length * 0.9]:
		var m := _marker("Disembark", Vector3(WIDTH * 0.5 - 0.5, DECK_HEIGHT + 0.9, dz))
		m.add_to_group(&"disembark_points")


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, tilt_x := 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, tilt_x), pos)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.transform = xf
	parent.add_child(mesh)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.transform = xf
	parent.add_child(col)


func _marker(marker_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = pos
	add_child(m)
	return m
