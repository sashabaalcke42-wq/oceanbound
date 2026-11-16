extends Node3D
## Sets up the starting world and runs the player's own boat: the island,
## their dock and workshop, the starter kit on a new game, and launching
## whatever they build at the berth.

const WORKSHOP_SCRIPT := preload("res://vessel/editor/workshop.gd")
## How close the player's boat must be to its berth to be worked on.
const WORKSHOP_RANGE := 40.0

@onready var island: Node3D = $Island
@onready var player: CharacterBody3D = $Player

var dock: Node3D
## The player's boat in the water, if they have launched one.
var player_boat: RigidBody3D
var workshop: Node3D


func _ready() -> void:
	var site: Dictionary = island.call(&"harbour_site")
	dock = preload("res://world/marina/personal_dock.gd").new()
	dock.name = "PersonalDock"
	add_child(dock)
	dock.call(&"build", site["shore"], site["outward"])
	(dock.get(&"workshop_point") as Interactable).interacted.connect(func(_by): open_workshop())

	player.global_position = dock.get(&"player_spawn").global_position
	player.set(&"respawn_point", player.global_position)

	new_game()


func new_game() -> void:
	Inventory.clear()
	StarterKit.give_kit()
	GameState.tutorial_done = false
	GameState.set_player_design(null)
	await get_tree().create_timer(1.5).timeout
	EventBus.notify.emit("Your boat parts have arrived. Open the workshop at the end of your dock (E) to build your first boat.")


func open_workshop() -> void:
	if workshop:
		return
	if is_instance_valid(player_boat):
		if player_boat.call(&"helm_occupant") != null:
			return
		var berth: Marker3D = dock.get(&"berth")
		if player_boat.global_position.distance_to(berth.global_position) > WORKSHOP_RANGE:
			EventBus.notify.emit("Bring your boat back to your berth to work on it.")
			return
		# The boat comes out of the water while you work on it.
		player_boat.queue_free()
		player_boat = null

	var design := VesselDesign.new()
	if GameState.player_design:
		design = VesselDesign.from_dict(GameState.player_design.to_dict())
	else:
		design.design_name = "My first tinny"
	workshop = WORKSHOP_SCRIPT.new()
	workshop.name = "Workshop"
	add_child(workshop)
	var site: Marker3D = dock.get(&"build_site")
	workshop.global_transform = site.global_transform
	workshop.connect(&"closed", _on_workshop_closed)
	workshop.connect(&"launch_requested", _on_launch_requested)
	player.call(&"set_in_menu", true)
	workshop.call(&"open", design, GameState.FACILITIES[&"personal_dock"],
			not GameState.tutorial_done and design.blocks.is_empty())


## Close without launching: the design is kept, and launched if it can float.
func _on_workshop_closed() -> void:
	var design: VesselDesign = workshop.get(&"editor").design
	workshop = null
	player.call(&"set_in_menu", false)
	if design.blocks.is_empty():
		GameState.set_player_design(null)
		return
	GameState.set_player_design(design)
	if (VesselBuilder.analyse(design)["problems"] as Array).is_empty():
		_spawn_player_boat(design)
	else:
		EventBus.notify.emit("Your unfinished boat stays in the workshop until it is ready to launch.")


func _on_launch_requested(design: VesselDesign) -> void:
	GameState.set_player_design(design)
	workshop.disconnect(&"closed", _on_workshop_closed)
	workshop.call(&"close")
	workshop = null
	player.call(&"set_in_menu", false)
	_spawn_player_boat(design)
	EventBus.notify.emit("\"%s\" is in the water. Walk over and press E to take the helm." % design.design_name)


func _spawn_player_boat(design: VesselDesign) -> void:
	var problems: Array[String] = []
	player_boat = VesselBuilder.build(design, problems)
	if player_boat == null:
		push_error("Launch failed: %s" % ", ".join(problems))
		return
	add_child(player_boat)
	player_boat.global_transform = (dock.get(&"berth") as Marker3D).global_transform
