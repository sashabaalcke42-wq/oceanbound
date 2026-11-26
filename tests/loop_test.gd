extends Node
## Checks the step 3 core loop in the real world scene: shops, the job board,
## deliveries and deadlines, fish orders, fishing, the fish market and fuel.
## Run: godot --headless --path . --fixed-fps 60 res://tests/loop_test.tscn

var main: Node3D
var player: CharacterBody3D
var fishing: Node
var _activity := ""
var _steps: Array[Callable] = []
var _wait := 0
var _busy := false
var _failures: Array[String] = []
var _job: Job
var _balance_before := 0


func _ready() -> void:
	SaveGame.enabled = false  # a fresh world, and no save left behind
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	player = main.get_node("Player")
	fishing = player.get_node("Fishing")
	fishing.rng.seed = 7
	EventBus.activity_changed.connect(func(t: String): _activity = t)
	_steps = [
		_start, _shop, _shop_broke,
		_accept_cargo, _at_pickup, _check_pickup, _at_dropoff, _check_dropoff,
		_accept_late_job, _check_late_job,
		_fish_order_short, _fish_order_full, _check_fish_order,
		_cast, _bite, _land,
		_market,
		_fuel,
		_other_screens,
		_done,
	]


func _physics_process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		return
	if _steps.is_empty() or _busy:
		return
	var step: Callable = _steps.pop_front()
	print("step: ", step.get_method())
	_busy = true
	await step.call()  # some steps wait a frame or two themselves
	_busy = false


func _start() -> void:
	for id in [&"home_dock", &"town_quay", &"lighthouse_point", &"northern_cove", &"oyster_farm"]:
		_check(Locations.has(id), "location %s exists" % id)
	_check(Economy.balance == Economy.STARTING_BALANCE, "new game starts with $%d" % Economy.STARTING_BALANCE)
	_check(Inventory.count(&"rod_basic") == 1 and Inventory.count(&"bait_pack") == 5, "new game gives a rod and bait")
	_check(Jobs.board().size() == Jobs.BOARD_SIZE, "job board is stocked")
	_wait = 5


func _shop() -> void:
	main.call(&"open_place", &"marine_supplies")
	var s = main.get(&"screen")
	_check(s != null and player.get(&"state") == 2, "shop opens and takes control")
	var hull := Inventory.count(&"hull_aluminium")
	var price: int = s.shop.price_of(&"hull_aluminium")
	_check(s.buy(&"hull_aluminium", 2), "buy two hull blocks")
	_check(Inventory.count(&"hull_aluminium") == hull + 2, "bought blocks go to the inventory")
	_check(Economy.balance == Economy.STARTING_BALANCE - price * 2, "blocks cost money")
	s.close()
	_wait = 3


func _shop_broke() -> void:
	_check(main.get(&"screen") == null and player.get(&"state") == 0, "closing the shop gives control back")
	main.call(&"open_place", &"marine_supplies")
	var s = main.get(&"screen")
	var keep := Economy.balance
	var motors := Inventory.count(&"outboard_15hp")
	Economy.spend(keep, "test")
	_check(not s.buy(&"outboard_15hp", 1) and Inventory.count(&"outboard_15hp") == motors, "cannot buy without the money")
	Economy.earn(keep, "test")
	s.close()
	_wait = 3


func _accept_cargo() -> void:
	_job = _make_job(preload("res://jobs/kinds/cargo_delivery.gd").new())
	_check(Jobs.accept(_job), "accept a delivery")
	_check(not Jobs.accept(Jobs.board()[0]), "only one job at a time")
	var beacon: Node3D = main.get_node("JobBeacon")
	var obj := _job.current_objective()
	_check(beacon.visible and beacon.global_position.distance_to(Locations.position_of(obj["location"])) < 0.1,
			"beacon marks the pickup")
	_wait = 2


func _at_pickup() -> void:
	_teleport(_job.current_objective()["location"])
	_wait = 20


func _check_pickup() -> void:
	_check(_job.current == 1 and Inventory.count(&"cargo_parcel") == 1, "cargo collected at the pickup")
	_balance_before = Economy.balance


func _at_dropoff() -> void:
	_teleport(_job.current_objective()["location"])
	_wait = 20


func _check_dropoff() -> void:
	_check(_job.state == Job.State.DONE and Jobs.active == null, "delivery completes")
	_check(Economy.balance == _balance_before + _job.reward, "delivery pays its reward")
	_check(Inventory.count(&"cargo_parcel") == 0, "cargo handed over")
	_check(not main.get_node("JobBeacon").visible, "beacon hidden with no job")


func _accept_late_job() -> void:
	_job = _make_job(preload("res://jobs/kinds/cargo_delivery.gd").new())
	Jobs.accept(_job)
	_teleport(_job.current_objective()["location"])
	_balance_before = Economy.balance
	_wait = 20


