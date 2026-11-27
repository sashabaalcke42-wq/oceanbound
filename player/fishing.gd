extends Node
## Rod fishing, from a dock, the shore or a stopped boat.
##
## Press F to cast a few metres ahead. After a wait (shorter with bait) a fish
## bites; press F within a couple of seconds to land it. What you catch depends
## on the water depth where the line went in: sardines and flathead in the
## shallows, snapper and kingfish further out, tuna only in the deep.

enum State { IDLE, WAITING, BITE }

const CAST_DISTANCE := 6.0
const WAIT_MIN := 8.0
const WAIT_MAX := 18.0
const BAIT_FACTOR := 0.5
const BITE_WINDOW := 2.5
## Moving this far on foot, or faster than this in a boat, reels the line in.
const MOVE_LIMIT := 2.5
const BOAT_SPEED_LIMIT := 1.2
const ROD := &"rod_basic"
const BAIT := &"bait_pack"

var state := State.IDLE
var timer := 0.0
var cast_point := Vector3.ZERO
var depth := 0.0
var using_bait := false
var rng := RandomNumberGenerator.new()

var _player: Node3D
var _origin := Vector3.ZERO
var _float: MeshInstance3D
var _rod: MeshInstance3D
var _line: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _bite_mark: Label3D
var _splash: CPUParticles3D
## The "F: Fish here" hint is showing.
var _hinting := false
var _hint_timer := 0.0
## Where the hand holds the rod (world space) while fishing, or null.
var rod_grip: Variant = null


func _ready() -> void:
	_player = get_parent()
	rng.randomize()
	# A red and white float where the line goes in.
	_float = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.09
	ball.height = 0.18
	_float.mesh = ball
	_float.material_override = BuildKit.material(Color(0.9, 0.15, 0.1), 0.4)
	_float.top_level = true
	_float.visible = false
	add_child.call_deferred(_float)
	# A rod in the hand and a line out to the float while fishing.
	_rod = MeshInstance3D.new()
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.008
	rod_mesh.bottom_radius = 0.018
	rod_mesh.height = 1.9
	_rod.mesh = rod_mesh
	_rod.material_override = BuildKit.material(Color(0.15, 0.15, 0.17), 0.4)
	_rod.top_level = true
	_rod.visible = false
	add_child.call_deferred(_rod)
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.95, 0.95, 0.9)
	_line.material_override = line_mat
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child.call_deferred(_line)
	# A big "!" over the float and a splash when a fish takes the bait.
	_bite_mark = Label3D.new()
	_bite_mark.text = "!"
	_bite_mark.font_size = 96
	_bite_mark.outline_size = 18
	_bite_mark.modulate = Color(1.0, 0.85, 0.2)
	_bite_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bite_mark.no_depth_test = true
	_bite_mark.fixed_size = true
	_bite_mark.pixel_size = 0.0009
	_bite_mark.top_level = true
	_bite_mark.visible = false
	add_child.call_deferred(_bite_mark)
	_splash = CPUParticles3D.new()
	_splash.emitting = false
	_splash.one_shot = true
	_splash.amount = 24
	_splash.lifetime = 0.7
	_splash.explosiveness = 0.9
	_splash.direction = Vector3.UP
	_splash.spread = 35.0
	_splash.initial_velocity_min = 1.5
	_splash.initial_velocity_max = 3.0
	_splash.gravity = Vector3(0, -9.8, 0)
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.0
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.07
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.9, 0.97, 1.0)
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.render_priority = 10
	drop.material = drop_mat
	_splash.mesh = drop
	_splash.top_level = true
	add_child.call_deferred(_splash)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"fish"):
		press()


## The F key: cast, strike, or reel in, depending on the state.
func press() -> void:
	match state:
		State.IDLE:
			cast()
		State.WAITING:
			_stop("You reel in your line.")
		State.BITE:
			land()


func cast() -> bool:
	var pstate: int = _player.get(&"state")
	if pstate == 2:  # in a menu
		return false
	if Inventory.count(ROD) == 0:
		EventBus.notify.emit("You need a fishing rod. The general store in town sells them.")
		return false
	var boat = _player.get(&"vessel") if pstate == 1 else null
	if boat and absf(boat.get(&"speed_ms")) > BOAT_SPEED_LIMIT:
		EventBus.notify.emit("Slow down to fish.")
		return false
	var facing: Vector3 = _player.call(&"facing")
	cast_point = _player.global_position + facing * CAST_DISTANCE
	depth = _depth_at(cast_point)
	if depth < 0.5:
		EventBus.notify.emit("There's no water to fish in there.")
		return false
	if catchable(depth).is_empty():
		EventBus.notify.emit("Too shallow for fish here.")
		return false
	using_bait = Inventory.count(BAIT) > 0
	timer = rng.randf_range(WAIT_MIN, WAIT_MAX) * (BAIT_FACTOR if using_bait else 1.0)
	_origin = _player.global_position
	if pstate == 0:
		_player.set(&"_body_yaw", atan2(-facing.x, -facing.z))  # turn to face the water
	state = State.WAITING
	_hinting = false
	EventBus.activity_changed.emit("Line out in %d m of water%s. Wait for the float to bob, then press F.\n(F now reels in. Could bite here: %s)" % [
		roundi(depth), ", with bait" if using_bait else "", fish_names(depth)])
	return true


## The fish that live at this depth, for showing the player: "sardine, flathead".
static func fish_names(d: float) -> String:
	var names: Array[String] = []
	for def in catchable(d):
		names.append(def.display_name.to_lower())
	return ", ".join(names)


