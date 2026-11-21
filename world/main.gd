extends Node3D
## Sets up the starting world and runs the player's own boat: the island,
## their dock and workshop, the town and jetties, the starter kit on a new
## game, launching whatever they build at the berth, and the menus opened
## from places in town.

const WORKSHOP_SCRIPT := preload("res://vessel/editor/workshop.gd")
## How close the player's boat must be to its berth to be worked on.
const WORKSHOP_RANGE := 40.0
## Compass directions (degrees) around the island for the town and jetties.
const TOWN_ANGLE := 135.0
const JETTIES := [
	{"id": &"lighthouse_point", "name": "Lighthouse Point", "angle": 195.0},
	{"id": &"northern_cove", "name": "Northern Cove", "angle": 300.0},
	{"id": &"oyster_farm", "name": "Oyster Farm", "angle": 30.0, "fuel": true},
]

@onready var island: Node3D = $Island
@onready var player: CharacterBody3D = $Player

var dock: Node3D
## The player's boat in the water, if they have launched one.
var player_boat: RigidBody3D
var workshop: Node3D
var town: Node3D
## The menu screen open right now, if any.
var screen: CanvasLayer


func _ready() -> void:
	Locations.clear()
	var site: Dictionary = island.call(&"harbour_site")
	dock = preload("res://world/marina/personal_dock.gd").new()
	dock.name = "PersonalDock"
	add_child(dock)
	dock.call(&"build", site["shore"], site["outward"])
	(dock.get(&"workshop_point") as Interactable).interacted.connect(func(_by): open_workshop())
	Locations.register(&"home_dock", "Your dock", (dock.get(&"berth") as Marker3D).global_position, 20.0)

	town = preload("res://world/town/town.gd").new()
	town.name = "Town"
	add_child(town)
	town.call(&"build", island, TOWN_ANGLE)
	town.connect(&"place_used", open_place)
	for j: Dictionary in JETTIES:
		var jetty: Node3D = preload("res://world/marina/jetty.gd").new()
		add_child(jetty)
		var s: Dictionary = island.call(&"shore_site", j["angle"])
		jetty.call(&"build", j["id"], j["name"], s["shore"], s["outward"], 18.0, j.get("fuel", false))
	var beacon := preload("res://world/beacon.gd").new()
	beacon.name = "JobBeacon"
	add_child(beacon)

	player.global_position = dock.get(&"player_spawn").global_position
	player.set(&"respawn_point", player.global_position)

	new_game()


func _physics_process(_delta: float) -> void:
	Jobs.check_arrival(player.global_position, player.call(&"is_settled"))


func new_game() -> void:
	Inventory.clear()
	StarterKit.give_kit()
	Inventory.add(&"rod_basic")
	Inventory.add(&"bait_pack", 5)
	Economy.reset()
	Jobs.reset()
	GameState.tutorial_done = false
	GameState.set_player_design(null)
	await get_tree().create_timer(1.5).timeout
	EventBus.notify.emit("Your boat parts have arrived. Open the workshop at the end of your dock (E) to build your first boat.")


## Open the menu for a place in town (a shop, the market, the job board).
func open_place(place_id: StringName) -> void:
	var s: CanvasLayer
	match place_id:
		&"marine_supplies", &"general_store":
			s = preload("res://ui/screens/shop_screen.gd").new(
					load("res://data/shops/%s.tres" % place_id))
		&"fish_market":
			s = preload("res://ui/screens/market_screen.gd").new()
		&"job_board":
			s = preload("res://ui/screens/job_board_screen.gd").new()
		&"harbour_office":
			s = preload("res://ui/screens/info_screen.gd").new("Harbour Office",
					"\"Welcome to the harbour. Mind the speed limit near the quay.\"", [
				["Public dry dock", "Bigger boats need a bigger slipway. Bookings open soon."],
				["Charts", "Town quay, Lighthouse Point, Northern Cove and Oyster Farm all have public jetties. Fuel at the town quay, Oyster Farm and your own dock."],
				["Fishing", "Sardines and flathead in the shallows, snapper and kingfish further out, tuna only in deep water."],
			])
	if s:
		open_screen(s)


func open_screen(s: CanvasLayer) -> void:
	if screen or workshop:
		s.free()
		return
	screen = s
	add_child(s)
	player.call(&"set_in_menu", true)
	s.connect(&"closed", func():
		screen = null
		player.call(&"set_in_menu", false))


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
	EventBus.notify.emit("\"%s\" is in the water, tied up alongside. Step aboard, walk to the helm seat and press E." % design.design_name)


func _spawn_player_boat(design: VesselDesign) -> void:
	var problems: Array[String] = []
	player_boat = VesselBuilder.build(design, problems)
	if player_boat == null:
		push_error("Launch failed: %s" % ", ".join(problems))
		return
	add_child(player_boat)
	player_boat.add_to_group(&"player_boat")
	var at := (dock.get(&"berth") as Marker3D).global_transform
	at.origin.y = VesselBuilder.float_height(player_boat.get(&"stats"))
	player_boat.global_transform = at
	player_boat.call(&"moor_here")
