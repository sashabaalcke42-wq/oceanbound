class_name ItemDef
extends Resource
## Anything the player can own that is not a boat block: fish, bait, tools,
## cargo. One .tres file per item in res://data/items/.

enum Category { FISH, BAIT, TOOL, FOOD, CARGO }

@export var id: StringName
@export var display_name := ""
## Name for more than one, if it is not just the display name (e.g. "Sardines").
@export var plural_name := ""
@export_multiline var description := ""
@export var category := Category.TOOL
## What a shop asks for it, and roughly what a market pays (fish prices move).
@export var base_price := 0

@export_group("Fish")
## Depth band (metres of water) where this fish is caught.
@export var min_depth := 0.0
@export var max_depth := 1000.0
## Relative chance of a bite compared with other fish in the same water.
@export var rarity_weight := 1.0


## "1 sardine", "12 sardines", "3 snapper".
func count_text(n: int) -> String:
	var word := display_name if n == 1 or plural_name == "" else plural_name
	return "%d %s" % [n, word.to_lower()]
