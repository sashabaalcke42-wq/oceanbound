extends Node3D
## The harbour town: a quay with the fish market and job board, and shops on
## the rise behind it. Placeholder boxes for now; every place the player can
## use is an Interactable that emits `place_used(id)` for the world to open the
## right screen, so the town knows nothing about menus.

signal place_used(place_id: StringName)

const QUAY_LENGTH := 24.0

## Shops and offices up the slope, along the shore (x) and inland (z).
const BUILDINGS := [
	{"id": &"marine_supplies", "name": "Marine Supplies", "x": -16.0, "z": 18.0,
		"size": Vector3(9, 4.5, 7), "wall": Color(0.85, 0.82, 0.74), "roof": Color(0.2, 0.36, 0.55),
		"prompt": "Shop for boat parts"},
	{"id": &"general_store", "name": "General Store", "x": -3.0, "z": 20.0,
		"size": Vector3(8, 4.0, 7), "wall": Color(0.9, 0.78, 0.6), "roof": Color(0.55, 0.22, 0.18),
		"prompt": "Shop for bait and gear"},
	{"id": &"harbour_office", "name": "Harbour Office", "x": 10.0, "z": 19.0,
		"size": Vector3(8, 5.0, 7), "wall": Color(0.92, 0.92, 0.9), "roof": Color(0.25, 0.3, 0.32),
		"prompt": "Visit the harbour office"},
]

var quay: Node3D
var _island: Node


## Place the town on the island's shore in a compass direction (degrees).
func build(island: Node, angle_deg: float) -> void:
	_island = island
	var site: Dictionary = island.call(&"shore_site", angle_deg)
	var shore: Vector3 = site["shore"]
	var outward: Vector3 = site["outward"]
	var origin := Vector3(shore.x, 0.0, shore.z)
	global_position = origin
	look_at(origin + outward, Vector3.UP)  # local -Z to sea, +Z inland, x along the shore

	quay = preload("res://world/marina/jetty.gd").new()
	add_child(quay)
	quay.call(&"build", &"town_quay", "Town quay", shore, outward, QUAY_LENGTH, true)

	_build_market_platform()
	for b: Dictionary in BUILDINGS:
		_building(b)


## A wide timber platform beside the quay with the fish market stall and the
## job board, so the everyday things are a few steps from your boat.
func _build_market_platform() -> void:
	var body := StaticBody3D.new()
	body.name = "MarketBody"
	add_child(body)
	var deck_y: float = 1.1
	var timber := Color(0.52, 0.4, 0.29)
	# Platform: 10 m along the shore, from the beach 9.5 m out, joined to the
	# quay's left side.
	var centre := Vector3(-6.2, deck_y, -4.0)
	BuildKit.box(self, body, centre, Vector3(10.0, 0.2, 11.0), timber)
	for px in [-10.8, -6.2, -1.6]:
		for pz in [-9.2, -2.8]:
			BuildKit.box(self, body, Vector3(px, deck_y - 3.0, pz), Vector3(0.25, 6.0, 0.25), Color(0.3, 0.24, 0.18))

	# Fish market stall: a counter under an awning.
	BuildKit.box(self, body, Vector3(-8.5, deck_y + 0.55, -6.5), Vector3(3.2, 0.9, 1.0), Color(0.7, 0.7, 0.72))
	BuildKit.box(self, null, Vector3(-8.5, deck_y + 1.05, -6.5), Vector3(3.0, 0.1, 0.8), Color(0.85, 0.9, 0.95))
	for ax in [-10.0, -7.0]:
		BuildKit.box(self, body, Vector3(ax, deck_y + 1.4, -7.4), Vector3(0.12, 2.6, 0.12), Color(0.3, 0.24, 0.18))
	BuildKit.box(self, null, Vector3(-8.5, deck_y + 2.75, -6.9), Vector3(3.6, 0.1, 2.0), Color(0.15, 0.45, 0.65), 0.15)
	BuildKit.sign_text(self, "Fish Market", Vector3(-8.5, deck_y + 3.3, -6.9))
	var market := BuildKit.interaction(self, "FishMarket", "Sell your catch", Vector3(-8.5, deck_y + 1.0, -5.4), Vector3(3.4, 2.0, 1.6))
	market.interacted.connect(func(_by): place_used.emit(&"fish_market"))

	# Job board: a noticeboard on two posts.
	for jx in [-3.6, -2.0]:
		BuildKit.box(self, body, Vector3(jx, deck_y + 0.9, -8.2), Vector3(0.12, 1.8, 0.12), Color(0.3, 0.24, 0.18))
	BuildKit.box(self, body, Vector3(-2.8, deck_y + 1.5, -8.2), Vector3(1.8, 1.1, 0.08), Color(0.6, 0.45, 0.3))
	BuildKit.box(self, null, Vector3(-3.1, deck_y + 1.55, -8.15), Vector3(0.5, 0.6, 0.02), Color(0.95, 0.93, 0.85))
	BuildKit.box(self, null, Vector3(-2.4, deck_y + 1.45, -8.15), Vector3(0.45, 0.5, 0.02), Color(0.98, 0.9, 0.7))
	BuildKit.sign_text(self, "Jobs", Vector3(-2.8, deck_y + 2.4, -8.2))
	var board := BuildKit.interaction(self, "JobBoard", "Read the job board", Vector3(-2.8, deck_y + 1.0, -7.4), Vector3(2.2, 2.0, 1.6))
	board.interacted.connect(func(_by): place_used.emit(&"job_board"))


func _building(b: Dictionary) -> void:
	var size: Vector3 = b["size"]
	var x: float = b["x"]
	var z: float = b["z"]
	# The floor sits at the ground level in front of the door, and a deep
	# foundation fills any dip under the rest of the building.
	var front := to_global(Vector3(x, 0, z - size.z * 0.5 - 1.0))
	var base: float = _island.call(&"height_at", front.x, front.z) + 0.05

	var body := StaticBody3D.new()
	body.name = String(b["id"]).to_pascal_case()
	add_child(body)
	var foundation := 6.0
	BuildKit.box(self, body, Vector3(x, base + (size.y - foundation) * 0.5, z),
			Vector3(size.x, size.y + foundation, size.z), b["wall"])
	# Roof: two sloping slabs meeting at a ridge along x.
	var pitch := 0.45
	var half := size.z * 0.5 + 0.4
	var slab_w := half / cos(pitch)
	for side in [-1.0, 1.0]:
		BuildKit.box(self, body, Vector3(x, base + size.y + sin(pitch) * slab_w * 0.5, z + side * half * 0.5),
				Vector3(size.x + 0.8, 0.2, slab_w), b["roof"], side * pitch)
	# Door and sign on the seaward face.
	var face_z := z - size.z * 0.5
	BuildKit.box(self, null, Vector3(x, base + 1.1, face_z - 0.03), Vector3(1.3, 2.2, 0.06), Color(0.35, 0.22, 0.14))
	BuildKit.sign_text(self, b["name"], Vector3(x, base + size.y + 1.6, face_z + 0.4), 140)
	var spot := BuildKit.interaction(self, "Door", b["prompt"], Vector3(x, base + 1.0, face_z - 1.0), Vector3(2.6, 2.4, 2.4))
	var id: StringName = b["id"]
	spot.interacted.connect(func(_by): place_used.emit(id))
