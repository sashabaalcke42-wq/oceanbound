extends Node3D
## A public jetty: a timber walkway out from the shore with room to moor on
## either side. Registers itself as a Location so jobs can send you here.

const DECK_HEIGHT := 1.1
const WIDTH := 2.4
const TIMBER := Color(0.52, 0.4, 0.29)
const PILE := Color(0.3, 0.24, 0.18)

var location_id: StringName
var display_name := ""
var length := 18.0
## The deck's static body, for anything else built on the jetty.
var body: StaticBody3D


## Place the jetty so it starts at `shore` and runs out along `outward`.
func build(id: StringName, p_name: String, shore: Vector3, outward: Vector3,
		p_length := 18.0, with_fuel := false, ground := Callable()) -> void:
	location_id = id
	display_name = p_name
	length = p_length
	name = String(id).to_pascal_case()
	var start := BuildKit.land_end(shore, outward, DECK_HEIGHT + 0.1, ground)
	global_position = start
	look_at(start + outward, Vector3.UP)  # local -Z points out to sea

	body = StaticBody3D.new()
	body.name = "DeckBody"
	add_child(body)
	# Level with the ground where it meets the land; a little extra tucks under it.
	BuildKit.box(self, body, Vector3(0, DECK_HEIGHT, -length * 0.5 + 0.5), Vector3(WIDTH, 0.2, length + 1.0), TIMBER)
	var z := -1.0
	while z > -length:
		for side in [-1.0, 1.0]:
			BuildKit.box(self, body, Vector3(side * (WIDTH * 0.5 - 0.1), DECK_HEIGHT - 3.0, z),
					Vector3(0.25, 6.0, 0.25), PILE)
		z -= 3.0
	# A post and name board at the seaward end, readable from a boat.
	BuildKit.box(self, body, Vector3(0, DECK_HEIGHT + 1.2, -length + 0.3), Vector3(0.2, 2.4, 0.2), PILE)
	BuildKit.sign_text(self, p_name, Vector3(0, DECK_HEIGHT + 2.8, -length + 0.3), 96)

	for dz in [-length * 0.35, -length * 0.7, -length + 1.0]:
		for side in [-1.0, 1.0]:
			var m := Marker3D.new()
			m.name = "Disembark"
			m.position = Vector3(side * (WIDTH * 0.5 - 0.5), DECK_HEIGHT + 0.9, dz)
			add_child(m)
			m.add_to_group(&"disembark_points")

	if with_fuel:
		var pump := preload("res://world/marina/fuel_pump.gd").new()
		pump.position = Vector3(WIDTH * 0.5 - 0.35, DECK_HEIGHT + 0.1, -length * 0.55)
		add_child(pump)

	Locations.register(id, p_name, to_global(Vector3(0, 0, -length * 0.6)), length * 0.5 + 8.0)
