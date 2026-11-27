extends Node3D
## The player's body: a jointed figure built from rounded shapes and animated
## in code. No imported model or animation files, so it is easy to restyle.
##
## Proportions are for a person about 1.8 m tall, in a high-vis sailing jacket,
## work trousers and boots. The figure faces -Z.
##
## Call `animate()` every frame with how the body is moving. Walking and
## running follow measured human gait curves (hip, knee and ankle angles over
## a stride), blended by speed, with the stride matched to the ground speed so
## the feet do not skate. The hips are lowered each frame until the lowest foot
## rests on the ground. Jumps have a push-off, a tuck and a reach for the
## ground; landings absorb the impact through the knees; standing still has
## breathing and a slow shift of weight.
##
## Joint rotations: a positive x rotation swings a limb forward (towards -Z),
## lifts the toes, and straightens a knee; knees bend with negative x.

enum Pose { GROUND, AIR, SWIM, SIT }

const ANKLE_HEIGHT := 0.085
const THIGH := 0.44
const SHIN := 0.43
const HIP_HEIGHT := ANKLE_HEIGHT + THIGH + SHIN  # 0.955 m, standing straight
const HIP_HALF_WIDTH := 0.095
const UPPER_ARM := 0.29
const FOREARM := 0.26
## Shoulder joints, in the chest's frame.
const SHOULDER := Vector3(0.185, 0.2, 0.01)
## The sole, in the foot's frame (origin at the ankle): heel and toe.
const HEEL := Vector2(0.06, -ANKLE_HEIGHT)   # (back, up)
const TOE := Vector2(-0.19, -ANKLE_HEIGHT)
## Metres covered in one full stride (two steps): lengthens with speed.
const WALK_CYCLE_BASE := 0.85
const WALK_CYCLE_PER_MS := 0.32
const RUN_CYCLE_BASE := 1.5
const RUN_CYCLE_PER_MS := 0.34

## Gait curves, ten samples over one stride of the left leg, starting as its
## heel strikes (degrees; hip + is forward, knee + is bent, ankle + is toes up).
## From averaged motion-capture data for walking and for running at about
## 5 m/s. The right leg is half a stride later.
const WALK_HIP := [24.0, 20.0, 11.0, 2.0, -7.0, -12.0, -6.0, 12.0, 24.0, 27.0]
const WALK_KNEE := [3.0, 16.0, 13.0, 5.0, 4.0, 16.0, 42.0, 60.0, 38.0, 8.0]
const WALK_ANKLE := [4.0, -6.0, 4.0, 8.0, 10.0, -4.0, -18.0, -4.0, 6.0, 6.0]
const RUN_HIP := [30.0, 16.0, 2.0, -14.0, -22.0, -12.0, 18.0, 46.0, 56.0, 42.0]
const RUN_KNEE := [22.0, 42.0, 30.0, 16.0, 26.0, 78.0, 112.0, 92.0, 52.0, 26.0]
const RUN_ANKLE := [4.0, 14.0, 8.0, -18.0, -26.0, -12.0, 4.0, 10.0, 10.0, 6.0]

var skin_color := Color(0.86, 0.66, 0.52)
var jacket_color := Color(0.95, 0.42, 0.08)  # high-vis orange
var jacket_trim := Color(0.16, 0.18, 0.22)
var reflective_color := Color(0.82, 0.84, 0.86)
var trouser_color := Color(0.2, 0.23, 0.29)
var boot_color := Color(0.25, 0.17, 0.11)
var sole_color := Color(0.09, 0.08, 0.08)
var hair_color := Color(0.22, 0.15, 0.09)

## World positions for the left and right hands to hold (a tiller, a wheel,
## a rod), or null to let that arm move with the pose.
var hand_targets: Array = [null, null]

var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _legs: Array[Dictionary] = []  # {thigh, knee, foot}
var _arms: Array[Dictionary] = []  # {shoulder, elbow, wrist}

