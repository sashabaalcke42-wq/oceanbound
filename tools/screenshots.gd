extends Node
## Development helper: loads the main scene, plays a short scripted tour and
## saves screenshots. Run with a display (or xvfb-run):
##   godot --path . res://tools/screenshots.tscn -- --out=/some/folder

var out_dir := "user://screenshots"
var main: Node
var _shots := [
	# [seconds after start, name, setup method, seconds of setup lead time]
	[3.0, "01_dock_on_foot", &"_shot_dock", 1.0],
	[6.0, "02_workshop_tutorial", &"_shot_workshop_start", 2.0],
	[9.0, "03_workshop_complete", &"_shot_workshop_done", 2.0],
	[12.0, "04_launched", &"_shot_launched", 2.0],
	[24.0, "05_underway", &"_shot_underway", 10.0],
	[27.0, "06_island_aerial", &"_shot_aerial", 1.0],
]
var _t := 0.0
var _next := 0
var _cam: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	_cam = Camera3D.new()
	_cam.far = 6000.0
	add_child(_cam)


func _process(delta: float) -> void:
	_t += delta
	if _next >= _shots.size():
		get_tree().quit()
		return
	var shot: Array = _shots[_next]
	if _t >= shot[0] - shot[3] and not get_meta(&"setup_%d" % _next, false):
		set_meta(&"setup_%d" % _next, true)
		call(shot[2])
	if _t >= shot[0]:
		var img := get_viewport().get_texture().get_image()
		var path: String = out_dir.path_join(shot[1] + ".png")
		img.save_png(path)
		print("saved ", path)
		_next += 1


func _player() -> Node3D:
	return main.get_node("Player")


func _place_blueprint(covers: Callable) -> void:
	var ed: DesignEditor = main.get(&"workshop").get(&"editor")
	for e in StarterKit.blueprint().blocks:
		if covers.call(e) and not ed.matches_blueprint_entry(e):
			ed.place(e["id"], e["cell"], e["rot"])


func _shot_dock() -> void:
	var p := _player()
	p.set(&"_yaw", PI * 0.85)
	p.set(&"_pitch", -0.15)


func _shot_workshop_start() -> void:
	main.call(&"open_workshop")
	var ws: Node3D = main.get(&"workshop")
	ws.set(&"_cam_yaw", 2.4)
	ws.set(&"_cam_pitch", -0.6)
	_place_blueprint(func(e): return e["id"] == &"hull_aluminium" and e["cell"].y == 0)


func _shot_workshop_done() -> void:
	_place_blueprint(func(_e): return true)


func _shot_launched() -> void:
	main.get(&"workshop").call(&"request_launch")
	var boat: Node3D = main.get(&"player_boat")
	_cam.global_position = boat.global_position + boat.global_basis * Vector3(4.5, 2.6, 4.0)
	_cam.look_at(boat.global_position + Vector3(0, 0.2, 0))
	_cam.current = true


func _shot_underway() -> void:
	var boat: RigidBody3D = main.get(&"player_boat")
	var p := _player()
	p.call(&"take_helm", boat)
	boat.call(&"set_engine_running", true)
	boat.set(&"throttle", 0.8)
	p.get_node("CameraPivot/SpringArm3D/Camera3D").current = true
	p.set(&"_yaw", boat.global_rotation.y + PI * 0.9)
	p.set(&"_pitch", -0.2)


func _shot_aerial() -> void:
	var dock: Node3D = main.get(&"dock")
	_cam.global_position = dock.global_position + Vector3(-260, 180, -260)
	_cam.look_at(Vector3(0, 10, 0))
	_cam.current = true
