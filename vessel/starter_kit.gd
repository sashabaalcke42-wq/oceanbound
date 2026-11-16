class_name StarterKit
## The player's first boat: the blocks they start with, the blueprint the
## tutorial guides them through, and the tutorial's steps.

## A few spare blocks beyond the blueprint, so the player can experiment.
const SPARES := {
	&"hull_aluminium": 16,
	&"hull_aluminium_wedge": 8,
	&"bench_seat": 2,
}


static func blueprint() -> VesselDesign:
	var d := DevDesigns.test_tinny()
	d.design_name = "My first tinny"
	return d


## Block counts for a new game: exactly enough for the blueprint, plus spares.
static func kit_counts() -> Dictionary:
	var counts := {}
	for e in blueprint().blocks:
		counts[e["id"]] = counts.get(e["id"], 0) + 1
	for id in SPARES:
		counts[id] = counts.get(id, 0) + SPARES[id]
	return counts


static func give_kit() -> void:
	var counts := kit_counts()
	for id in counts:
		Inventory.add(id, counts[id])


## The tutorial, in order. Each step covers some of the blueprint's blocks
## (`covers` picks them) and selects the block type to use.
static func tutorial_steps() -> Array[Dictionary]:
	return [
		{
			"title": "Lay the hull bottom",
			"hint": "Click and drag across the blue outline to lay a whole row or rectangle of hull blocks at once.",
			"block": &"hull_aluminium",
			"covers": func(e: Dictionary) -> bool: return e["id"] == &"hull_aluminium" and e["cell"].y == 0,
		},
		{
			"title": "Shape the bow",
			"hint": "Angled hull blocks make the bow rise out of the water. Press R and T to turn a block until it matches the outline.",
			"block": &"hull_aluminium_wedge",
			"covers": func(e: Dictionary) -> bool: return e["id"] == &"hull_aluminium_wedge",
		},
		{
			"title": "Build the sides and transom",
			"hint": "One row of hull blocks around the edge keeps the water out. The air inside is what keeps you afloat.",
			"block": &"hull_aluminium",
			"covers": func(e: Dictionary) -> bool: return e["id"] == &"hull_aluminium" and e["cell"].y == 1,
		},
		{
			"title": "Fit the seats and fuel tank",
			"hint": "The helm seat is where you drive from. Every boat needs one.",
			"block": &"seat_helm",
			"covers": func(e: Dictionary) -> bool:
				return e["id"] in [&"seat_helm", &"bench_seat", &"fuel_tank_12l"],
		},
		{
			"title": "Mount the outboard",
			"hint": "Click the back of the transom. The motor hangs down so the propeller sits below the waterline.",
			"block": &"outboard_15hp",
			"covers": func(e: Dictionary) -> bool: return e["id"] == &"outboard_15hp",
		},
	]