var _phase := 0.0       # 0..1 through a stride
var _swim_phase := 0.0
var _time := 0.0
var _land := 0.0        # 0..1, how hard we just landed
var _land_v := 0.0      # landing crouch springs back with a little overshoot
var _air_t := 0.0       # seconds since leaving the ground
var _last_pose := Pose.GROUND
var _lean := Vector2.ZERO  # forward and sideways lean of the upper body
var _prev_speed := 0.0
var _accel := 0.0       # smoothed forward acceleration, for leaning into it
var _blend := {}        # smoothed joint angles
var _hip_y := HIP_HEIGHT
var _swim_stroke := 0.0  # 0 treading water, 1 swimming along
var _swim_pitch := 0.0   # how far the whole body tips forward to swim


func _ready() -> void:
	_build()


## Show or hide the head (hidden in first person so it does not block the view).
func set_head_visible(on: bool) -> void:
	_head.visible = on


## Where the middle of a hand is now (0 left, 1 right), in world space.
func hand_position(i: int) -> Vector3:
	return (_arms[i]["elbow"] as Node3D).global_transform * Vector3(0, -(FOREARM + 0.07), 0)


## Start a landing crouch, scaled by how fast we hit the ground.
func land(impact_speed: float) -> void:
	_land = clampf(impact_speed / 8.0, 0.2, 1.0)
	_land_v = 0.0


## Drive the animation.
## `local_vel`: velocity in the body's own frame (x right, z back).
## `turn_rate`: radians per second around the vertical.
## `vertical_speed`: for jumping, falling and landing.
func animate(delta: float, pose: Pose, local_vel: Vector3, turn_rate := 0.0, vertical_speed := 0.0) -> void:
	delta = maxf(delta, 0.0001)
	_time += delta
	var flat := Vector2(local_vel.x, local_vel.z)
	var speed := flat.length()
	var forward := -local_vel.z

	# Leaning into speeding up and back when pulling up.
	var acc := clampf((speed - _prev_speed) / delta, -12.0, 12.0)
	_prev_speed = speed
	_accel = lerpf(_accel, acc, 1.0 - exp(-6.0 * delta))

	# The landing crouch is a damped spring back to standing.
	_land_v += (-_land * 60.0 - _land_v * 11.0) * delta
	_land = maxf(_land + _land_v * delta, -0.08)

	if pose == Pose.AIR:
		_air_t = 0.0 if _last_pose != Pose.AIR else _air_t + delta
	_last_pose = pose

	var run := smoothstep(2.9, 4.6, speed)
	var moving := smoothstep(0.1, 0.7, speed)
	var a := {}
	match pose:
		Pose.GROUND:
			_ground_pose(a, delta, speed, run, moving)
		Pose.AIR:
			_air_pose(a, vertical_speed, speed)
		Pose.SWIM:
			_swim_pose(a, delta, speed)
		Pose.SIT:
			_sit_pose(a)

	# Body lean: forward with speed and acceleration, into turns when running.
	var target_lean := Vector2.ZERO
	if pose == Pose.GROUND or pose == Pose.AIR:
		target_lean.x = (0.05 * moving + 0.13 * run) * signf(forward + 0.001) + clampf(_accel * 0.018, -0.12, 0.16)
		target_lean.y = clampf(-turn_rate * speed * 0.035, -0.3, 0.3)
	elif pose == Pose.SWIM:
		target_lean.x = 0.12
	elif pose == Pose.SIT:
		# Leaning in to hold a tiller or wheel, upright otherwise.
		target_lean.x = 0.3 if hand_targets.any(func(h): return h is Vector3) else 0.06
	if pose == Pose.GROUND:
		target_lean.x += 0.35 * maxf(_land, 0.0)
	_lean = _lean.lerp(target_lean, 1.0 - exp(-7.0 * delta))

	# Smooth every joint so changes of pose blend rather than snap. Gait moves
	# fast, so the smoothing is quick; it mostly hides pose changes.
	var k := 1.0 - exp(-(22.0 if pose == Pose.GROUND else 12.0) * delta)
	for key in a:
		_blend[key] = lerpf(_blend.get(key, a[key]), a[key], k)

	_apply(pose, delta)


