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
	state = State.WAITING
	EventBus.activity_changed.emit("Fishing in %d m of water%s. F reels in." % [roundi(depth), ", with bait" if using_bait else ""])
	return true


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


func _process(_delta: float) -> void:
	_float.visible = state != State.IDLE and _float.is_inside_tree()
	if _float.visible:
		var bob := 0.0
		if state == State.BITE:
			bob = -0.12 * absf(sin(Time.get_ticks_msec() * 0.02))
		_float.global_position = Vector3(cast_point.x, Waves.height_at(cast_point.x, cast_point.z) + bob, cast_point.z)


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
		EventBus.activity_changed.emit("Something's biting! Press F!")
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
