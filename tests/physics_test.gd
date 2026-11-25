extends Node3D
## Headless check of the boat physics and design round-trip.
## Run: godot --headless --path . --fixed-fps 60 res://tests/physics_test.tscn
## Prints measurements and exits with code 1 if any check fails.

var boat: RigidBody3D
var _frame := 0
var _phase := 0
var _phase_start := 0
var _failures: Array[String] = []
var _turned := 0.0
var _max_tilt := 0.0
var _dry_y := 0.0
var _drift_from := Vector3.ZERO
var _min_y := INF


func _ready() -> void:
	Waves.amplitude_scale = 0.0
	_check_design_round_trip()
	var problems: Array[String] = []
	var design := DevDesigns.test_tinny()
	var stats := VesselBuilder.compute_stats(design)
	print("Test tinny: %d blocks, %.0f kg, displacement %.0f kg, length %.2f m, beam %.2f m, %d columns, fuel %.0f L" % [
		design.blocks.size(), stats["mass"], stats["displacement_kg"], stats["length"], stats["beam"],
		stats["columns"].size(), stats["fuel_capacity"]])
	boat = VesselBuilder.build(design, problems)
	_check(boat != null, "test tinny builds (%s)" % ", ".join(problems))
	if boat == null:
		_finish()
		return
	add_child(boat)
	boat.global_position = Vector3(0, 0.4, 0)
	boat.call(&"set_helm_occupant", self)
	_check_bad_designs()