func _ground_pose(a: Dictionary, delta: float, speed: float, run: float, moving: float) -> void:
	var cycle := lerpf(WALK_CYCLE_BASE + WALK_CYCLE_PER_MS * speed, RUN_CYCLE_BASE + RUN_CYCLE_PER_MS * speed, run)
	_phase = fposmod(_phase + speed / cycle * delta, 1.0)
	# Short shuffles use small steps: scale the swing down at low speed.
	var amp := moving * lerpf(0.75, 1.0, smoothstep(0.7, 2.0, speed))
	for i in 2:
		var side := "_l" if i == 0 else "_r"
		var p := fposmod(_phase + 0.5 * i, 1.0)
		var hip := lerpf(_curve(WALK_HIP, p), _curve(RUN_HIP, p), run)
		var knee := lerpf(_curve(WALK_KNEE, p), _curve(RUN_KNEE, p), run)
		var ankle := lerpf(_curve(WALK_ANKLE, p), _curve(RUN_ANKLE, p), run)
		a["thigh" + side] = deg_to_rad(hip) * amp
		a["knee" + side] = -deg_to_rad(knee) * amp - 0.04
		a["foot" + side] = deg_to_rad(ankle) * amp
		# Arms swing against the legs: forward as the other leg comes through.
		var arm_swing := -deg_to_rad(hip) * lerpf(0.55, 1.0, run) * amp
		a["arm" + side] = arm_swing * lerpf(1.0, 0.85, run) - 0.02 + 0.12 * run
		a["elbow" + side] = lerpf(0.22, 1.5, run) + maxf(arm_swing, 0.0) * 0.5 + 0.12 * (1.0 - moving)
	a["arm_out"] = 0.07 + 0.05 * run
	# Standing: weight on one leg then the other, every few seconds.
	var idle := 1.0 - moving
	if idle > 0.0:
		var shift := sin(_time * 0.45) * idle
		a["thigh_l"] += 0.03 * shift
		a["thigh_r"] -= 0.03 * shift
		a["knee_l"] -= 0.06 * maxf(-shift, 0.0)
		a["knee_r"] -= 0.06 * maxf(shift, 0.0)
		a["hip_roll"] = 0.04 * shift
		a["head_turn"] = 0.25 * sin(_time * 0.21) * sin(_time * 0.07) * idle
	else:
		a["hip_roll"] = 0.0
		a["head_turn"] = 0.0
	# Hips turn with the leading leg; the chest counter-rotates.
	a["hip_yaw"] = -sin(_phase * TAU) * lerpf(0.09, 0.14, run) * moving
	a["hip_drop"] = sin(_phase * TAU * 2.0) * 0.035 * moving
	# A landing folds the legs and pushes the arms forward for balance.
	if _land > 0.0:
		var l := _land
		for side in ["_l", "_r"]:
			a["thigh" + side] += 0.75 * l
			a["knee" + side] -= 1.4 * l
			a["foot" + side] += 0.55 * l
			a["arm" + side] += 0.5 * l
			a["elbow" + side] += 0.4 * l
		a["arm_out"] += 0.25 * l
	# Running bounces through a short flight between steps.
	a["bounce"] = run * 0.045 * maxf(sin(_phase * TAU * 2.0 - 0.9), 0.0)


func _air_pose(a: Dictionary, vertical_speed: float, speed: float) -> void:
	var up := clampf(vertical_speed / 4.0, -1.0, 1.0)
	var push := 1.0 - smoothstep(0.0, 0.18, _air_t)  # straight legs as we leave the ground
	var reach := smoothstep(0.0, -0.8, up)  # legs come down to meet the ground
	var run := smoothstep(2.5, 5.0, speed)
	# Leading leg tucked up, trailing leg behind; both straighten to land.
	var lead_hip := lerpf(lerpf(0.9, 0.5, reach), 0.1, push) + 0.2 * run
	var trail_hip := lerpf(lerpf(-0.15, 0.2, reach), -0.25, push)
	a["thigh_l"] = lead_hip
	a["knee_l"] = lerpf(lerpf(-1.35, -0.35, reach), -0.15, push)
	a["foot_l"] = lerpf(0.1, -0.5, push)
	a["thigh_r"] = trail_hip
	a["knee_r"] = lerpf(lerpf(-1.0, -0.3, reach), -0.1, push)
	a["foot_r"] = lerpf(-0.1, -0.6, push)
	# Arms drive up on take-off, then spread for balance.
	a["arm_l"] = lerpf(lerpf(-0.3, 0.3, reach), 1.1, push)
	a["arm_r"] = lerpf(lerpf(0.7, 0.4, reach), 1.1, push)
	a["elbow_l"] = 0.6
	a["elbow_r"] = 0.6
	a["arm_out"] = lerpf(0.4 + 0.25 * reach, 0.15, push)
	a["hip_yaw"] = 0.0
	a["hip_drop"] = 0.0
	a["hip_roll"] = 0.0
	a["head_turn"] = 0.0
	a["bounce"] = 0.0


