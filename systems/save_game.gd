class_name SaveGame
extends RefCounted
## Saving and loading the player's progress to one file: money, what they
## own, their boat design, where their boat and they are, and the tutorial
## flag. The job board is not saved; it is dealt afresh on load.

const FORMAT_VERSION := 1

## Where the save lives. Tests point this somewhere else.
static var path := "user://savegame.json"
## Off in tests that start a world of their own, so they neither load nor
## leave a save behind.
static var enabled := true


static func exists() -> bool:
	return enabled and FileAccess.file_exists(path)


static func delete() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Write the world's state. Returns false if the file could not be written.
static func save(world: Node) -> bool:
	if not enabled:
		return false
	var player: Node3D = world.get(&"player")
	var boat: RigidBody3D = world.get(&"player_boat")
	var data := {
		"format": FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"economy": Economy.to_dict(),
		"inventory": Inventory.to_dict(),
		"tutorial_done": GameState.tutorial_done,
		"design": GameState.player_design.to_dict() if GameState.player_design else null,
		"player": _place_of(player, player.get(&"_yaw")),
	}
	if is_instance_valid(boat):
		var b := _place_of(boat)
		b["fuel_l"] = boat.get(&"fuel_l")
		b["water_l"] = boat.get(&"water_l")
		b["engine_flood"] = boat.get(&"engine_flood")
		b["hydrolocked"] = boat.get(&"hydrolocked")
		data["boat"] = b
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


## Read the save, or {} if there is none or it cannot be read.
static func read() -> Dictionary:
	if not exists():
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _place_of(n: Node3D, yaw: Variant = null) -> Dictionary:
	var p := n.global_position
	return {"x": p.x, "y": p.y, "z": p.z, "yaw": yaw if yaw != null else n.global_rotation.y}
