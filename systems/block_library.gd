extends Node
## Loads every BlockDef in res://data/blocks/ at startup and looks them up by id.

const BLOCK_DIR := "res://data/blocks/"

var _blocks: Dictionary = {}  # StringName -> BlockDef


func _enter_tree() -> void:
	for file in ResourceLoader.list_directory(BLOCK_DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(BLOCK_DIR + file) as BlockDef
		if def == null:
			push_error("BlockLibrary: %s is not a BlockDef" % file)
			continue
		if _blocks.has(def.id):
			push_error("BlockLibrary: duplicate block id %s" % def.id)
		_blocks[def.id] = def


func get_block(id: StringName) -> BlockDef:
	return _blocks.get(id)


func has_block(id: StringName) -> bool:
	return _blocks.has(id)


func all_blocks() -> Array[BlockDef]:
	var out: Array[BlockDef] = []
	for def: BlockDef in _blocks.values():
		out.append(def)
	return out