func _swim_pose(a: Dictionary, delta: float, speed: float) -> void:
	var stroke := smoothstep(0.25, 0.9, speed)
	_swim_stroke = stroke
	_swim_phase = fposmod(_swim_phase + delta * lerpf(0.55, 0.75, stroke), 1.0)
	var s := sin(_swim_phase * TAU)
	var c := cos(_swim_phase * TAU)
	# Treading water: scissor kicks and sculling hands. Moving: breaststroke,
	# arms sweeping out and round as the legs frog-kick.
	var tread := {
		"thigh_l": 0.25 + s * 0.3, "thigh_r": 0.25 - s * 0.3,
		"knee_l": -0.6 - 0.3 * maxf(c, 0.0), "knee_r": -0.6 - 0.3 * maxf(-c, 0.0),
		"foot_l": -0.4, "foot_r": -0.4,
		"arm_l": 1.1 + 0.25 * c, "arm_r": 1.1 + 0.25 * c,
		"elbow_l": 0.5, "elbow_r": 0.5, "arm_out": 0.55 + 0.35 * s,
	}
	var kick := maxf(s, 0.0)
	var reach := 0.5 + 0.5 * c
	var breast := {
		"thigh_l": 0.15 + 0.85 * kick, "thigh_r": 0.15 + 0.85 * kick,
		"knee_l": -0.2 - 1.6 * kick, "knee_r": -0.2 - 1.6 * kick,
		"foot_l": -0.7 + 0.8 * kick, "foot_r": -0.7 + 0.8 * kick,
		"arm_l": lerpf(1.2, 2.6, reach), "arm_r": lerpf(1.2, 2.6, reach),
		"elbow_l": lerpf(1.3, 0.15, reach), "elbow_r": lerpf(1.3, 0.15, reach),
		"arm_out": lerpf(0.9, 0.15, reach),
	}
	for key in tread:
		a[key] = lerpf(tread[key], breast[key], stroke)
	a["hip_yaw"] = 0.0
	a["hip_drop"] = 0.0
	a["hip_roll"] = 0.0
	a["head_turn"] = 0.0
	a["bounce"] = 0.0


func _sit_pose(a: Dictionary) -> void:
	# Seated low, as in a small boat: knees a little above the hips and feet
	# flat on the floor in front.
	a["thigh_l"] = 1.62
	a["thigh_r"] = 1.55
	a["knee_l"] = -1.62
	a["knee_r"] = -1.52
	a["foot_l"] = 0.02
	a["foot_r"] = 0.0
	# A free hand rests on the thigh.
	a["arm_l"] = 0.5
	a["arm_r"] = 0.45
	a["elbow_l"] = 0.85
	a["elbow_r"] = 0.9
	a["arm_out"] = 0.16
	a["hip_yaw"] = 0.0
	a["hip_drop"] = 0.0
	a["hip_roll"] = 0.0
	a["head_turn"] = 0.0
	a["bounce"] = 0.0