func _check_late_job() -> void:
	_check(Inventory.count(&"cargo_parcel") == 1, "second parcel collected")
	_job.time_left = 0.01
	for i in 3:
		await get_tree().physics_frame
	_check(_job.state == Job.State.FAILED and Jobs.active == null, "missing the deadline fails the job")
	_check(Inventory.count(&"cargo_parcel") == 0 and Economy.balance == _balance_before, "failed job takes the parcel back and pays nothing")


func _fish_order_short() -> void:
	var kind := preload("res://jobs/kinds/fish_order.gd").new()
	_job = _make_job(kind)
	Jobs.accept(_job)
	var take: Dictionary = _job.current_objective()["take"]
	Inventory.add(take["id"], take["count"] - 1)
	_teleport(&"town_quay")
	_wait = 20


func _fish_order_full() -> void:
	_check(Jobs.active == _job, "a fish order waits for the full count")
	var take: Dictionary = _job.current_objective()["take"]
	Inventory.add(take["id"], 1)
	_balance_before = Economy.balance
	_wait = 5


func _check_fish_order() -> void:
	var take: Dictionary = _job.objectives[0]["take"]
	_check(_job.state == Job.State.DONE and Inventory.count(take["id"]) == 0, "fish order delivered")
	_check(Economy.balance == _balance_before + _job.reward, "fish order pays")


func _cast() -> void:
	# Stand at the seaward end of the home dock, looking out to sea.
	var dock: Node3D = main.get(&"dock")
	player.global_position = dock.to_global(Vector3(0, 2.0, -25.0))
	var out := -dock.global_basis.z
	player.set(&"_yaw", atan2(-out.x, -out.z))
	_wait = 20


func _bite() -> void:
	_check(fishing.cast_preview() > 0.5, "facing the water from the dock, fishing is possible")
	_check(_activity.begins_with("F: Fish here"), "the screen says F fishes here (\"%s\")" % _activity)
	_check(fishing.cast(), "cast from the end of the dock")
	_check(_activity.contains("Wait for the float"), "the screen says what to do next")
	_check(fishing.depth > 0.5, "line is in the water (%.1f m deep)" % fishing.depth)
	fishing.timer = 0.0
	_wait = 3


func _land() -> void:
	_check(fishing.state == 2, "a fish bites")
	_check(_activity.contains("Press F now"), "the bite is called out on screen")
	_check(fishing.get(&"_line").visible and fishing.get(&"_rod").visible, "rod and line are shown")
	var bait := Inventory.count(&"bait_pack")
	var fish: StringName = fishing.land()
	_check(fish != &"" and Inventory.count(fish) == 1, "landed a %s" % fish)
	_check(Inventory.count(&"bait_pack") == bait - 1, "used one bait")
	var shallow: Array = fishing.catchable(3.0).map(func(d): return d.id)
	var deep: Array = fishing.catchable(27.0).map(func(d): return d.id)
	_check(&"fish_sardine" in shallow and not &"fish_tuna" in shallow, "shallows hold small fish, no tuna")
	_check(&"fish_tuna" in deep, "tuna in deep water")
	Inventory.add(&"fish_snapper", 10)


func _market() -> void:
	main.call(&"open_place", &"fish_market")
	var before := Economy.balance
	var p1 := Economy.fish_price(&"fish_snapper")
	var earned := Economy.sell_fish(&"fish_snapper", Inventory.count(&"fish_snapper"))
	_check(earned > 0 and Economy.balance == before + earned, "selling fish pays")
	_check(Economy.fish_price(&"fish_snapper") < p1, "selling lots lowers the price")
	_check(Inventory.count(&"fish_snapper") == 0, "sold fish leave the inventory")
	main.get(&"screen").close()
	_wait = 3


func _fuel() -> void:
	main.call(&"_spawn_player_boat", StarterKit.blueprint())
	var boat: RigidBody3D = main.get(&"player_boat")
	await get_tree().physics_frame
	boat.set(&"fuel_l", 2.0)
	var before := Economy.balance
	var pump: Node = main.get(&"dock").get_node("FuelPump")
	var litres: float = pump.refuel()
	var cap: float = boat.get(&"stats")["fuel_capacity"]
	_check(is_equal_approx(boat.get(&"fuel_l"), cap), "pump fills the tank")
	_check(Economy.balance == before - ceili(litres * pump.PRICE_PER_LITRE), "fuel costs money")


func _other_screens() -> void:
	for id in [&"general_store", &"job_board", &"harbour_office"]:
		main.call(&"open_place", id)
		var s = main.get(&"screen")
		_check(s != null, "%s opens" % id)
		s.refresh()
		s.close()
		await get_tree().process_frame


func _done() -> void:
	print("%d failure(s)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)


## A job of a given kind, put on the board so it can be accepted.
func _make_job(kind: JobKind) -> Job:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var job := kind.generate(rng)
	Jobs.available.append(job)
	return job


func _teleport(location: StringName) -> void:
	player.global_position = Locations.position_of(location) + Vector3(0, 2.5, 0)
	player.velocity = Vector3.ZERO


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
