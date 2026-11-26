extends RigidBody3D
## A live boat in the world. Built by VesselBuilder from a VesselDesign.
##
## Physics model:
## - Buoyancy: each hull column pushes up in proportion to how much of it is
##   under the wave surface, at its own position, so boats pitch and roll on
##   waves and a lopsided design lists. People and water aboard add weight
##   where they are, so the boat trims and heels with its load.
## - Drag: light along the hull, heavy sideways, so boats carve turns rather
##   than slide. It acts on the boat's speed through the water, and the water
##   itself moves with the waves, so boats surge and get set back by swell.
##   Above about twice hull speed the hull starts planing and drag drops.
## - Wind pushes on the hull above the water and turns a drifting boat.
## - Thrust: each engine pushes at its propeller. Thrust falls off as the
##   boat approaches the propeller's pitch speed, and fades as the propeller
##   lifts towards the surface (ventilation), when the engine races.
##   Outboards steer by swinging their thrust.
## - Water aboard: waves higher than the gunwale slop in, collect in the
##   bottom of the boat, slosh to the low side and weigh it down. A bilge
##   pump or bailing gets it out. An engine whose powerhead goes under dies.
## - Mooring: left alongside a jetty, a boat is held by its lines.
## Tuning numbers live in `profile` so they can be adjusted without code.

signal engine_state_changed(running: bool)
signal fuel_empty

const GRAVITY := 9.81
const AIR_DENSITY := 1.2
const IDLE_RPM := 900.0
const MAX_RPM := 5800.0

## Drag coefficients are per square metre of waterplane; rotational damping
## values are decay rates per second.
const DEFAULT_PROFILE := {
	"drag_forward": 3.0,
	"drag_lateral": 70.0,
	"drag_lateral_linear": 160.0,
	"planing_drag_factor": 0.55,
	"heave_damping": 900.0,
	"yaw_damping": 1.6,
	"yaw_damping_per_ms": 0.55,
	"roll_pitch_damping": 1.2,
	"reverse_thrust_factor": 0.4,
	"thrust_height_assist": 0.75,
	"throttle_rate": 1.1,
	"steer_rate": 3.0,
	## Air drag on the part above the water (Cd times area fraction).
	"windage": 0.9,
	## How readily water pours in over a submerged gunwale.
	"ingress_rate": 1.7,
	## Mooring lines: spring (per kg of boat) and damping, and slack in metres.
	"mooring_spring": 0.6,
	"mooring_damping": 1.4,
	"mooring_slack": 0.4,
}

var profile: Dictionary = DEFAULT_PROFILE.duplicate()

var design: VesselDesign
var stats: Dictionary

## Throttle lever, -1 (full astern) to 1 (full ahead).
var throttle := 0.0
## Current steering, -1 (port) to 1 (starboard).
var steer := 0.0
var engine_running := false
var fuel_l := 0.0
## Engine revs, for the instruments and the engine sound.
var rpm := 0.0
## Litres of water slopping about in the bottom of the boat.
var water_l := 0.0
## Where the boat is tied up, if it is.
var moored := false
var _board_area: Interactable
var mooring_transform := Transform3D()

## Set every frame by whoever is at the helm (player or AI pilot).
var input_throttle_axis := 0.0
var input_steer_axis := 0.0
var input_throttle_zero := false

## Read-only telemetry for the HUD, effects and tests.
var speed_ms := 0.0
var submerged_ratio := 0.0
## How much of the propeller's grip is left (0 = spinning in air).
var prop_grip := 1.0

var _payloads := {}  # key -> [mass, local position]
var _helm_occupant: Node3D
var _water_shift := Vector3.ZERO
var _water_payload := [0.0, Vector3.ZERO]
## How much water has got into the engine, 0 to 1. It climbs while the
## powerhead is under water (fast when running, since the engine sucks it
## in), costs power and makes it misfire, and at 1 the engine stalls,
## hydrolocked. Above water it slowly clears; a locked engine has to be
## cranked by hand (R at the helm) to pump the water out of the cylinders.
var engine_flood := 0.0
var hydrolocked := false
var _head_wet := false
var _misfire := 0.0
var _flood_rng := RandomNumberGenerator.new()
const FLOOD_RATE_RUNNING := 0.4   # per second under water, engine running
const FLOOD_RATE_OFF := 0.08      # per second under water, engine off
const CLEAR_RATE_RUNNING := 0.06  # per second above water, running it dry
const CLEAR_RATE_OFF := 0.02
const CRANK_CLEARS := 0.15        # each pull of the starter on a locked engine
const UNLOCK_BELOW := 0.45