func _apply(pose: Pose, delta: float) -> void:
	var b := _blend
	for i in 2:
		var side := "_l" if i == 0 else "_r"
		var sign_x := -1.0 if i == 0 else 1.0
		_legs[i]["thigh"].rotation = Vector3(b["thigh" + side], 0, 0)
		_legs[i]["knee"].rotation = Vector3(minf(b["knee" + side], 0.0), 0, 0)
		_legs[i]["foot"].rotation = Vector3(b["foot" + side], 0, 0)
		var shoulder: Node3D = _arms[i]["shoulder"]
		shoulder.rotation = Vector3(b["arm" + side], 0, sign_x * b["arm_out"])
		_arms[i]["elbow"].rotation = Vector3(maxf(b["elbow" + side], 0.0), 0, 0)
		_arms[i]["wrist"].rotation = Vector3(0.1 + 0.15 * b["elbow" + side], 0, 0)

	# Hips: low enough that the lowest point of either sole touches the
	# ground, so feet plant instead of floating or sinking.
	var target_y := HIP_HEIGHT
	if pose == Pose.GROUND:
		var lowest := INF
		for side in ["_l", "_r"]:
			lowest = minf(lowest, _sole_low(b["thigh" + side], minf(b["knee" + side], 0.0), b["foot" + side]))
		target_y = -lowest + b["bounce"] + 0.006 * sin(_time * 1.7) * (1.0 - smoothstep(0.1, 0.7, _prev_speed))
		target_y -= absf(b["hip_drop"]) * 0.3
	elif pose == Pose.SIT:
		target_y = 0.31
	elif pose == Pose.SWIM:
		# Swimming along, the body floats up and tips forward, legs trailing.
		target_y = lerpf(HIP_HEIGHT, HIP_HEIGHT + 0.3, _swim_stroke)
	_swim_pitch = lerpf(_swim_pitch, 0.95 * _swim_stroke if pose == Pose.SWIM else 0.0, 1.0 - exp(-5.0 * delta))
	_hip_y = lerpf(_hip_y, target_y, 1.0 - exp(-(40.0 if pose == Pose.GROUND else 20.0) * delta))
	_hips.position.y = _hip_y
	_hips.rotation = Vector3(-_swim_pitch, b["hip_yaw"], _lean.y * 0.5 + b["hip_drop"] + b["hip_roll"])

	# Spine and chest share the lean; the chest turns against the hips.
	_spine.rotation = Vector3(-_lean.x * 0.45, -b["hip_yaw"] * 0.6, -b["hip_drop"] * 0.6 - b["hip_roll"] * 0.8)
	_chest.rotation = Vector3(-_lean.x * 0.45, -b["hip_yaw"] * 0.9, _lean.y * 0.3)
	# Breathing: the chest rises and widens a little.
	var breath := sin(_time * TAU * 0.25)
	_chest.scale = Vector3(1.0 + 0.012 * breath, 1.0 + 0.006 * breath, 1.0 + 0.018 * breath)
	# The head keeps the eyes level and looks where we are going.
	_neck.rotation = Vector3(_lean.x * 0.75, b["hip_yaw"] * 0.5 + b["head_turn"], -_lean.y * 0.5)
	if pose == Pose.SWIM:
		_neck.rotation.x = (_lean.x + _swim_pitch) * 0.95
	for i in 2:
		if i < hand_targets.size() and hand_targets[i] is Vector3:
			_reach(i, hand_targets[i])


## How far below the hip joint the lower of heel and toe sits, for a leg at
## these joint angles (negative: below).
func _sole_low(hip: float, knee: float, ankle: float) -> float:
	var shin := hip + knee
	var foot := shin + ankle
	var ankle_y := -cos(hip) * THIGH - cos(shin) * SHIN
	var low := INF
	for pt: Vector2 in [HEEL, TOE]:
		# Rotate the sole point (y up, z back) by the foot's angle about x.
		low = minf(low, ankle_y + pt.y * cos(foot) - pt.x * sin(foot))
	return low


## A gait curve sampled at `p` (0..1), smoothly through its ten points.
static func _curve(samples: Array, p: float) -> float:
	var n := samples.size()
	var f := p * n
	var i := int(f) % n
	var t := f - floorf(f)
	var p0: float = samples[(i - 1 + n) % n]
	var p1: float = samples[i]
	var p2: float = samples[(i + 1) % n]
	var p3: float = samples[(i + 2) % n]
	# Catmull-Rom.
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


