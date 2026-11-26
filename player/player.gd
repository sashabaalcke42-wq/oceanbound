extends CharacterBody3D
## The player: walking, swimming, riding on a boat's deck, and sitting at the
## helm.
##
## Velocity is always in world space. Standing on a boat, the "ground" moves:
## the player is carried at the deck's own velocity (including its turning),
## and keeps that momentum when they jump or fall off. Their weight is added
## to the boat where they stand, so walking to one side makes it list.
## At the helm the body sits on the seat and the movement keys drive the boat.
## V switches between third and first person.

enum State { ON_FOOT, AT_HELM, IN_MENU, SWIMMING }

const WALK_SPEED := 3.0
const RUN_SPEED := 6.2
const SWIM_SPEED := 1.3
const SWIM_SPRINT := 2.1
const JUMP_VELOCITY := 4.4
const GROUND_ACCEL := 22.0   # m/s² towards the wanted speed: quick but not instant
const GROUND_DECEL := 28.0
const AIR_ACCEL := 4.0
## Grace periods: a jump still works just after walking off an edge, and a
## jump pressed just before landing happens on landing.
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.15
## At the helm, the camera swings back behind the boat after this long
## without the mouse moving.
const CAMERA_FOLLOW_DELAY := 1.2
const MOUSE_SENSITIVITY := 0.0025
const BODY_MASS := 80.0
const FOOT_ARM := 3.2
const HELM_ARM := 7.5
const EYE_HEIGHT := 1.62
const SIT_EYE_HEIGHT := 1.12
## Chest depth at which wading turns into swimming, and where the swimmer floats.
const SWIM_DEPTH := 1.15
const FLOAT_DEPTH := 1.4
## After this long in the water, someone fishes you out.
const RESCUE_SECONDS := 120.0
## Litres per second a person can bail with a bucket.
const BAIL_RATE := 1.2

var state := State.ON_FOOT
## The boat at whose helm we sit.
var vessel: RigidBody3D
## The boat whose deck we are standing on, if any.
var riding: RigidBody3D
var first_person := false
## Where to put the player back if they are rescued from the sea.
var respawn_point := Vector3.ZERO
var swim_time := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw := 0.0
var _pitch := -0.25
var _body_yaw := 0.0
var _focus: Interactable
var _was_on_floor := true
var _last_vy := 0.0
var _payload_pos := Vector3(INF, INF, INF)
var _ground_vel := Vector3.ZERO
## Seconds since we last touched the floor (smooths over tiny hops on a deck).
var _air_time := 0.0
var _jump_buffer := 0.0
var _mouse_idle := 0.0
## What E does at the helm right now, shown as the prompt.
var _helm_prompt := ""

@onready var _pivot: Node3D = $CameraPivot
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _body: Node3D = $Body
@onready var _collider: CollisionShape3D = $Collider
@onready var _reach: Area3D = $Reach


func _ready() -> void:
	add_to_group(&"player")
	_arm.add_excluded_object(get_rid())
	_camera.current = true
	_reach.collision_mask = Interactable.LAYER
	_capture_mouse(true)
	var fishing := preload("res://player/fishing.gd").new()
	fishing.name = "Fishing"
	add_child(fishing)


## The flat direction the camera looks, for casting a line ahead.
func facing() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3.FORWARD


## True when on foot and not being carried along quickly by a boat, or at the
## helm of a boat that has nearly stopped. Jobs only count arrivals then.
func is_settled() -> bool:
	if state == State.AT_HELM:
		return is_instance_valid(vessel) and absf(vessel.get(&"speed_ms")) < 2.0
	return state == State.ON_FOOT and Vector2(_ground_vel.x, _ground_vel.z).length() < 2.0


## The boat we are on, whether standing or at the helm.
func current_boat() -> RigidBody3D:
	if state == State.AT_HELM and is_instance_valid(vessel):
		return vessel
	if state == State.ON_FOOT and is_instance_valid(riding):
		return riding
	return null


## Hand control to a full-screen menu (such as the workshop) or take it back.
func set_in_menu(on: bool) -> void:
	if on:
		if state == State.AT_HELM:
			if not step_ashore():
				leave_helm()
		state = State.IN_MENU
		_set_focus(null)
		velocity = Vector3.ZERO
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		state = State.ON_FOOT
		_camera.current = true
		_capture_mouse(true)