func _physics_process(_delta: float) -> void:
	if boat == null:
		return
	_frame += 1
	if OS.get_environment("TRACE") != "" and _frame % 15 == 0:
		print("phase %d t=%.2f pos=%s rot=%s v=%s w=%s sub=%.2f" % [_phase, (_frame - _phase_start) / 60.0,
			boat.global_position, boat.global_rotation_degrees, boat.linear_velocity, boat.angular_velocity,
			boat.get(&"submerged_ratio")])
	var t := (_frame - _phase_start) / 60.0
	match _phase:
		0:  # settle on calm water
			if t >= 6.0:
				var bottom_y: float = boat.global_position.y - 0.125
				var tilt := _tilt_deg()
				print("Calm float: hull bottom %.3f m (draft %.3f m), tilt %.2f deg, vertical speed %.3f m/s" % [
					bottom_y, -bottom_y, tilt, boat.linear_velocity.y])
				_check(-bottom_y > 0.01 and -bottom_y < 0.2, "draft is between 1 and 20 cm")
				_check(tilt < 3.0, "floats level in calm water")
				_check(absf(boat.linear_velocity.y) < 0.05, "settles")
				boat.call(&"set_engine_running", true)
				boat.set(&"input_throttle_axis", 1.0)
				_next()
		1:  # full ahead
			if t >= 20.0:
				var kn: float = boat.get(&"speed_ms") * 1.944
				print("Full ahead for 20 s: %.1f kn, throttle %.2f, fuel left %.2f L" % [kn, boat.get(&"throttle"), boat.get(&"fuel_l")])
				_check(kn > 12.0 and kn < 32.0, "top speed between 12 and 32 knots")
				_turned = 0.0
				boat.set(&"input_steer_axis", 1.0)
				_next()
		2:  # hard to starboard
			_turned += boat.angular_velocity.y / 60.0
			if t >= 6.0:
				var turned := rad_to_deg(_turned)
				var v_local: Vector3 = boat.global_basis.inverse() * boat.linear_velocity
				print("Hard right for 6 s: heading changed %.0f deg, %.1f kn, sideslip %.2f m/s, heel %.1f deg" % [
					turned, boat.get(&"speed_ms") * 1.944, v_local.x, rad_to_deg(boat.global_rotation.z)])
				_check(turned < -60.0, "turns to starboard (clockwise)")
				_check(turned > -360.0, "turn rate is not twitchy (under 60 deg/s)")
				_check(absf(v_local.x) < absf(v_local.z) * 0.5, "carves rather than slides")
				boat.set(&"input_steer_axis", 0.0)
				boat.set(&"input_throttle_axis", 0.0)
				boat.set(&"input_throttle_zero", true)
				_next()
		3:  # cut throttle, coast down
			if t >= 12.0:
				var kn: float = boat.get(&"speed_ms") * 1.944
				print("Throttle cut for 12 s: %.2f kn" % kn)
				_check(kn < 3.0, "slows down when throttle is cut")
				boat.set(&"input_throttle_zero", false)
				_next()
		4:  # normal waves, idling. Waves build up over 4 s, then 30 s measured.
			Waves.amplitude_scale = minf(t / 4.0, 1.0)
			if t > 4.0:
				_max_tilt = maxf(_max_tilt, _tilt_deg())
				_min_y = minf(_min_y, boat.global_position.y)
			if t >= 34.0:
				print("30 s in normal waves: max tilt %.1f deg, lowest point %.2f m, submerged ratio %.2f" % [
					_max_tilt, _min_y, boat.get(&"submerged_ratio")])
				_check(_max_tilt < 30.0, "does not capsize in normal waves")
				_check(_min_y > -2.5, "stays afloat in normal waves")
				var water: float = boat.get(&"water_l")
				print("Water shipped in normal waves: %.1f L of %.0f" % [water, boat.get(&"stats")["bilge_capacity_l"]])
				_check(boat.call(&"water_fraction") < 0.15, "ships little water in normal waves")
				Waves.amplitude_scale = 0.0
				boat.set(&"water_l", 0.0)
				_next()
		5:  # calm again; measure the draft, then put water in the boat
			if is_equal_approx(t, 4.0):
				_dry_y = boat.global_position.y
				boat.set(&"water_l", 150.0)
			if t >= 9.0:
				var sank: float = _dry_y - boat.global_position.y
				print("150 L of water aboard: sits %.1f cm lower" % (sank * 100.0))
				_check(sank > 0.02, "water aboard weighs the boat down")
				boat.call(&"bail", 1000.0)
				_check(boat.get(&"water_l") == 0.0, "bailing empties the boat")
				boat.call(&"set_engine_running", false)
				Waves.wind_speed = 8.0
				_drift_from = boat.global_position
				_next()
		6:  # engine off in an 8 m/s wind: drifts downwind
			if t >= 15.0:
				var moved: Vector3 = boat.global_position - _drift_from
				moved.y = 0.0
				print("15 s adrift in 16 kn of wind: moved %.1f m, %.0f deg off the wind" % [
					moved.length(), rad_to_deg(moved.angle_to(Waves.wind))])
				_check(moved.length() > 2.0, "wind pushes a drifting boat")
				_check(moved.angle_to(Waves.wind) < deg_to_rad(60.0), "and pushes it downwind")
				boat.call(&"moor_here")
				_drift_from = boat.global_position
				_next()
		7:  # moored in the same wind: the lines hold it
			if t >= 15.0:
				var moved: Vector3 = boat.global_position - _drift_from
				moved.y = 0.0
				print("15 s moored in the wind: moved %.2f m" % moved.length())
				_check(moved.length() < 1.0, "mooring lines hold the boat")
				Waves.wind_speed = 5.0
				boat.set(&"moored", false)
				# Overload it and take it into a rough sea.
				boat.call(&"set_payload", &"cargo", 900.0, boat.get(&"stats")["center_of_mass"])
				_next()
		8:
			Waves.amplitude_scale = minf(t / 4.0, 1.0) * 2.0
			if t >= 30.0:
				var water: float = boat.get(&"water_l")
				print("Overloaded in a rough sea for 26 s: %.0f L of water aboard, lowest %.2f m" % [water, boat.global_position.y])
				_check(water > 5.0, "an overloaded boat ships water in rough seas")
				_finish()


func _next() -> void:
	_phase += 1
	_phase_start = _frame


func _tilt_deg() -> float:
	return rad_to_deg(boat.global_basis.y.angle_to(Vector3.UP))


func _check_design_round_trip() -> void:
	var d := DevDesigns.test_tinny()
	var path := "user://round_trip_test.json"
	_check(d.save_json(path) == OK, "design saves")
	var back := VesselDesign.load_json(path)
	_check(back != null and back.blocks.size() == d.blocks.size(), "design loads with the same block count")
	if back:
		_check(JSON.stringify(back.to_dict()) == JSON.stringify(d.to_dict()), "design round-trips exactly")


func _check_bad_designs() -> void:
	var empty := VesselDesign.new()
	var problems: Array[String] = []
	_check(VesselBuilder.build(empty, problems) == null and not problems.is_empty(), "empty design is rejected")
	var heavy := VesselDesign.new()
	heavy.add_block(&"hull_aluminium", Vector3i.ZERO)
	heavy.add_block(&"outboard_15hp", Vector3i(0, -1, 1))
	problems.clear()
	_check(VesselBuilder.build(heavy, problems) == null, "overweight design is rejected: %s" % ", ".join(problems))


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	print("%d failure(s)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)
