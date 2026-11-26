extends Node
## Scripted play-through of the main game flows, to catch runtime errors.
## Any engine or script error printed while this runs is a failure.
## Run: godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn

var main: Node3D
var player: CharacterBody3D
var _steps: Array[Callable] = []
var _wait := 0
var _busy := false
var _failures: Array[String] = []
var _errors := ErrorCounter.new()


## Counts every engine and script error, so the run fails on any of them
## even when no check notices (in the editor a script error stops the game).
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	OS.add_logger(_errors)
	SaveGame.enabled = false  # a fresh world, and no save left behind
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	player = main.get_node("Player")
	_steps = [
		_walk_ashore, _compass_shows_town,
		_open_workshop, _place_some, _close_workshop,            # leave unfinished
		_open_workshop, _undo_redo, _delete_mode, _build_rest, _launch,
		_board, _drive, _cut_and_leave_far, _standing_in_boat, _drive_back, _leave_at_dock,
		_open_workshop, _remove_and_relaunch,
		_walk_into_sea, _swimming, _save_and_load, _pause_menu, _done,
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
	await step.call()
	_busy = false


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


## Pressed through the workshop's own buttons, part way through the
## tutorial, as a player would.
func _undo_redo() -> void:
	var ed: DesignEditor = _ws().get(&"editor")
	_check(_ws().get(&"step_index") >= 0, "tutorial carries on when you come back to an unfinished build")
	_press("Clear")
	_check(ed.design.blocks.is_empty(), "clear empties the build")
	var placed := 0
	for e in StarterKit.blueprint().blocks:
		if placed < 4 and ed.place(e["id"], e["cell"], e["rot"]) == "":
			placed += 1
	var before := ed.design.blocks.size()
	for name in ["Undo", "Redo", "Undo", "Clear", "Undo", "Clear", "Undo", "Undo"]:
		_press(name)
	_check(ed.design.blocks.size() == before - 2, "undo and clear buttons work mid-tutorial")
	_check(_errors.errors.is_empty(), "no errors from the workshop buttons")
	_wait = 5


## Delete mode: hovering a piece shows it, a click removes it, a drag
## removes a whole row as one undo step. The placing ghost is the real piece.
func _delete_mode() -> void:
	var ws := _ws()
	var ed: DesignEditor = ws.get(&"editor")
	ed.clear_all()
	for x in range(-2, 3):
		ed.place(&"hull_aluminium", Vector3i(x, 0, 0), 0)
	ws.set(&"selected_block", &"outboard_15hp")
	Inventory.add(&"outboard_15hp")
	ws.set(&"_hover_valid", true)
	ws.set(&"_hover_target", Vector3i(0, 1, 3))
	ws.call(&"_update_ghost")
	var ghost: MeshInstance3D = ws.get(&"_ghost_piece")
	_check(ghost.visible and ghost.mesh != null and ghost.mesh.get_surface_count() > 0, "the ghost shows the piece itself")
	_press("Delete")
	_check(ws.get(&"delete_mode"), "Delete button switches to delete mode")
	ws.set(&"_hover_has_block", true)
	ws.set(&"_hover_block", Vector3i(-2, 0, 0))
	ws.call(&"_update_ghost")
	_check(ghost.visible, "the piece to delete is highlighted")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ws.call(&"_on_mouse_button", click)
	ws.set(&"_hover_block", Vector3i(0, 0, 0))
	click = click.duplicate()
	click.pressed = false
	ws.call(&"_on_mouse_button", click)
	_check(ed.design.blocks.size() == 2, "dragging in delete mode removes the row (%d left)" % ed.design.blocks.size())
	ed.undo()
	_check(ed.design.blocks.size() == 5, "one undo brings the whole row back")
	_press("Build")
	_check(not ws.get(&"delete_mode"), "Build button goes back to placing")
	Inventory.remove(&"outboard_15hp")
	_wait = 5


func _save_and_load() -> void:
	SaveGame.enabled = true
	SaveGame.path = "user://test_save.json"
	SaveGame.delete()
	var money := Economy.balance
	var fish_before := Inventory.count(&"bait_pack")
	_check(SaveGame.save(main), "the game saves")
	_check(SaveGame.exists(), "a save file is written")
	Economy.reset(1)
	Inventory.remove(&"bait_pack", fish_before)
	var boat_was: Vector3 = (main.get(&"player_boat") as Node3D).global_position
	(main.get(&"player_boat") as Node).queue_free()
	main.set(&"player_boat", null)
	await get_tree().physics_frame
	main.call(&"load_game")
	_check(Economy.balance == money, "money comes back from the save")
	_check(Inventory.count(&"bait_pack") == fish_before, "belongings come back")
	var boat: Node3D = main.get(&"player_boat")
	_check(boat != null and Vector2(boat.global_position.x - boat_was.x, boat.global_position.z - boat_was.z).length() < 1.0,
			"the boat is back where it was")
	SaveGame.delete()
	SaveGame.enabled = false
	_wait = 30


func _pause_menu() -> void:
	var esc := InputEventAction.new()
	esc.action = &"toggle_mouse"
	esc.pressed = true
	main.call(&"_unhandled_input", esc)
	_check(main.get(&"pause_menu") != null and get_tree().paused, "Esc pauses with a menu")
	(main.get(&"pause_menu") as Node).call(&"resume")
	_check(not get_tree().paused and main.get(&"pause_menu") == null, "Continue carries on")
	_wait = 5


func _press(text: String) -> void:
	for b: Button in _ws().find_children("*", "Button", true, false):
		if b.text == text:
			b.pressed.emit()
			return
	_check(false, "workshop has a %s button" % text)


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
	# A tiller boat: the driver's hand is on the tiller, and the motor swings
	# the way its thrust points as you steer.
	var grip: Variant = boat.call(&"tiller_grip")
	_check(grip is Vector3, "the starter boat is steered by tiller")
	var body: Node3D = player.get_node("Body")
	var hand_at := INF
	for arm: Dictionary in body.get(&"_arms"):
		var hand: Vector3 = (arm["elbow"] as Node3D).global_transform * Vector3(0, -(0.28 + 0.045), 0)
		hand_at = minf(hand_at, hand.distance_to(grip))
	_check(hand_at < 0.05, "the driver holds the tiller (hand %.2f m from the grip)" % hand_at)
	boat.set(&"steer", 1.0)
	boat.call(&"_process", 0.0)
	var motor := boat.get_node("Outboard0") as Node3D
	_check(absf(motor.rotation.y - deg_to_rad(32.0)) < 0.01, "the motor swings as you steer")
	boat.set(&"steer", 0.0)
	boat.call(&"_process", 0.0)
	# Dunking the engine floods it bit by bit: it loses power and keeps
	# running for a while, then hydrolocks and has to be cranked clear.
	var step := 1.0 / 60.0
	boat.set(&"engine_flood", 0.0)
	boat.set(&"hydrolocked", false)
	boat.call(&"set_engine_running", true)
	for i in 60:
		boat.call(&"_update_flood", true, step)
	var f: float = boat.get(&"engine_flood")
	_check(f > 0.3 and f < 0.5 and boat.get(&"engine_running"), "a second under water floods the engine %d%% but it keeps running" % roundi(f * 100.0))
	boat.set(&"_misfire", 0.0)
	_check(boat.call(&"engine_power") < 0.8, "a flooded engine loses power")
	for i in 120:
		boat.call(&"_update_flood", true, step)
	_check(boat.get(&"hydrolocked") and not boat.get(&"engine_running"), "a fully flooded engine hydrolocks and stops")
	boat.call(&"set_engine_running", true)
	_check(not boat.get(&"engine_running") and is_equal_approx(boat.get(&"engine_flood"), 1.0), "can't start or crank it while it is under water")
	for i in 60:
		boat.call(&"_update_flood", false, step)
	_check(is_equal_approx(boat.get(&"engine_flood"), 1.0), "a locked engine does not clear by itself")
	for i in 4:
		boat.call(&"set_engine_running", true)
	_check(not boat.get(&"hydrolocked") and not boat.get(&"engine_running") and boat.get(&"engine_flood") < 0.45,
			"cranking it over clears the lock (%d%% left)" % roundi(boat.get(&"engine_flood") * 100.0))
	for i in 600:
		boat.call(&"_update_flood", false, step)
	_check(boat.get(&"engine_flood") < 0.3, "left above water, the engine dries out")
	boat.set(&"engine_flood", 0.0)
	boat.call(&"set_engine_running", true)
	boat.set(&"throttle", 1.0)
	# Start clear of the dock (leaving the berth needs steering, which this
	# test does not do), then run at full throttle.
	boat.global_position += -(main.get(&"dock") as Node3D).global_basis.z * 30.0
	boat.set(&"moored", false)
	_wait = 600


func _cut_and_leave_far() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	boat.set(&"throttle", 0.0)
	player.call(&"leave_helm")  # at sea: stand up in the boat
	_check(player.get(&"state") == 0, "can get up from the helm at sea")
	main.call(&"open_workshop")  # far from the berth: should refuse
	_check(_ws() == null, "workshop refuses while the boat is away")
	_wait = 60


func _standing_in_boat() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	_check(player.get(&"riding") == boat, "standing on the boat's deck")
	_check(player.global_position.distance_to(boat.global_position) < 3.0, "carried along with the boat")
	boat.get_node("BoardArea").call(&"interact", player)
	_check(player.get(&"state") == 1, "back at the helm")
	_wait = 5


func _drive_back() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	boat.global_transform = (main.get(&"dock").get(&"berth") as Marker3D).global_transform
	boat.linear_velocity = Vector3.ZERO
	_wait = 30


func _leave_at_dock() -> void:
	_check(player.call(&"step_ashore"), "E at the helm beside the dock steps ashore")
	_check(player.get(&"state") == 0, "steps off at the dock")
	_check(player.get(&"riding") == null and player.global_position.y > 1.0, "standing on the dock, not in the boat")
	await _frames(240)
	var boat: RigidBody3D = main.get(&"player_boat")
	var xf: Transform3D = boat.get(&"mooring_transform")
	_check(boat.get(&"moored"), "boat is tied up")
	_check(Vector2(xf.origin.x - boat.global_position.x, xf.origin.z - boat.global_position.z).length() < 1.0,
			"boat lies alongside where it was tied")
	_check(player.get(&"state") == 0 and player.global_position.y > 1.0, "still on the dock after the boat settles")
	# One press from the dock takes you aboard and to the helm.
	var board: Interactable = boat.get_node("BoardFromShore")
	_check(board.enabled, "boarding from the dock is offered")
	board.interact(player)
	_check(player.get(&"state") == 1, "boarded from the dock straight to the helm")
	await _frames(10)
	_check(player.call(&"step_ashore"), "and back ashore")
	_wait = 30


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _remove_and_relaunch() -> void:
	_check(main.get(&"player_boat") == null, "boat comes out of the water for the workshop")
	var ed: DesignEditor = _ws().get(&"editor")
	ed.remove_at(Vector3i(2, 1, -2))
	Inventory.add(&"hull_aluminium", 3)
	_ws().call(&"request_launch")
	_wait = 30


## Walk off the land end of the dock in several directions, up the hill
## beside it: the player must stay on top of the ground, never inside it.
func _walk_ashore() -> void:
	var island: Node = main.get_node("Island")
	var spawn: Vector3 = player.global_position
	var site: Dictionary = island.call(&"harbour_site")
	var inland: Vector3 = -(site["outward"] as Vector3)
	var worst := 99.0
	var furthest := 0.0
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2]:
		player.global_position = spawn
		player.velocity = Vector3.ZERO
		var dir := inland.rotated(Vector3.UP, turn)
		player.set(&"_yaw", atan2(-dir.x, -dir.z))
		Input.action_press(&"move_forward")
		for i in 300:
			await get_tree().physics_frame
			var p := player.global_position
			if (island.call(&"height_at", p.x, p.z) as float) < 1.5:
				continue  # still on the dock
			# The real ground surface: a ray straight down onto the terrain.
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0, 1)
			q.exclude = [player.get_rid()]
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				worst = minf(worst, p.y - (hit["position"] as Vector3).y)
		Input.action_release(&"move_forward")
		furthest = maxf(furthest, Vector2(player.global_position.x - spawn.x, player.global_position.z - spawn.z).length())
	print("  lowest feet-above-ground on the hill: %.2f m, furthest walked %.1f m" % [worst, furthest])
	_check(worst > -0.2, "walking ashore stays on top of the hill")
	_check(furthest > 8.0, "can walk off the dock onto land")
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	_wait = 10