func set_first_person(on: bool) -> void:
	first_person = on
	_body.call(&"set_head_visible", not on)
	_update_camera_rig()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.IN_MENU:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_idle = 0.0
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.4, 1.2 if first_person else 0.6)
	elif event is InputEventMouseButton and event.pressed:
		_capture_mouse(true)
	elif event.is_action_pressed(&"toggle_mouse"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed(&"view_toggle"):
		set_first_person(not first_person)
	elif event.is_action_pressed(&"interact"):
		if state == State.AT_HELM:
			leave_helm()
		elif _focus:
			_focus.interact(self)
	elif event.is_action_pressed(&"engine_toggle") and state == State.AT_HELM:
		vessel.call(&"set_engine_running", not vessel.get(&"engine_running"))


func _physics_process(delta: float) -> void:
	match state:
		State.ON_FOOT:
			_walk(delta)
			_update_focus()
			_update_payload()
			_check_water()
		State.SWIMMING:
			_swim(delta)
			_update_focus()
		State.AT_HELM:
			_drive()
			_update_helm_prompt()
	if state != State.AT_HELM and Input.is_action_pressed(&"bail"):
		_bail(delta)


func _process(delta: float) -> void:
	_mouse_idle += delta
	if state == State.AT_HELM and is_instance_valid(vessel):
		# Follow the seat every rendered frame so the camera does not judder.
		var seat: Transform3D = vessel.call(&"helm_transform")
		global_position = seat.origin
		_body_yaw = vessel.global_rotation.y
		_follow_boat_with_camera(delta)
	_pivot.global_rotation = Vector3(_pitch, _yaw, 0.0)
	_body.global_rotation = Vector3(0, _body_yaw, 0)
	_animate(delta)


## Called by a vessel's helm seat.
func take_helm(v: RigidBody3D) -> void:
	_clear_payload()
	vessel = v
	_set_riding(null)
	state = State.AT_HELM
	_collider.disabled = true
	velocity = Vector3.ZERO
	vessel.call(&"set_helm_occupant", self)
	_arm.add_excluded_object(vessel.get_rid())
	_update_camera_rig()
	_set_focus(null)
	EventBus.player_boarded.emit(vessel)
	EventBus.notify.emit("R starts the engine. W and S set the throttle, A and D steer, X cuts the throttle. E gets up from the seat.")


## At the helm beside a jetty and nearly stopped: tie up and step onto the
## jetty. Returns false (and does nothing) if there is nowhere to step to.
func step_ashore() -> bool:
	if not is_instance_valid(vessel):
		return false
	var boat := vessel
	if boat.linear_velocity.length() > 1.5:
		return false
	var point: Node3D = boat.call(&"nearest_landing", 7.0)
	if point == null:
		return false
	leave_helm()
	boat.call(&"moor_alongside", point.get_parent())
	_clear_payload()
	_set_riding(null)
	global_position = point.global_position + Vector3.UP * 0.1
	velocity = Vector3.ZERO
	var to_boat := boat.global_position - global_position
	_yaw = atan2(-to_boat.x, -to_boat.z) + PI
	_body_yaw = _yaw
	return true


## Swing the camera round behind the boat when the mouse has been left alone
## and the boat is moving, so steering does not leave you looking sideways.
func _follow_boat_with_camera(delta: float) -> void:
	if _mouse_idle < CAMERA_FOLLOW_DELAY or first_person:
		return
	var speed: float = absf(vessel.get(&"speed_ms"))
	if speed < 1.0:
		return
	var rate := clampf(speed / 6.0, 0.2, 1.0) * 1.6
	_yaw = lerp_angle(_yaw, vessel.global_rotation.y, 1.0 - exp(-rate * delta))


func _update_helm_prompt() -> void:
	var text := "E: Stand up"
	if is_instance_valid(vessel) and vessel.linear_velocity.length() <= 1.5 \
			and vessel.call(&"nearest_landing", 7.0) != null:
		text = "E: Tie up and step ashore"
	if text != _helm_prompt:
		_helm_prompt = text
		EventBus.interaction_prompt_changed.emit(text)


## Stand up from the helm, on the boat beside the seat.
func leave_helm() -> void:
	if not is_instance_valid(vessel):
		state = State.ON_FOOT
		_collider.disabled = false
		return
	var boat := vessel
	_helm_prompt = ""
	EventBus.interaction_prompt_changed.emit("")
	boat.call(&"set_helm_occupant", null)
	EventBus.player_disembarked.emit(boat)
	state = State.ON_FOOT
	var seat: Transform3D = boat.call(&"helm_transform")
	global_position = seat.origin + Vector3.UP * 0.35
	velocity = _point_velocity(boat, global_position)
	_set_riding(boat)
	_collider.disabled = false
	vessel = null
	_update_camera_rig()


func _walk(delta: float) -> void:
	var on_floor := is_on_floor()
	_ground_vel = _point_velocity(riding, global_position) if on_floor and is_instance_valid(riding) else Vector3.ZERO

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y))
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var speed := RUN_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED

	if on_floor:
		# Move relative to whatever we stand on.
		var rel := Vector3(velocity.x - _ground_vel.x, 0, velocity.z - _ground_vel.z)
		var target := dir * speed
		var rate := GROUND_ACCEL if target.length() > rel.length() else GROUND_DECEL
		rel = rel.move_toward(target, rate * delta)
		velocity.x = _ground_vel.x + rel.x
		velocity.z = _ground_vel.z + rel.z
		velocity.y = _ground_vel.y
		if is_instance_valid(riding):
			# Turn with the boat.
			var spin: float = riding.angular_velocity.y * delta
			_yaw += spin
			_body_yaw += spin
	if Input.is_action_just_pressed(&"jump"):
		_jump_buffer = JUMP_BUFFER
	_jump_buffer -= delta
	if (on_floor or _air_time < COYOTE_TIME) and _jump_buffer > 0.0:
		velocity.y = _ground_vel.y + JUMP_VELOCITY
		_jump_buffer = 0.0
		_air_time = COYOTE_TIME  # no second jump from the same grace period
		on_floor = false
	if not on_floor:
		velocity.y -= _gravity * delta
		velocity += dir * AIR_ACCEL * delta

	if dir.length_squared() > 0.01 and not first_person:
		_body_yaw = lerp_angle(_body_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-10.0 * delta))
	elif first_person:
		_body_yaw = _yaw
	_last_vy = velocity.y - _ground_vel.y
	move_and_slide()
	_find_floor_body()
	if is_on_floor() and _air_time > 0.25 and _last_vy < -2.5:
		_body.call(&"land", -_last_vy)
	_was_on_floor = is_on_floor()
	_air_time = 0.0 if is_on_floor() else _air_time + delta


