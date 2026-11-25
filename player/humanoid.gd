extends Node3D
## The player's body: a jointed figure built from simple shapes, animated in
## code. No imported model or animation files, so it is easy to restyle.
##
## Proportions are for a person about 1.8 m tall. The figure faces -Z.
## Call `animate()` every frame with how the body is moving; it blends
## between standing, walking, running, swimming, falling, landing and sitting.
##
## Joint rotations: a positive x rotation swings a limb forward (towards -Z).

enum Pose { GROUND, AIR, SWIM, SIT }

const HIP_HEIGHT := 0.93
const THIGH := 0.44
const SHIN := 0.44
const UPPER_ARM := 0.3
const FOREARM := 0.28
const SHOULDER_Y := 0.48  # above the hips
const WALK_STRIDE := 1.3   # metres per full step cycle at walking pace
const RUN_STRIDE := 2.3

var skin_color := Color(0.87, 0.68, 0.53)
var shirt_color := Color(0.85, 0.42, 0.12)  # a high-vis sailing jacket
var trouser_color := Color(0.2, 0.24, 0.3)
var boot_color := Color(0.16, 0.12, 0.1)
var hair_color := Color(0.24, 0.16, 0.1)

var _hips: Node3D
var _spine: Node3D
var _neck: Node3D
var _head_mesh: Node3D
var _legs: Array[Dictionary] = []  # {thigh, knee, foot}
var _arms: Array[Dictionary] = []  # {shoulder, elbow}

var _phase := 0.0
var _land := 0.0       # 0..1, how hard we just landed (crouch)
var _lean := Vector2.ZERO  # forward and sideways body lean
var _breath := 0.0
var _blend := {}       # smoothed joint angles


func _ready() -> void:
	_build()


## Show or hide the head (hidden in first person so it does not block the view).
func set_head_visible(on: bool) -> void:
	_head_mesh.visible = on