func setup(p_design: VesselDesign, p_stats: Dictionary) -> void:
	design = p_design
	stats = p_stats
	fuel_l = stats["fuel_capacity"]
	_apply_mass_properties()
	# We do our own water drag, so turn the default damping off.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.05
	can_sleep = false
	continuous_cd = false
	_add_helm_seat()
	var fx := preload("res://vessel/vessel_effects.gd").new()
	fx.name = "Effects"
	add_child(fx)


func _process(_delta: float) -> void:
	# Swing each outboard to where its thrust points.
	var engines: Array = stats.get("engines", [])
	for i in engines.size():
		var pivot := get_node_or_null(NodePath("Outboard%d" % i)) as Node3D
		if pivot:
			pivot.basis = Basis(Vector3.UP, steer * (engines[i]["steer"] as float))


## Where the driver's hand goes on a tiller outboard, in world space, or null
## if the boat is not steered by tiller.
func tiller_grip() -> Variant:
	for child in get_children():
		if child.name.begins_with("Outboard"):
			var m := child.get_child(0).get_node_or_null(^"TillerGrip") as Node3D
			if m:
				return m.global_position
	return null


func has_helm() -> bool:
	return stats.get("has_helm", false)


## Seat position for a helm occupant, in world space.
func helm_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(), stats["helm_position"])


func set_engine_running(on: bool) -> void:
	if on and stats["engines"].is_empty():
		EventBus.notify.emit("This boat has no engine.")
		return
	if on and fuel_l <= 0.0:
		EventBus.notify.emit("Out of fuel.")
		return
	if on and not engine_running and _head_wet:
		EventBus.notify.emit("The engine is under water. Bail the boat out first.")
		return
	if on and not engine_running and hydrolocked:
		_crank_clear()
		return
	if on == engine_running:
		return
	# A wet engine may not catch first time.
	if on and engine_flood > 0.15 and _flood_rng.randf() < engine_flood:
		EventBus.notify.emit("It turns over, coughs and won't catch. Engine %d%% flooded, try again." % roundi(engine_flood * 100.0))
		return
	engine_running = on
	if not on:
		throttle = 0.0
	engine_state_changed.emit(on)


## A pull on a hydrolocked engine: water squirts out of the plug holes.
func _crank_clear() -> void:
	engine_flood = maxf(engine_flood - CRANK_CLEARS, 0.0)
	if engine_flood < UNLOCK_BELOW:
		hydrolocked = false
		EventBus.notify.emit("Water sprays out and the engine turns over freely. Engine %d%% flooded. Press R to start." % roundi(engine_flood * 100.0))
	else:
		EventBus.notify.emit("You crank it over and water spurts out. Engine %d%% flooded, keep cranking (R)." % roundi(engine_flood * 100.0))


## How much of its power the engine makes, with water in it and the odd
## misfire.
func engine_power() -> float:
	if not engine_running:
		return 0.0
	return (1.0 - 0.65 * engine_flood) * (0.15 if _misfire > 0.0 else 1.0)


## Extra weight on board, such as the player or cargo.
func set_payload(key: StringName, mass_kg: float, local_pos: Vector3) -> void:
	_payloads[key] = [mass_kg, local_pos]
	_apply_mass_properties()


func clear_payload(key: StringName) -> void:
	if _payloads.erase(key):
		_apply_mass_properties()


func set_helm_occupant(who: Node3D) -> void:
	_helm_occupant = who
	if who:
		moored = false
		set_payload(&"helm", 80.0, stats["helm_position"] + Vector3.UP * 0.6)
	else:
		clear_payload(&"helm")
		input_throttle_axis = 0.0
		input_steer_axis = 0.0
		input_throttle_zero = false
		try_moor()


