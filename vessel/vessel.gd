extends RigidBody3D
## A live boat in the world. Built by VesselBuilder from a VesselDesign.
##
## Physics model ("believable arcade"):
## - Buoyancy: each hull column pushes up in proportion to how much of it is
##   under the wave surface, at its own position, so boats pitch and roll on
##   waves and a lopsided design lists.
## - Drag: light along the hull, heavy sideways, so boats carve turns rather
##   than slide. Above about twice hull speed the hull starts planing and
##   forward drag drops.
## - Thrust: each engine pushes at its propeller, only while the propeller is
##   in the water. Outboards steer by swinging their thrust.
## Tuning numbers live in `profile` so they can be adjusted without code.

signal engine_state_changed(running: bool)
signal fuel_empty

const GRAVITY := 9.81

## Drag coefficients are per square metre of waterplane; rotational damping
## values are decay rates per second.
const DEFAULT_PROFILE := {
	"drag_forward": 3.2,
	"drag_lateral": 70.0,
	"drag_lateral_linear": 160.0,
	"planing_drag_factor": 0.55,
	"heave_damping": 900.0,
	"yaw_damping": 1.6,
	"yaw_damping_per_ms": 0.55,
	"roll_pitch_damping": 1.2,
	"reverse_thrust_factor": 0.4,
	"thrust_height_assist": 0.75,
	"throttle_rate": 0.7,
	"steer_rate": 3.0,
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

## Set every frame by whoever is at the helm (player or AI pilot).
var input_throttle_axis := 0.0
var input_steer_axis := 0.0
var input_throttle_zero := false

## Read-only telemetry for the HUD and tests.
var speed_ms := 0.0
var submerged_ratio := 0.0

var _payloads := {}  # key -> [mass, local position]
var _helm_occupant: Node3D


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
	_add_board_area()


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
	if on == engine_running:
		return
	engine_running = on
	if not on:
		throttle = 0.0
	engine_state_changed.emit(on)


## Extra weight on board, such as the player or cargo.
func set_payload(key: StringName, mass_kg: float, local_pos: Vector3) -> void:
	_payloads[key] = [mass_kg, local_pos]
	_apply_mass_properties()


func clear_payload(key: StringName) -> void:
	_payloads.erase(key)
	_apply_mass_properties()


func set_helm_occupant(who: Node3D) -> void:
	_helm_occupant = who
	if who:
		set_payload(&"helm", 80.0, stats["helm_position"])
	else:
		clear_payload(&"helm")
		input_throttle_axis = 0.0
		input_steer_axis = 0.0


func helm_occupant() -> Node3D:
	return _helm_occupant


func _physics_process(delta: float) -> void:
	_update_controls(delta)
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

	# Hull drag in the boat's own frame (-Z is forward).
	var v_local := xf.basis.inverse() * linear_velocity
	speed_ms = -v_local.z
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

	_apply_thrust(xf, delta)


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


func _apply_thrust(xf: Transform3D, delta: float) -> void:
	if not engine_running:
		return
	for e: Dictionary in stats["engines"]:
		var burn: float = e["burn"] * maxf(absf(throttle), 0.1) * delta / 3600.0
		fuel_l = maxf(fuel_l - burn, 0.0)
		var prop: Vector3 = xf * (e["pos"] as Vector3)
		if prop.y > Waves.height_at(prop.x, prop.z):
			continue  # propeller out of the water
		var dir: Vector3 = Basis(Vector3.UP, steer * (e["steer"] as float)) * (e["forward"] as Vector3)
		var power: float = throttle if throttle >= 0.0 else throttle * profile["reverse_thrust_factor"]
		# Push from the propeller's position along the boat, but at a height
		# partway up towards the centre of mass. Real hulls get planing lift
		# that resists the bow-up moment of a low thrust line; this stands in
		# for it without a full hydrodynamic model.
		var local_at: Vector3 = e["pos"]
		local_at.y = lerpf(local_at.y, center_of_mass.y, profile["thrust_height_assist"])
		apply_force(xf.basis * dir * (e["thrust"] as float) * power, xf * local_at - global_position)
	if fuel_l <= 0.0:
		set_engine_running(false)
		fuel_empty.emit()
		EventBus.notify.emit("The engine coughs and dies. Out of fuel.")


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


func _add_board_area() -> void:
	var area := Interactable.new()
	area.name = "BoardArea"
	area.prompt = "Take the helm"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(stats["beam"] + 1.5, 2.5, stats["length"] + 1.5)
	shape.shape = box
	var mid: Vector3 = stats["center_of_mass"]
	shape.position = Vector3(mid.x, 0.5, mid.z)
	area.add_child(shape)
	add_child(area)
	area.interacted.connect(_on_board_requested)


func _on_board_requested(by: Node) -> void:
	if not has_helm():
		EventBus.notify.emit("This boat has no helm seat to drive from.")
		return
	if _helm_occupant:
		return
	if by.has_method(&"take_helm"):
		by.call(&"take_helm", self)
