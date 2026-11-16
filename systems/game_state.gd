extends Node
## The player's progress that is not an item: their boat design, which
## facilities they can build in, and tutorial flags. Saved by the save system
## in step 4.

signal player_design_changed

## The design of the player's own boat, or null before they have built one.
var player_design: VesselDesign
var tutorial_done := false

## Build limits, in grid cells, for each facility. Larger facilities arrive
## with progression (public dry dock, then shipyards).
const FACILITIES := {
	&"personal_dock": {
		"name": "Personal dock",
		"min": Vector3i(-4, -3, -9),
		"max": Vector3i(4, 4, 9),
	},
}


func set_player_design(d: VesselDesign) -> void:
	player_design = d
	player_design_changed.emit()