func helm_occupant() -> Node3D:
	return _helm_occupant


## Tie up if we are stopped beside a jetty or dock. Returns true if moored.
func try_moor() -> bool:
	if engine_running and absf(throttle) > 0.05:
		return false
	if linear_velocity.length() > 1.5:
		return false
	var point := nearest_landing(6.0)
	if point == null:
		return false
	moor_alongside(point.get_parent() as Node3D)
	return true


## The nearest place to step ashore (a jetty or dock's disembark point)
## within `within` metres, or null.
func nearest_landing(within: float) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for n: Node3D in get_tree().get_nodes_in_group(&"disembark_points"):
		var d := Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


## Put lines out to a jetty: the boat is drawn in parallel to it, a little
## off its side, on whichever side it already lies, facing whichever way along
## it is nearer to its current heading.
func moor_alongside(jetty: Node3D) -> void:
	if jetty == null:
		moor_here()
		return
	var inv := jetty.global_transform.affine_inverse()
	var local := inv * global_position
	var side := signf(local.x) if absf(local.x) > 0.01 else 1.0
	var deck_half := 1.2  # jetties and docks are 2.4 m wide
	var jetty_len: float = jetty.get(&"length") if jetty.get(&"length") != null else 18.0
	var target := Vector3(side * (deck_half + stats["beam"] * 0.5 + 0.6), 0.0,
			clampf(local.z, -jetty_len + 2.0, -3.0))
	var along := jetty.global_basis.z
	along.y = 0.0
	along = along.normalized()
	var fwd := -global_basis.z
	if fwd.dot(along) < 0.0:
		along = -along
	# The boat's forward (-Z) lies along `along`.
	var yaw := atan2(-along.x, -along.z)
	var origin := jetty.global_transform * target
	origin.y = global_position.y
	moored = true
	mooring_transform = Transform3D(Basis(Vector3.UP, yaw), origin)


func moor_here() -> void:
	moored = true
	mooring_transform = global_transform


## Take some litres of water out (a bucket, a pump).
func bail(litres: float) -> void:
	water_l = maxf(water_l - litres, 0.0)


## How full of water the boat is, 0 to 1.
func water_fraction() -> float:
	var cap: float = stats.get("bilge_capacity_l", 0.0)
	return water_l / cap if cap > 0.0 else 0.0


