extends Node3D
## Spray, wake and engine noise for a vessel. Pure presentation: reads the
## vessel's telemetry and never changes its physics.

const MIX_RATE := 22050.0

var _boat: RigidBody3D
var _spray: CPUParticles3D
var _wake: CPUParticles3D
var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _noise := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_boat = get_parent()
	var stats: Dictionary = _boat.get(&"stats")
	var half_len: float = stats["length"] * 0.5
	var mid: Vector3 = stats["center_of_mass"]
	_spray = _particles(Vector3(mid.x, 0.2, mid.z - half_len - 0.1), 0.22, 0.9, Color(1, 1, 1, 0.85))
	# Spray is thrown out from the bow and travels with the boat for its short
	# life; the wake stays behind in the water.
	_spray.local_coords = true
	_spray.direction = Vector3(0, 1, -0.2)
	_spray.spread = 80.0
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_spray.emission_box_extents = Vector3(stats["beam"] * 0.5, 0.05, 0.1)
	_spray.lifetime = 0.6
	_spray.gravity = Vector3(0, -9.8, 0)
	_spray.amount = 140
	_spray.scale_amount_min = 0.4
	_spray.scale_amount_max = 1.0
	_wake = _particles(Vector3(mid.x, 0.3, mid.z + half_len + 0.3), 0.8, 4.0, Color(0.93, 0.97, 1, 0.75))
	_wake.direction = Vector3(0, 0.2, 1)
	_wake.spread = 25.0
	_wake.gravity = Vector3.ZERO
	_wake.damping_min = 1.0
	_wake.damping_max = 2.0
	_wake.amount = 220
	_wake.scale_amount_min = 0.6
	_wake.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	_wake.scale_amount_curve = curve

	if not (stats["engines"] as Array).is_empty() and AudioServer.get_driver_name() != "Dummy":
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = MIX_RATE
		gen.buffer_length = 0.15
		_audio = AudioStreamPlayer3D.new()
		_audio.stream = gen
		_audio.unit_size = 6.0
		_audio.max_distance = 260.0
		_audio.volume_db = -6.0
		_audio.position = stats["engines"][0]["head"]
		add_child(_audio)
		_audio.play()
		_playback = _audio.get_stream_playback()


func _process(_delta: float) -> void:
	var speed: float = absf(_boat.get(&"speed_ms"))
	var wet: float = clampf(_boat.get(&"submerged_ratio"), 0.0, 1.0)
	_spray.emitting = speed > 2.0 and wet > 0.3
	_spray.initial_velocity_min = speed * 0.25
	_spray.initial_velocity_max = speed * 0.5
	_wake.emitting = speed > 0.8 and wet > 0.3
	_wake.initial_velocity_min = 0.3
	_wake.initial_velocity_max = 0.6 + speed * 0.1
	_fill_audio()


## A two-stroke outboard, made from two detuned pulse waves at the firing
## frequency plus some noise, louder and brighter with throttle.
func _fill_audio() -> void:
	if _playback == null:
		return
	var rpm: float = _boat.get(&"rpm")
	var running: bool = _boat.get(&"engine_running")
	var throttle: float = absf(_boat.get(&"throttle"))
	var f := rpm / 60.0  # one firing per revolution
	var vol := 0.0 if not running else 0.22 + throttle * 0.3
	var frames := _playback.get_frames_available()
	for i in frames:
		_phase = fmod(_phase + f / MIX_RATE, 1.0)
		_phase2 = fmod(_phase2 + f * 1.007 / MIX_RATE, 1.0)
		_noise = lerpf(_noise, _rng.randf_range(-1.0, 1.0), 0.3)
		var pulse := (1.0 if _phase < 0.18 else -0.2) + (0.7 if _phase2 < 0.25 else -0.15)
		var s := (pulse * 0.5 + _noise * (0.25 + throttle * 0.35)) * vol
		_playback.push_frame(Vector2(s, s))


func _particles(pos: Vector3, size: float, lifetime: float, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 90
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	# A soft round blob rather than a square.
	var blob := GradientTexture2D.new()
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	blob.gradient = g
	blob.width = 32
	blob.height = 32
	mat.albedo_texture = blob
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	# Draw after the (transparent) ocean so the sea does not paint over it.
	mat.render_priority = 10
	mat.albedo_color = color
	quad.material = mat
	p.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p