func _swim(delta: float) -> void:
	swim_time += delta
	var surface := Waves.height_at(global_position.x, global_position.z)
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y)
	var speed := SWIM_SPRINT if Input.is_action_pressed(&"sprint") else SWIM_SPEED
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(dir * speed, 2.5 * delta)
	velocity.x = h.x
	velocity.z = h.z
	# Float with the head just above the waves, bobbing with them.
	var target_y := surface - FLOAT_DEPTH
	velocity.y += ((target_y - global_position.y) * 14.0 - velocity.y * 5.0) * delta
	# Haul yourself out onto a jetty or a low boat side.
	if Input.is_action_just_pressed(&"jump") and is_on_wall():
		velocity.y = 5.2
		velocity += dir * 1.5
	if dir.length_squared() > 0.01:
		_body_yaw = lerp_angle(_body_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-4.0 * delta))
	move_and_slide()
	_find_floor_body()
	var depth := surface - global_position.y
	if (is_on_floor() and depth < SWIM_DEPTH - 0.2) or depth < 0.6:
		state = State.ON_FOOT
		swim_time = 0.0
	elif swim_time > RESCUE_SECONDS:
		rescue()


## Fished out of the sea and put back on the dock.
func rescue() -> void:
	global_position = respawn_point
	velocity = Vector3.ZERO
	state = State.ON_FOOT
	swim_time = 0.0
	_set_riding(null)
	EventBus.notify.emit("A passing fisherman pulls you out and drops you back at your dock.")


func _check_water() -> void:
	var surface := Waves.height_at(global_position.x, global_position.z)
	if global_position.y < surface - SWIM_DEPTH:
		_clear_payload()
		_set_riding(null)
		state = State.SWIMMING
		swim_time = 0.0
		EventBus.notify.emit("Splash! Swim with WASD. Space climbs out at a jetty or boat side.")