func _physics_process(delta: float) -> void:
	_update_controls(delta)
	if _board_area:
		# Only offered to someone who is not already aboard.
		var p := get_tree().get_first_node_in_group(&"player")
		_board_area.enabled = _helm_occupant == null and p != null and p.call(&"current_boat") != self
	var xf := global_transform
	var com_world := xf * center_of_mass
	var area: float = maxf(stats["waterplane_area"], 0.05)
	var total_buoyancy := 0.0

	# Buoyancy and heave damping, per hull column.
	for col: Dictionary in stats["columns"]:
		var p: Vector3 = xf * (col["pos"] as Vector3)
		var hh: float = col["half_height"]
		var surface := Waves.height_at(p.x, p.z)
		var frac := clampf((surface - (p.y - hh)) / (hh * 2.0), 0.0, 1.0)
		if frac <= 0.0:
			continue
		var lift := Waves.GRAVITY * VesselBuilder.WATER_DENSITY * (col["volume"] as float) * frac
		total_buoyancy += lift
		# Push at the centre of the submerged part of the column.
		var at := Vector3(p.x, p.y - hh + hh * frac, p.z)
		var v_point := linear_velocity + angular_velocity.cross(at - com_world)
		var damping: float = -profile["heave_damping"] * (col["area"] as float) * frac * v_point.y
		apply_force(Vector3.UP * (lift + damping), at - global_position)

	submerged_ratio = total_buoyancy / (mass * GRAVITY)
	var wet := clampf(submerged_ratio, 0.0, 1.0)

	# Hull drag in the boat's own frame (-Z is forward), against the water's
	# own movement under the waves.
	var water_vel := Waves.water_velocity(global_position.x, global_position.z)
	var v_local := xf.basis.inverse() * (linear_velocity - water_vel)
	speed_ms = -(xf.basis.inverse() * linear_velocity).z
	# Displacement hull speed, roughly 0.4 * sqrt(g * length).
	var hull_speed := 0.4 * sqrt(Waves.GRAVITY * maxf(stats["length"], 1.0))
	var planing := smoothstep(hull_speed * 2.0, hull_speed * 3.2, absf(v_local.z))
	var k_fwd: float = profile["drag_forward"] * area * lerpf(1.0, profile["planing_drag_factor"], planing)
	var k_lat: float = profile["drag_lateral"] * area
	var c_lat: float = profile["drag_lateral_linear"] * area
	var drag := Vector3(
		-(k_lat * absf(v_local.x) + c_lat) * v_local.x,
		0.0,
		-(k_fwd * absf(v_local.z) + c_lat * 0.05) * v_local.z)
	apply_central_force(xf.basis * drag * wet)

	# Rotational damping from the water, as a decay rate (per second) scaled
	# by the boat's own inertia so it behaves the same for any size of boat.
	var w_local := xf.basis.inverse() * angular_velocity
	var damp := Vector3(
		-profile["roll_pitch_damping"] * inertia.x * w_local.x,
		-(profile["yaw_damping"] + profile["yaw_damping_per_ms"] * absf(v_local.z)) * inertia.y * w_local.y,
		-profile["roll_pitch_damping"] * inertia.z * w_local.z)
	apply_torque(xf.basis * damp * wet)

	_apply_wind(xf)
	_update_flood(_powerhead_under(xf), delta)
	_apply_thrust(xf, delta)
	_update_water(xf, delta)
	_apply_mooring(delta)


func _update_controls(delta: float) -> void:
	if input_throttle_zero:
		throttle = 0.0
	else:
		throttle = clampf(throttle + input_throttle_axis * profile["throttle_rate"] * delta, -1.0, 1.0)
		# A small detent at neutral so it is easy to stop.
		if input_throttle_axis == 0.0 and absf(throttle) < 0.04:
			throttle = 0.0
	steer = move_toward(steer, input_steer_axis, profile["steer_rate"] * delta)
	if not engine_running:
		throttle = 0.0
	if engine_running and absf(throttle) > 0.05:
		moored = false
	# Revs follow the throttle with a little lag, and race when the propeller
	# loses its grip on the water.
	var target := 0.0
	if engine_running:
		target = lerpf(IDLE_RPM, MAX_RPM, absf(throttle)) * lerpf(1.25, 1.0, prop_grip)
		# Water in the engine drags the revs down, and a misfire stumbles them.
		target *= lerpf(1.0, 0.7, engine_flood) * (0.55 if _misfire > 0.0 else 1.0)
	rpm = lerpf(rpm, minf(target, MAX_RPM * 1.15), 1.0 - exp(-(3.0 if target > rpm else 1.5) * delta))


func _apply_wind(xf: Transform3D) -> void:
	# Area above the water, side-on and end-on: the boat's length or beam times
	# its freeboard. Pushes at the middle of that area.
	var rel := Waves.wind - linear_velocity
	rel.y = 0.0
	if rel.length_squared() < 0.01:
		return
	var freeboard := maxf(0.15, (1.0 - submerged_ratio) * 0.6)
	var local := xf.basis.inverse() * rel
	var side_area: float = stats["length"] * freeboard
	var end_area: float = stats["beam"] * freeboard
	var area := absf(local.x) / rel.length() * side_area + absf(local.z) / rel.length() * end_area
	var force: Vector3 = rel * rel.length() * 0.5 * AIR_DENSITY * profile["windage"] * area
	# Windage sits a little forward of the middle on most hulls, so a drifting
	# boat swings its bow downwind.
	var at := xf * (center_of_mass + Vector3(0, 0.3, -stats["length"] * 0.12)) - global_position
	apply_force(force, at)