## Bend an arm so its hand ends at `target` (world space): a two-bone reach
## with the elbow pointing out and back, as when holding a handle.
func _reach(i: int, target: Vector3) -> void:
	var shoulder: Node3D = _arms[i]["shoulder"]
	var parent := shoulder.get_parent() as Node3D
	var d: Vector3 = parent.global_transform.affine_inverse() * target - shoulder.position
	var upper_len := UPPER_ARM
	var fore_len := FOREARM + 0.07  # to the middle of the hand
	var l := clampf(d.length(), absf(upper_len - fore_len) + 0.01, upper_len + fore_len - 0.001)
	var n := d.normalized()
	var bend := PI - acos(clampf((upper_len * upper_len + fore_len * fore_len - l * l) / (2.0 * upper_len * fore_len), -1.0, 1.0))
	var alpha := acos(clampf((upper_len * upper_len + l * l - fore_len * fore_len) / (2.0 * upper_len * l), -1.0, 1.0))
	var hinge := Vector3.RIGHT - n * n.dot(Vector3.RIGHT)
	if hinge.length() < 0.01:
		hinge = Vector3.FORWARD.cross(n)
	hinge = hinge.normalized()
	var best := shoulder.basis
	var best_err := INF
	for sgn in [1.0, -1.0]:
		var upper := n.rotated(hinge, sgn * alpha)
		var y := -upper
		var bb := Basis(hinge, y, hinge.cross(y))
		var hand := upper * upper_len + bb * Vector3(0, -cos(bend), -sin(bend)) * fore_len
		var err := hand.distance_to(n * l)
		if err < best_err:
			best_err = err
			best = bb
	shoulder.basis = best
	_arms[i]["elbow"].rotation = Vector3(bend, 0, 0)
	_arms[i]["wrist"].rotation = Vector3(-0.2, 0, 0)


# --- The model --------------------------------------------------------------

