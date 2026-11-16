extends CharacterBody3D
## The player on foot, and at the helm of a boat.
##
## On foot: third-person walking with mouse look. At the helm: the body is
## parked on the boat's helm seat with collisions off, and movement keys drive
## the boat instead. One camera rig serves both, with a longer arm on the water.

enum State { ON_FOOT, AT_HELM, IN_MENU }

const WALK_SPEED := 4.0
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 4.6
const MOUSE_SENSITIVITY := 0.0025
const FOOT_ARM := 3.2
const HELM_ARM := 9.0
const DISEMBARK_RANGE := 7.0

var state := State.ON_FOOT
var vessel: RigidBody3D
## Where to put the player back if they fall in the sea.
var respawn_point := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw := 0.0
var _pitch := -0.25
var _focus: Interactable

@onready var _pivot: Node3D = $CameraPivot
@onready var _arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _body_mesh: Node3D = $Body
@onready var _collider: CollisionShape3D = $Collider
@onready var _reach: Area3D = $Reach


func _ready() -> void:
	_arm.add_excluded_object(get_rid())
	_camera.current = true
	_reach.collision_mask = Interactable.LAYER
	_capture_mouse(true)


## Hand control to a full-screen menu (such as the workshop) or take it back.
func set_in_menu(on: bool) -> void:
	if on:
		state = State.IN_MENU
		_set_focus(null)
		velocity = Vector3.ZERO
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		state = State.ON_FOOT
		_camera.current = true
		_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.IN_MENU:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.3, 0.6)
	elif event is InputEventMouseButton and event.pressed:
		_capture_mouse(true)
	elif event.is_action_pressed(&"toggle_mouse"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
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
			_check_overboard()
		State.AT_HELM:
			_drive()
	_pivot.global_rotation = Vector3(_pitch, _yaw, 0.0)


func _process(_delta: float) -> void:
	if state == State.AT_HELM and is_instance_valid(vessel):
		# Follow the seat every rendered frame so the camera does not judder.
		var seat: Transform3D = vessel.call(&"helm_transform")
		global_position = seat.origin


## Called by a vessel's board area.
func take_helm(v: RigidBody3D) -> void:
	vessel = v
	state = State.AT_HELM
	_collider.disabled = true
	velocity = Vector3.ZERO
	vessel.call(&"set_helm_occupant", self)
	_arm.spring_length = HELM_ARM
	_arm.add_excluded_object(vessel.get_rid())
	_set_focus(null)
	EventBus.player_boarded.emit(vessel)
	EventBus.notify.emit("R starts the engine. W and S move the throttle, A and D steer, X cuts the throttle. E steps off at a dock.")


func leave_helm() -> void:
	var spot := _nearest_disembark_point()
	if spot == null:
		EventBus.notify.emit("Bring the boat alongside a dock to step off.")
		return
	vessel.call(&"set_helm_occupant", null)
	_arm.remove_excluded_object(vessel.get_rid())
	EventBus.player_disembarked.emit(vessel)
	state = State.ON_FOOT
	global_position = spot.global_position
	_collider.disabled = false
	_arm.spring_length = FOOT_ARM
	vessel = null


func _walk(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed(&"jump"):
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED
	velocity.x = move_toward(velocity.x, dir.x * speed, speed * 8.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, speed * 8.0 * delta)
	if dir.length_squared() > 0.01:
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
	move_and_slide()


func _drive() -> void:
	if not is_instance_valid(vessel):
		state = State.ON_FOOT
		_collider.disabled = false
		return
	vessel.set(&"input_throttle_axis", Input.get_axis(&"move_back", &"move_forward"))
	vessel.set(&"input_steer_axis", Input.get_axis(&"move_left", &"move_right"))
	vessel.set(&"input_throttle_zero", Input.is_action_pressed(&"throttle_zero"))
	_body_mesh.global_rotation.y = vessel.global_rotation.y


func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for area in _reach.get_overlapping_areas():
		if area is Interactable and area.enabled:
			var d := global_position.distance_squared_to(area.global_position)
			if d < best_d:
				best_d = d
				best = area
	_set_focus(best)


func _set_focus(i: Interactable) -> void:
	if i == _focus:
		return
	_focus = i
	EventBus.interaction_prompt_changed.emit("E: %s" % i.prompt if i else "")


func _nearest_disembark_point() -> Node3D:
	var best: Node3D = null
	var best_d := DISEMBARK_RANGE
	for n in get_tree().get_nodes_in_group(&"disembark_points"):
		var d: float = (n as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _check_overboard() -> void:
	if global_position.y < Waves.height_at(global_position.x, global_position.z) - 1.2:
		global_position = respawn_point
		velocity = Vector3.ZERO
		EventBus.notify.emit("You swim back to your dock, dripping wet.")


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