## Drive the animation.
## `local_vel`: velocity in the body's own frame (x right, z back).
## `turn_rate`: radians per second around the vertical.
## `vertical_speed`: for falling and landing.
func animate(delta: float, pose: Pose, local_vel: Vector3, turn_rate := 0.0, vertical_speed := 0.0) -> void:
	var speed := Vector2(local_vel.x, local_vel.z).length()
	var forward := -local_vel.z
	_breath += delta * 1.6
	_land = move_toward(_land, 0.0, delta * 3.0)

	# Running blends in from 4 m/s; the stride gets longer and arms pump.
	var run := smoothstep(3.6, 6.0, speed)
	var stride := lerpf(WALK_STRIDE, RUN_STRIDE, run)
	if pose == Pose.GROUND:
		_phase = fmod(_phase + speed / stride * TAU * delta, TAU)
	elif pose == Pose.SWIM:
		_phase = fmod(_phase + (1.2 + speed) * delta * 2.5, TAU)
	var moving := smoothstep(0.15, 0.8, speed)

	var target_lean := Vector2(
			clampf(forward * 0.03 + run * 0.12, -0.15, 0.3) * moving,
			clampf(-turn_rate * speed * 0.03, -0.25, 0.25))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-8.0 * delta))

	var a := {}  # joint -> angle
	var hip_y := HIP_HEIGHT
	var s := sin(_phase)
	var c := cos(_phase)
	match pose:
		Pose.GROUND:
			var swing := lerpf(0.45, 0.85, run) * moving
			a["thigh_l"] = s * swing
			a["thigh_r"] = -s * swing
			# The knee folds most as the leg swings through, and when running.
			a["knee_l"] = -maxf(0.0, -c) * lerpf(0.7, 1.6, run) * moving - 0.05
			a["knee_r"] = -maxf(0.0, c) * lerpf(0.7, 1.6, run) * moving - 0.05
			a["foot_l"] = -a["thigh_l"] * 0.3
			a["foot_r"] = -a["thigh_r"] * 0.3
			a["arm_l"] = -s * lerpf(0.35, 0.8, run) * moving
			a["arm_r"] = s * lerpf(0.35, 0.8, run) * moving
			a["elbow_l"] = lerpf(0.15, 1.4, run) * maxf(moving, 0.2)
			a["elbow_r"] = a["elbow_l"]
			a["arm_out"] = 0.08
			# The body bobs twice per cycle, and dips after a landing.
			hip_y += -absf(s) * lerpf(0.03, 0.07, run) * moving + 0.015 * sin(_breath) * (1.0 - moving)
			if _land > 0.0:
				var k := _land
				a["thigh_l"] += 0.6 * k
				a["thigh_r"] += 0.6 * k
				a["knee_l"] -= 1.1 * k
				a["knee_r"] -= 1.1 * k
				hip_y -= 0.22 * k
		Pose.AIR:
			var up := clampf(vertical_speed / 5.0, -1.0, 1.0)
			a["thigh_l"] = 0.5 + 0.2 * up
			a["thigh_r"] = 0.1
			a["knee_l"] = -0.9
			a["knee_r"] = -0.5
			a["foot_l"] = 0.2
			a["foot_r"] = 0.2
			a["arm_l"] = 0.4
			a["arm_r"] = -0.2
			a["elbow_l"] = 0.6
			a["elbow_r"] = 0.6
			a["arm_out"] = 0.35 - 0.2 * up
		Pose.SWIM:
			# Treading water: slow scissor kicks and sculling arms.
			a["thigh_l"] = s * 0.35 + 0.2
			a["thigh_r"] = -s * 0.35 + 0.2
			a["knee_l"] = -0.5 - 0.3 * maxf(c, 0.0)
			a["knee_r"] = -0.5 - 0.3 * maxf(-c, 0.0)
			a["foot_l"] = 0.5
			a["foot_r"] = 0.5
			a["arm_l"] = 1.2 + 0.3 * c
			a["arm_r"] = 1.2 - 0.3 * c
			a["elbow_l"] = 0.4
			a["elbow_r"] = 0.4
			a["arm_out"] = 0.5 + 0.3 * s
			_lean.x = lerpf(_lean.x, 0.25 + moving * 0.6, 1.0 - exp(-4.0 * delta))
		Pose.SIT:
			a["thigh_l"] = 1.45
			a["thigh_r"] = 1.35
			a["knee_l"] = -1.4
			a["knee_r"] = -1.3
			a["foot_l"] = 0.0
			a["foot_r"] = 0.0
			a["arm_l"] = 0.9
			a["arm_r"] = 0.7
			a["elbow_l"] = 0.5
			a["elbow_r"] = 0.6
			a["arm_out"] = 0.15
			hip_y = 0.4
			_lean.x = lerpf(_lean.x, 0.05, 1.0 - exp(-6.0 * delta))

	# Smooth every joint so changes of pose blend rather than snap.
	var k_blend := 1.0 - exp(-14.0 * delta)
	for key in a:
		_blend[key] = lerpf(_blend.get(key, a[key]), a[key], k_blend)
	_blend["hip_y"] = lerpf(_blend.get("hip_y", hip_y), hip_y, 1.0 - exp(-20.0 * delta))

	_hips.position.y = _blend["hip_y"]
	_hips.rotation = Vector3(0, s * 0.08 * moving * (1.0 if pose == Pose.GROUND else 0.0), _lean.y)
	_spine.rotation = Vector3(-_lean.x, -_hips.rotation.y * 1.6, 0)
	_spine.scale = Vector3.ONE * (1.0 + 0.012 * sin(_breath))
	_neck.rotation.x = _lean.x * 0.7
	for i in 2:
		var side := "_l" if i == 0 else "_r"
		var sign_x := -1.0 if i == 0 else 1.0
		_legs[i]["thigh"].rotation = Vector3(_blend["thigh" + side], 0, 0)
		_legs[i]["knee"].rotation = Vector3(_blend["knee" + side], 0, 0)
		_legs[i]["foot"].rotation = Vector3(_blend["foot" + side], 0, 0)
		_arms[i]["shoulder"].rotation = Vector3(_blend["arm" + side], 0, sign_x * _blend["arm_out"])
		_arms[i]["elbow"].rotation = Vector3(_blend["elbow" + side], 0, 0)


## Start a landing crouch, scaled by how fast we hit the ground.
func land(impact_speed: float) -> void:
	_land = clampf(impact_speed / 9.0, 0.15, 1.0)