## Where a cast would land, and how deep the water is there; -1 if fishing
## is not possible right now (no rod, swimming, in a menu, boat moving).
func cast_preview() -> float:
	var pstate: int = _player.get(&"state")
	if pstate == 2 or pstate == 3 or Inventory.count(ROD) == 0:
		return -1.0
	if pstate == 1:
		var boat = _player.get(&"vessel")
		if boat == null or absf(boat.get(&"speed_ms")) > BOAT_SPEED_LIMIT:
			return -1.0
	var facing: Vector3 = _player.call(&"facing")
	var d := _depth_at(_player.global_position + facing * CAST_DISTANCE)
	return d if d >= 0.5 and not catchable(d).is_empty() else -1.0


## Tell the player they can fish when they face water worth fishing.
func _update_hint(delta: float) -> void:
	_hint_timer -= delta
	if _hint_timer > 0.0:
		return
	_hint_timer = 0.25
	var d := cast_preview() if state == State.IDLE else -1.0
	if d > 0.0:
		_hinting = true
		EventBus.activity_changed.emit("F: Fish here  (%d m deep: %s)" % [roundi(d), fish_names(d)])
	elif _hinting:
		_hinting = false
		EventBus.activity_changed.emit("")


## Strike when a fish is biting. Returns the fish id, or &"" if nothing.
func land() -> StringName:
	if state != State.BITE:
		return &""
	var fish := pick_fish(depth)
	if using_bait:
		Inventory.remove(BAIT)
	if fish == &"":
		_stop("Nothing on the hook.")
		return &""
	Inventory.add(fish)
	_stop("You caught a %s! The market pays about $%d." % [ItemLibrary.name_of(fish).to_lower(), Economy.fish_price(fish)])
	return fish


## Fish that live at this depth.
static func catchable(d: float) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for def in ItemLibrary.items_in(ItemDef.Category.FISH):
		if d >= def.min_depth and d <= def.max_depth:
			out.append(def)
	return out


## A fish for this depth, weighted by how common each one is.
func pick_fish(d: float) -> StringName:
	var pool := catchable(d)
	var total := 0.0
	for def in pool:
		total += def.rarity_weight
	var roll := rng.randf() * total
	for def in pool:
		roll -= def.rarity_weight
		if roll <= 0.0:
			return def.id
	return pool.back().id if not pool.is_empty() else &""


func _process(delta: float) -> void:
	_update_hint(delta)
	var fishing := state != State.IDLE and _float.is_inside_tree()
	_float.visible = fishing
	_rod.visible = fishing
	_line.visible = fishing
	_bite_mark.visible = fishing and state == State.BITE
	if not fishing:
		rod_grip = null
		return
	var bob := 0.0
	if state == State.BITE:
		# Dragged under and back, hard: a fish is on.
		bob = -0.3 * absf(sin(Time.get_ticks_msec() * 0.012))
	var surface := Waves.height_at(cast_point.x, cast_point.z)
	_float.global_position = Vector3(cast_point.x, surface + bob, cast_point.z)
	_bite_mark.global_position = Vector3(cast_point.x, surface + 0.9, cast_point.z)
	# The rod: held at the right hand, raised up and out towards the float.
	var p := _player.global_position
	var to_float := Vector3(cast_point.x - p.x, 0.0, cast_point.z - p.z).normalized()
	var right := to_float.cross(Vector3.UP).normalized()
	var butt := p + Vector3.UP * 1.0 + right * 0.25 + to_float * 0.2
	var rod_dir := (to_float + Vector3.UP * (1.3 if state == State.BITE else 0.9)).normalized()
	var tip := butt + rod_dir * 1.9
	rod_grip = butt + rod_dir * 0.3
	_rod.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, rod_dir)), (butt + tip) * 0.5)
	# The line hangs from the tip to the float in a shallow curve.
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var end := _float.global_position + Vector3.UP * 0.08
	var sag := 0.05 if state == State.BITE else 0.6
	for i in 13:
		var k := i / 12.0
		_line_mesh.surface_add_vertex(tip.lerp(end, k) - Vector3.UP * sag * 4.0 * k * (1.0 - k))
	_line_mesh.surface_end()


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	if not _still_fishing():
		_stop("You reel in your line to move.")
		return
	timer -= delta
	if timer > 0.0:
		return
	if state == State.WAITING:
		state = State.BITE
		timer = BITE_WINDOW
		_splash.global_position = cast_point + Vector3.UP * 0.05
		_splash.restart()
		EventBus.activity_changed.emit("FISH ON!  Press F now!")
	else:
		_stop("It got away.")


func _still_fishing() -> bool:
	var pstate: int = _player.get(&"state")
	if pstate == 2:
		return false
	if pstate == 1:
		var boat = _player.get(&"vessel")
		return boat != null and absf(boat.get(&"speed_ms")) <= BOAT_SPEED_LIMIT * 1.5
	return _player.global_position.distance_to(_origin) <= MOVE_LIMIT


func _stop(message: String) -> void:
	state = State.IDLE
	EventBus.activity_changed.emit("")
	if message != "":
		EventBus.notify.emit(message)


func _depth_at(p: Vector3) -> float:
	var island := get_tree().get_first_node_in_group(&"island")
	var ground: float = island.call(&"height_at", p.x, p.z) if island else -30.0
	return Waves.height_at(p.x, p.z) - ground if ground < 0.0 else 0.0