func _compass_shows_town() -> void:
	var hud: Node = main.get_node_or_null("HUD")
	if hud == null:
		for c in main.get_children():
			if c is CanvasLayer and c.has_method(&"bearing_of"):
				hud = c
	_check(hud != null, "HUD is present")
	if hud:
		var found := false
		for l: Label in hud.get(&"_compass_marks"):
			if l.text.contains("Harbour Town"):
				found = true
		_check(found, "compass lists Harbour Town")
	_check(main.get_node("PersonalDock").get_node_or_null("TownSignpost") != null, "dock has a signpost to town")


func _walk_into_sea() -> void:
	player.global_position = Vector3(0, -5, 900)
	_wait = 120


func _swimming() -> void:
	_check(player.get(&"state") == 3, "falling in the sea means swimming")
	var surface := Waves.height_at(player.global_position.x, player.global_position.z)
	# Floats head-up, chest about 1.4 m under the moving surface.
	_check(player.global_position.y > surface - 1.8, "a swimmer floats")
	player.set(&"swim_time", 1000.0)
	_wait = 5


func _done() -> void:
	_check(player.get(&"state") == 0 and player.global_position.y > 0.0, "player is rescued from the sea")
	for e in _errors.errors:
		_failures.append("error: " + e)
		print("  FAIL  error: " + e)
	print("%d failure(s)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