func _apply_thrust(xf: Transform3D, delta: float) -> void:
	if not engine_running:
		prop_grip = 1.0
		return
	var grip_sum := 0.0
	for e: Dictionary in stats["engines"]:
		var burn: float = e["burn"] * maxf(absf(throttle), 0.1) * delta / 3600.0
		fuel_l = maxf(fuel_l - burn, 0.0)
		var prop: Vector3 = xf * (e["pos"] as Vector3)
		# Full grip 25 cm under the surface, none at the surface.
		var depth := Waves.height_at(prop.x, prop.z) - prop.y
		var grip := clampf((depth + 0.02) / 0.27, 0.0, 1.0)
		grip_sum += grip
		var dir: Vector3 = Basis(Vector3.UP, steer * (e["steer"] as float)) * (e["forward"] as Vector3)
		var power: float = throttle if throttle >= 0.0 else throttle * profile["reverse_thrust_factor"]
		power *= engine_power()
		# A propeller pushes less the faster the water comes at it.
		var inflow := (xf.basis.inverse() * linear_velocity).dot(e["forward"] as Vector3) * signf(power)
		var pitch: float = e.get("pitch_speed", 14.0)
		var load := clampf(1.0 - maxf(inflow, 0.0) / pitch, 0.0, 1.0)
		# Push from the propeller's position along the boat, but at a height
		# partway up towards the centre of mass. Real hulls get planing lift
		# that resists the bow-up moment of a low thrust line; this stands in
		# for it without a full hydrodynamic model.
		var local_at: Vector3 = e["pos"]
		local_at.y = lerpf(local_at.y, center_of_mass.y, profile["thrust_height_assist"])
		apply_force(xf.basis * dir * (e["thrust"] as float) * power * grip * load, xf * local_at - global_position)
	prop_grip = grip_sum / maxf(stats["engines"].size(), 1)
	if fuel_l <= 0.0:
		set_engine_running(false)
		fuel_empty.emit()
		EventBus.notify.emit("The engine coughs and dies. Out of fuel.")


## Is any engine's powerhead (its top) under the water?
func _powerhead_under(xf: Transform3D) -> bool:
	for e: Dictionary in stats["engines"]:
		var head: Vector3 = xf * (e.get("head", e["pos"]) as Vector3)
		if head.y < Waves.height_at(head.x, head.z) - 0.05:
			return true
	return false


func _update_flood(wet: bool, delta: float) -> void:
	_head_wet = wet
	_misfire = maxf(_misfire - delta, 0.0)
	if stats["engines"].is_empty():
		return
	var before := engine_flood
	if wet:
		engine_flood = minf(engine_flood + (FLOOD_RATE_RUNNING if engine_running else FLOOD_RATE_OFF) * delta, 1.0)
	elif not hydrolocked:
		engine_flood = maxf(engine_flood - (CLEAR_RATE_RUNNING if engine_running else CLEAR_RATE_OFF) * delta, 0.0)
	if engine_running:
		# A wet engine misfires, more often the wetter it is.
		if engine_flood > 0.2 and _misfire <= 0.0 and _flood_rng.randf() < engine_flood * 2.5 * delta:
			_misfire = _flood_rng.randf_range(0.12, 0.35)
		if engine_flood >= 1.0:
			hydrolocked = true
			set_engine_running(false)
			EventBus.notify.emit("The engine chokes on water and seizes: hydrolocked. Get it above water, then crank it clear with R.")
		elif before < 0.5 and engine_flood >= 0.5:
			EventBus.notify.emit("The engine is sputtering, it's taking on water!")