func _build() -> void:
	var skin := _mat(skin_color, 0.7)
	var shirt := _mat(shirt_color, 0.8)
	var trousers := _mat(trouser_color, 0.9)
	var boots := _mat(boot_color, 0.6)
	var hair := _mat(hair_color, 0.9)
	var dark := _mat(Color(0.08, 0.08, 0.1), 0.4)

	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position.y = HIP_HEIGHT
	add_child(_hips)
	_box(_hips, Vector3(0, 0.02, 0), Vector3(0.34, 0.16, 0.2), trousers)

	# Torso: a tapered jacket, with a collar and a belt.
	_spine = Node3D.new()
	_spine.name = "Spine"
	_spine.position.y = 0.08
	_hips.add_child(_spine)
	_capsule(_spine, Vector3(0, 0.22, 0), 0.17, 0.5, shirt, Vector3(1.05, 1, 0.68))
	_box(_spine, Vector3(0, 0.38, 0), Vector3(0.42, 0.12, 0.22), shirt)
	_box(_spine, Vector3(0, 0.0, 0), Vector3(0.35, 0.05, 0.21), boots)
	_box(_spine, Vector3(0, 0.2, -0.115), Vector3(0.03, 0.34, 0.01), dark)  # zip

	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position.y = SHOULDER_Y - 0.02
	_spine.add_child(_neck)
	_capsule(_neck, Vector3(0, 0.06, 0), 0.055, 0.14, skin)
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 0.2
	_neck.add_child(head)
	_head_mesh = head
	_sphere(head, Vector3.ZERO, 0.115, skin, Vector3(0.92, 1.08, 1.0))
	_sphere(head, Vector3(0, 0.045, 0.015), 0.12, hair, Vector3(0.96, 0.72, 1.0))  # hair
	_box(head, Vector3(0, -0.005, -0.112), Vector3(0.03, 0.05, 0.03), skin)  # nose
	for ex in [-0.042, 0.042]:
		_box(head, Vector3(ex, 0.02, -0.103), Vector3(0.025, 0.02, 0.01), dark)  # eyes
		_sphere(head, Vector3(ex * 2.6, 0.0, 0.0), 0.025, skin)  # ears

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Legs: pivot at the hip joint, then knee, then ankle.
		var thigh := Node3D.new()
		thigh.position = Vector3(side * 0.1, -0.02, 0)
		_hips.add_child(thigh)
		_capsule(thigh, Vector3(0, -THIGH * 0.5, 0), 0.075, THIGH + 0.1, trousers)
		var knee := Node3D.new()
		knee.position.y = -THIGH
		thigh.add_child(knee)
		_capsule(knee, Vector3(0, -SHIN * 0.5, 0), 0.06, SHIN + 0.06, trousers)
		var foot := Node3D.new()
		foot.position.y = -SHIN
		knee.add_child(foot)
		_box(foot, Vector3(0, -0.04, -0.05), Vector3(0.11, 0.1, 0.27), boots)
		_legs.append({"thigh": thigh, "knee": knee, "foot": foot})

		# Arms: pivot at the shoulder, then elbow, then hand.
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.22, SHOULDER_Y - 0.1, 0)
		_spine.add_child(shoulder)
		_capsule(shoulder, Vector3(0, -UPPER_ARM * 0.5, 0), 0.055, UPPER_ARM + 0.08, shirt)
		var elbow := Node3D.new()
		elbow.position.y = -UPPER_ARM
		shoulder.add_child(elbow)
		_capsule(elbow, Vector3(0, -FOREARM * 0.5, 0), 0.047, FOREARM + 0.04, shirt)
		_sphere(elbow, Vector3(0, -FOREARM - 0.04, 0), 0.05, skin, Vector3(0.8, 1.1, 0.6))
		_arms.append({"shoulder": shoulder, "elbow": elbow})
	animate(0.016, Pose.GROUND, Vector3.ZERO)


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _capsule(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0)
	cap.radial_segments = 12
	cap.rings = 4
	m.mesh = cap
	m.material_override = mat
	m.position = pos
	m.scale = scl
	parent.add_child(m)


func _sphere(parent: Node3D, pos: Vector3, radius: float, mat: Material, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 14
	sph.rings = 8
	m.mesh = sph
	m.material_override = mat
	m.position = pos
	m.scale = scl
	parent.add_child(m)


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
