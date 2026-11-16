extends Node
## Loads every ItemDef in res://data/items/ and answers questions about any
## id the player can own, whether it is an item or a boat block.

const ITEM_DIR := "res://data/items/"

var _items: Dictionary = {}  # StringName -> ItemDef


func _enter_tree() -> void:
	for file in ResourceLoader.list_directory(ITEM_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(ITEM_DIR + file) as ItemDef
		if def == null:
			push_error("ItemLibrary: %s is not an ItemDef" % file)
			continue
		_items[def.id] = def


func get_item(id: StringName) -> ItemDef:
	return _items.get(id)


func items_in(category: ItemDef.Category) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for def: ItemDef in _items.values():
		if def.category == category:
			out.append(def)
	return out


## Display name for any ownable id (item or block).
func name_of(id: StringName) -> String:
	var item := get_item(id)
	if item:
		return item.display_name
	var block := BlockLibrary.get_block(id)
	if block:
		return block.display_name
	return String(id).capitalize()


## Shop price for any ownable id (item or block).
func base_price(id: StringName) -> int:
	var item := get_item(id)
	if item:
		return item.base_price
	var block := BlockLibrary.get_block(id)
	return block.price if block else 0