func _drive() -> void:
	if not is_instance_valid(vessel):
		state = State.ON_FOOT
		_collider.disabled = false
		return
	vessel.set(&"input_throttle_axis", Input.get_axis(&"move_back", &"move_forward"))
	vessel.set(&"input_steer_axis", Input.get_axis(&"move_left", &"move_right"))
	vessel.set(&"input_throttle_zero", Input.is_action_pressed(&"throttle_zero"))
	if Input.is_action_pressed(&"bail"):
		_bail(get_physics_process_delta_time())


func _bail(delta: float) -> void:
	var boat := current_boat()
	if boat and boat.has_method(&"bail"):
		boat.call(&"bail", BAIL_RATE * delta)


## Remember which boat (if any) is under our feet.
func _find_floor_body() -> void:
	if not is_on_floor():
		return
	var found: RigidBody3D = null
	# Floor snapping does not always report a collision, so look straight down.
	var from := global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.7, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["collider"] is RigidBody3D:
		found = hit["collider"]
	if found != riding:
		_clear_payload()
		_set_riding(found)


## The boat under our feet. The camera may pass through it, but not others.
func _set_riding(b: RigidBody3D) -> void:
	if b == riding:
		return
	if is_instance_valid(riding) and riding != vessel:
		_arm.remove_excluded_object(riding.get_rid())
	riding = b
	if is_instance_valid(b):
		_arm.add_excluded_object(b.get_rid())


## Our weight on the boat, where we stand.
func _update_payload() -> void:
	if not is_instance_valid(riding) or not is_on_floor():
		return
	var local := riding.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.9)
	if local.distance_to(_payload_pos) > 0.15:
		_payload_pos = local
		riding.call(&"set_payload", &"player", BODY_MASS, local)


func _clear_payload() -> void:
	if is_instance_valid(riding) and _payload_pos.x != INF:
		riding.call(&"clear_payload", &"player")
	_payload_pos = Vector3(INF, INF, INF)


static func _point_velocity(body: RigidBody3D, at: Vector3) -> Vector3:
	if not is_instance_valid(body):
		return Vector3.ZERO
	var com := body.global_transform * body.center_of_mass
	return body.linear_velocity + body.angular_velocity.cross(at - com)


func _animate(delta: float) -> void:
	var pose: int = 0  # Pose.GROUND
	match state:
		State.AT_HELM:
			pose = 3
		State.SWIMMING:
			pose = 2
		State.ON_FOOT, State.IN_MENU:
			pose = 0 if _air_time < 0.2 or state == State.IN_MENU else 1
	var rel := velocity - _ground_vel
	if state == State.AT_HELM or state == State.IN_MENU:
		rel = Vector3.ZERO
	var local := Basis(Vector3.UP, _body_yaw).inverse() * rel
	var turn := 0.0
	if has_meta(&"last_body_yaw"):
		turn = angle_difference(get_meta(&"last_body_yaw"), _body_yaw) / maxf(delta, 0.001)
	set_meta(&"last_body_yaw", _body_yaw)
	_body.call(&"animate", delta, pose, local, turn, rel.y)
	_update_camera_rig()


func _update_camera_rig() -> void:
	var sitting := state == State.AT_HELM
	if first_person:
		_arm.spring_length = 0.0
		_pivot.position = Vector3(0, SIT_EYE_HEIGHT if sitting else EYE_HEIGHT, 0)
		# Eyes sit slightly forward of the body's centre.
		_pivot.position += Basis(Vector3.UP, _body_yaw - global_rotation.y) * Vector3(0, 0, -0.12)
	else:
		_arm.spring_length = HELM_ARM if sitting else FOOT_ARM
		_pivot.position = Vector3(0, 1.3 if sitting else EYE_HEIGHT, 0)


func _update_focus() -> void:
	# Nearest wins, but something in front of you counts as much closer than
	# something behind, so the prompt follows where you look.
	var best: Interactable = null
	var best_d := INF
	var look := facing()
	for area in _reach.get_overlapping_areas():
		if area is Interactable and area.enabled:
			var to := area.global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d > 0.05:
				d -= look.dot(to / d) * 1.2
			if d < best_d:
				best_d = d
				best = area
	_set_focus(best)


func _set_focus(i: Interactable) -> void:
	if i == _focus:
		return
	_focus = i
	EventBus.interaction_prompt_changed.emit("E: %s" % i.prompt if i else "")


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
