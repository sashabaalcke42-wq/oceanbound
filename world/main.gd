extends Node3D
## Sets up the starting world: island, the player's dock, the player, and
## (for now) a developer test boat at the berth. Step 2 replaces the test boat
## with the starter kit and the build tutorial.

@onready var island: Node3D = $Island
@onready var player: CharacterBody3D = $Player

var dock: Node3D
var test_boat: RigidBody3D


func _ready() -> void:
	var site: Dictionary = island.call(&"harbour_site")
	dock = preload("res://world/marina/personal_dock.gd").new()
	dock.name = "PersonalDock"
	add_child(dock)
	dock.call(&"build", site["shore"], site["outward"])

	player.global_position = dock.get(&"player_spawn").global_position
	player.set(&"respawn_point", player.global_position)

	spawn_test_boat()


func spawn_test_boat() -> void:
	var problems: Array[String] = []
	test_boat = VesselBuilder.build(DevDesigns.test_tinny(), problems)
	if test_boat == null:
		push_error("Test boat failed to build: %s" % ", ".join(problems))
		return
	add_child(test_boat)
	var berth: Marker3D = dock.get(&"berth")
	test_boat.global_transform = berth.global_transform