func _build() -> void:
	var skin := _mat(skin_color, 0.62)
	var jacket := _mat(jacket_color, 0.75)
	var trim := _mat(jacket_trim, 0.7)
	var tape := _mat(reflective_color, 0.25, 0.4)
	var trousers := _mat(trouser_color, 0.92)
	var boots := _mat(boot_color, 0.55)
	var soles := _mat(sole_color, 0.9)
	var hair := _mat(hair_color, 0.95)
	var eye_white := _mat(Color(0.93, 0.92, 0.9), 0.3)
	var iris := _mat(Color(0.18, 0.28, 0.33), 0.2)
	var lips := _mat(skin_color.darkened(0.25).lerp(Color(0.6, 0.3, 0.3), 0.3), 0.5)
	var metal := _mat(Color(0.75, 0.75, 0.72), 0.3, 0.8)

	_hips = _node(self, "Hips", Vector3(0, HIP_HEIGHT, 0))
	# Pelvis and seat.
	_ellipsoid(_hips, Vector3(0, 0.03, 0.005), Vector3(0.165, 0.11, 0.115), trousers)
	_ellipsoid(_hips, Vector3(0, -0.01, 0.045), Vector3(0.15, 0.1, 0.09), trousers)  # seat

	# Torso: an abdomen and a ribcage, both under the jacket, which hangs a
	# little below the waist. Reflective tape rings the chest and waist.
	_spine = _node(_hips, "Spine", Vector3(0, 0.08, 0))
	_ellipsoid(_spine, Vector3(0, 0.08, 0.0), Vector3(0.166, 0.17, 0.113), jacket)  # waist
	_tube(_spine, Vector3(0, -0.02, 0.0), 0.168, 0.162, 0.06, jacket, Vector3(1.0, 1.0, 0.68))  # hem
	_ring(_spine, Vector3(0, 0.03, 0), 0.164, 0.111, 0.035, tape)
	_ring(_spine, Vector3(0, -0.045, 0), 0.168, 0.114, 0.016, trim)  # hem band
	_chest = _node(_spine, "Chest", Vector3(0, 0.18, 0))
	_ellipsoid(_chest, Vector3(0, 0.08, 0.0), Vector3(0.178, 0.2, 0.118), jacket)  # ribcage
	_ellipsoid(_chest, Vector3(0, 0.2, 0.015), Vector3(0.16, 0.06, 0.085), jacket)  # trapezius
	_ring(_chest, Vector3(0, 0.03, 0), 0.172, 0.114, 0.035, tape)
	# Collar: a stand-up neck of the jacket.
	_tube(_chest, Vector3(0, 0.245, 0.005), 0.075, 0.085, 0.07, jacket)
	_tube(_chest, Vector3(0, 0.282, 0.005), 0.077, 0.077, 0.008, trim)
	# Zip and pull, and a chest pocket.
	_box(_chest, Vector3(0, 0.1, -0.118), Vector3(0.014, 0.26, 0.006), trim, Vector3(0.18, 0, 0))
	_box(_chest, Vector3(0.012, 0.2, -0.112), Vector3(0.012, 0.03, 0.006), metal)
	_box(_chest, Vector3(-0.075, 0.12, -0.108), Vector3(0.06, 0.012, 0.012), trim, Vector3(0, 0.35, 0))  # pocket flap

	# Neck and head.
	_neck = _node(_chest, "Neck", Vector3(0, 0.25, 0.01))
	_tube(_neck, Vector3(0, 0.03, 0), 0.057, 0.055, 0.11, skin)
	_head = _node(_neck, "Head", Vector3(0, 0.07, 0))
	_ellipsoid(_head, Vector3(0, 0.11, 0.005), Vector3(0.088, 0.112, 0.102), skin)  # skull
	_ellipsoid(_head, Vector3(0, 0.055, -0.025), Vector3(0.068, 0.062, 0.068), skin)  # jaw
	_ellipsoid(_head, Vector3(0, 0.015, -0.062), Vector3(0.032, 0.022, 0.03), skin)  # chin
	for sx in [-1.0, 1.0]:
		_ellipsoid(_head, Vector3(sx * 0.037, 0.118, -0.082), Vector3(0.017, 0.012, 0.01), eye_white)
		_ellipsoid(_head, Vector3(sx * 0.037, 0.118, -0.0905), Vector3(0.0075, 0.0075, 0.004), iris)
		_box(_head, Vector3(sx * 0.038, 0.142, -0.092), Vector3(0.036, 0.008, 0.012), hair, Vector3(0, 0, sx * 0.08))  # brow
		_ellipsoid(_head, Vector3(sx * 0.09, 0.105, 0.005), Vector3(0.012, 0.028, 0.02), skin)  # ear
	_ellipsoid(_head, Vector3(0, 0.1, -0.097), Vector3(0.014, 0.03, 0.016), skin, Vector3(0.3, 0, 0))  # nose bridge
	_ellipsoid(_head, Vector3(0, 0.083, -0.104), Vector3(0.017, 0.013, 0.014), skin)  # nose tip
	_ellipsoid(_head, Vector3(0, 0.05, -0.088), Vector3(0.022, 0.006, 0.006), lips)  # mouth
	# Short hair: a cap over the top and back, a fringe, and sideburns.
	_ellipsoid(_head, Vector3(0, 0.138, 0.018), Vector3(0.093, 0.1, 0.1), hair)
	_ellipsoid(_head, Vector3(0, 0.188, -0.045), Vector3(0.078, 0.04, 0.06), hair, Vector3(0.3, 0, 0))
	for sx in [-1.0, 1.0]:
		_box(_head, Vector3(sx * 0.083, 0.095, -0.018), Vector3(0.008, 0.04, 0.022), hair)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Legs: pivot at the hip joint, then knee, then ankle.
		var thigh := _node(_hips, "Thigh", Vector3(side * HIP_HALF_WIDTH, 0, 0))
		_limb(thigh, 0.0, -THIGH, 0.088, 0.062, trousers, Vector3(1.0, 1.0, 1.08))
		_ellipsoid(thigh, Vector3(0, -0.15, -0.008), Vector3(0.074, 0.14, 0.076), trousers)  # quad
		var knee := _node(thigh, "Knee", Vector3(0, -THIGH, 0))
		_limb(knee, 0.0, -SHIN, 0.058, 0.046, trousers)
		_ellipsoid(knee, Vector3(0, -0.12, 0.022), Vector3(0.052, 0.1, 0.055), trousers)  # calf
		_ellipsoid(knee, Vector3(0, 0.0, -0.01), Vector3(0.057, 0.055, 0.05), trousers)  # kneecap
		var foot := _node(knee, "Foot", Vector3(0, -SHIN, 0))
		# A work boot: ankle collar, upper, toe cap and a thick sole.
		_tube(foot, Vector3(0, 0.03, 0.005), 0.058, 0.06, 0.1, boots)
		_ellipsoid(foot, Vector3(0, -0.035, -0.045), Vector3(0.058, 0.055, 0.135), boots)
		_ellipsoid(foot, Vector3(0, -0.045, -0.15), Vector3(0.05, 0.04, 0.05), boots)
		_box(foot, Vector3(0, -ANKLE_HEIGHT + 0.012, -0.065), Vector3(0.11, 0.024, 0.27), soles)
		_box(foot, Vector3(0, 0.035, -0.05), Vector3(0.05, 0.01, 0.07), trim, Vector3(-0.6, 0, 0))  # laces
		_legs.append({"thigh": thigh, "knee": knee, "foot": foot})

		# Arms: pivot at the shoulder, then elbow, then wrist.
		var shoulder := _node(_chest, "Shoulder", Vector3(side * SHOULDER.x, SHOULDER.y, SHOULDER.z))
		_ellipsoid(shoulder, Vector3(0, -0.035, 0), Vector3(0.057, 0.072, 0.06), jacket)  # deltoid
		_limb(shoulder, 0.0, -UPPER_ARM, 0.058, 0.047, jacket)
		_ring(shoulder, Vector3(0, -0.17, 0), 0.0545, 0.0545, 0.03, tape)
		var elbow := _node(shoulder, "Elbow", Vector3(0, -UPPER_ARM, 0))
		_limb(elbow, 0.0, -FOREARM + 0.02, 0.05, 0.043, jacket)
		_tube(elbow, Vector3(0, -FOREARM + 0.025, 0), 0.046, 0.046, 0.035, trim)  # cuff
		var wrist := _node(elbow, "Wrist", Vector3(0, -FOREARM, 0))
		_tube(wrist, Vector3(0, 0.02, 0), 0.03, 0.032, 0.04, skin)
		# Hand, relaxed: palm, curled fingers and a thumb.
		_ellipsoid(wrist, Vector3(0, -0.045, -0.002), Vector3(0.022, 0.047, 0.042), skin)
		_ellipsoid(wrist, Vector3(0, -0.1, -0.012), Vector3(0.02, 0.035, 0.038), skin, Vector3(0.35, 0, 0))
		_ellipsoid(wrist, Vector3(-side * 0.0, -0.035, -0.04), Vector3(0.014, 0.034, 0.014), skin, Vector3(0.5, 0, 0))
		_arms.append({"shoulder": shoulder, "elbow": elbow, "wrist": wrist})
	animate(0.016, Pose.GROUND, Vector3.ZERO)


