extends Node
## Scripted play-through of the main game flows, to catch runtime errors.
## Any engine or script error printed while this runs is a failure.
## Run: godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn

var main: Node3D
var player: CharacterBody3D
var _steps: Array[Callable] = []
var _wait := 0
var _failures: Array[String] = []


func _ready() -> void:
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	player = main.get_node("Player")
	_steps = [
		_open_workshop, _place_some, _close_workshop,            # leave unfinished
		_open_workshop, _undo_redo, _build_rest, _launch,
		_board, _drive, _cut_and_leave_far, _drive_back, _leave_at_dock,
		_open_workshop, _remove_and_relaunch,
		_walk_into_sea, _done,
	]


func _physics_process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		return
	if _steps.is_empty():
		return
	var step: Callable = _steps.pop_front()
	print("step: ", step.get_method())
	step.call()


func _ws() -> Node:
	return main.get(&"workshop")


func _open_workshop() -> void:
	main.call(&"open_workshop")
	_check(_ws() != null, "workshop opens")
	_wait = 10


func _place_some() -> void:
	var ed: DesignEditor = _ws().get(&"editor")
	var cells: Array[Vector3i] = []
	for x in 3:
		cells.append(Vector3i(x, 0, 0))
	ed.place_many(&"hull_aluminium", cells, 0)
	_ws().call(&"select_block", &"hull_aluminium_wedge")
	_wait = 10


func _close_workshop() -> void:
	_ws().call(&"close")
	_wait = 10


func _undo_redo() -> void:
	var ed: DesignEditor = _ws().get(&"editor")
	ed.undo()
	ed.redo()
	ed.clear_all()
	ed.undo()
	_wait = 5


func _build_rest() -> void:
	var ed: DesignEditor = _ws().get(&"editor")
	ed.clear_all()
	for e in StarterKit.blueprint().blocks:
		ed.place(e["id"], e["cell"], e["rot"])
	_wait = 10


func _launch() -> void:
	_ws().call(&"request_launch")
	_check(main.get(&"player_boat") != null, "boat launched")
	_wait = 30


func _board() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	boat.get_node("BoardArea").call(&"interact", player)
	_check(player.get(&"state") == 1, "player is at the helm")
	_wait = 5


func _drive() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	boat.call(&"set_engine_running", true)
	boat.set(&"throttle", 1.0)
	_wait = 300


func _cut_and_leave_far() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	boat.set(&"throttle", 0.0)
	player.call(&"leave_helm")  # far from a dock: should refuse politely
	_check(player.get(&"state") == 1, "cannot step off at sea")
	main.call(&"open_workshop")  # far from the berth: should refuse
	_check(_ws() == null, "workshop refuses while the boat is away")
	_wait = 10


func _drive_back() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	boat.global_transform = (main.get(&"dock").get(&"berth") as Marker3D).global_transform
	boat.linear_velocity = Vector3.ZERO
	_wait = 30


func _leave_at_dock() -> void:
	player.call(&"leave_helm")
	_check(player.get(&"state") == 0, "steps off at the dock")
	_wait = 30


func _remove_and_relaunch() -> void:
	_check(main.get(&"player_boat") == null, "boat comes out of the water for the workshop")
	var ed: DesignEditor = _ws().get(&"editor")
	ed.remove_at(Vector3i(2, 1, -2))
	Inventory.add(&"hull_aluminium", 3)
	_ws().call(&"request_launch")
	_wait = 30


func _walk_into_sea() -> void:
	player.global_position = Vector3(0, -5, 900)
	_wait = 30


func _done() -> void:
	_check(player.global_position.y > 0.0, "player is rescued from the sea")
	print("%d failure(s)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