## Water over the gunwale comes in; the pump takes it out; it gathers in the
## bottom of the boat on whichever side is low.
func _update_water(xf: Transform3D, delta: float) -> void:
	var cap: float = stats.get("bilge_capacity_l", 0.0)
	if cap <= 0.0:
		return
	var inflow := 0.0
	for o: Dictionary in stats["openings"]:
		var p: Vector3 = xf * (o["pos"] as Vector3)
		var over := Waves.height_at(p.x, p.z) - p.y
		if over > 0.0:
			# Flow over a weir: width times head to the power 1.5.
			inflow += profile["ingress_rate"] * sqrt(o["area"] as float) * pow(over, 1.5) * 1000.0
	water_l = clampf(water_l + inflow * delta - (stats.get("pump_lps", 0.0) as float) * delta, 0.0, cap)

	# The water's centre of mass slides towards the low side, with a little lag
	# so it sloshes.
	var down := xf.basis.inverse() * Vector3.DOWN
	var ext: Vector3 = stats["bilge_extent"]
	var fill := clampf(water_l / cap, 0.0, 1.0)
	var target := Vector3(
		clampf(down.x * 4.0, -1.0, 1.0) * ext.x,
		-ext.y + ext.y * fill,
		clampf(down.z * 4.0, -1.0, 1.0) * ext.z) * (1.0 - fill * 0.7)
	_water_shift = _water_shift.lerp(target, 1.0 - exp(-2.5 * delta))
	var kg := water_l
	var pos: Vector3 = (stats["bilge_center"] as Vector3) + _water_shift
	if absf(kg - _water_payload[0]) > 0.5 or pos.distance_to(_water_payload[1]) > 0.03:
		_water_payload = [kg, pos]
		if kg > 0.2:
			set_payload(&"water", kg, pos)
		else:
			clear_payload(&"water")


func _apply_mooring(_delta: float) -> void:
	if not moored:
		return
	var off := mooring_transform.origin - global_position
	off.y = 0.0
	var slack: float = profile["mooring_slack"]
	var stretch := minf(maxf(off.length() - slack, 0.0), 1.2)
	var v := linear_velocity
	v.y = 0.0
	var f: Vector3 = off.normalized() * stretch * mass * profile["mooring_spring"] * 10.0 - v * mass * profile["mooring_damping"] * 0.5
	apply_central_force(f)
	# Hold the heading too.
	var want := mooring_transform.basis.get_euler().y
	var yaw_err := angle_difference(global_rotation.y, want)
	apply_torque(Vector3.UP * (yaw_err * 4.0 - angular_velocity.y * 3.0) * inertia.y)


func _apply_mass_properties() -> void:
	var m: float = stats["mass"]
	var moment: Vector3 = stats["center_of_mass"] * m
	var points: Array = stats["point_masses"].duplicate()
	for key in _payloads:
		var pm: Array = _payloads[key]
		m += pm[0]
		moment += pm[1] * pm[0]
		points.append(pm)
	var com := moment / m
	var inertia := Vector3.ZERO
	for pm in points:
		var r: Vector3 = (pm[1] as Vector3) - com
		var pmass: float = pm[0]
		inertia += pmass * Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y)
	mass = m
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com
	self.inertia = inertia.max(Vector3.ONE * 0.5)


## The helm seat: walk up to it on deck and press E to take the helm.
func _add_helm_seat() -> void:
	if not has_helm():
		return
	var area := Interactable.new()
	area.name = "BoardArea"
	area.prompt = "Take the tiller" if stats.get("tiller_count", 0) > 0 else "Take the helm"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.8, 1.4)
	shape.shape = box
	area.add_child(shape)
	area.position = stats["helm_position"] + Vector3.UP * 0.6
	add_child(area)
	area.interacted.connect(_on_helm_requested)
	# From a dock or jetty beside the boat, one press takes you aboard and
	# straight to the helm.
	var centre := Vector3.ZERO
	for col: Dictionary in stats["columns"]:
		centre += col["pos"]
	centre /= maxf(stats["columns"].size(), 1)
	_board_area = Interactable.new()
	_board_area.name = "BoardFromShore"
	_board_area.prompt = "Step aboard and take the helm"
	var bshape := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(stats["beam"] + 1.5, 3.0, stats["length"] + 1.0)
	bshape.shape = bbox
	_board_area.add_child(bshape)
	_board_area.position = Vector3(centre.x, (stats["helm_position"] as Vector3).y + 0.6, centre.z)
	add_child(_board_area)
	_board_area.interacted.connect(_on_helm_requested)


func _on_helm_requested(by: Node) -> void:
	if _helm_occupant:
		return
	if by.has_method(&"take_helm"):
		by.call(&"take_helm", self)