func _node(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## A sphere stretched to the given radii.
func _ellipsoid(parent: Node3D, pos: Vector3, radii: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 20
	sph.rings = 12
	m.mesh = sph
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = radii
	parent.add_child(m)


## A tapered limb from y0 down to y1 along the node's -Y, rounded at both ends.
func _limb(parent: Node3D, y0: float, y1: float, r0: float, r1: float, mat: Material, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r0
	cyl.bottom_radius = r1
	cyl.height = absf(y0 - y1)
	cyl.radial_segments = 18
	cyl.rings = 2
	cyl.cap_top = false
	cyl.cap_bottom = false
	m.mesh = cyl
	m.material_override = mat
	m.position = Vector3(0, (y0 + y1) * 0.5, 0)
	m.scale = scl
	parent.add_child(m)
	_ellipsoid(parent, Vector3(0, y0, 0), Vector3(r0, r0, r0) * scl, mat)
	_ellipsoid(parent, Vector3(0, y1, 0), Vector3(r1, r1, r1) * scl, mat)


## A short open-ended tube (collar, cuff).
func _tube(parent: Node3D, pos: Vector3, r_bottom: float, r_top: float, height: float, mat: Material,
		scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bottom
	cyl.height = height
	cyl.radial_segments = 18
	cyl.rings = 1
	m.mesh = cyl
	m.material_override = mat
	m.position = pos
	m.scale = scl
	parent.add_child(m)


## A band wrapped round an oval body section (reflective tape, a hem).
func _ring(parent: Node3D, pos: Vector3, rx: float, rz: float, height: float, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = height
	cyl.radial_segments = 24
	cyl.rings = 1
	m.mesh = cyl
	m.material_override = mat
	m.position = pos
	m.scale = Vector3(rx + 0.003, 1.0, rz + 0.003)
	parent.add_child(m)


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
