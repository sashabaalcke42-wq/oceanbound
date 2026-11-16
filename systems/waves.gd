extends Node
## The single source of truth for the ocean surface.
##
## Waves are a sum of Gerstner waves. The ocean shader receives exactly these
## parameters and this `time` every frame (see world/ocean/ocean.gd), so
## `height_at()` matches the surface the player sees and boats sit on the
## visible waves.

const GRAVITY := 9.81
## Waves fade to flat between these distances from the camera. The shader does
## the same, so heights stay in agreement and distant water does not alias.
const FADE_START := 260.0
const FADE_END := 420.0

## Each wave: direction in degrees (0 = towards +X), wavelength in metres,
## steepness 0..1 (how sharp the crests are; the sum should stay below 1).
@export var waves: Array[Dictionary] = [
	{"dir": 20.0, "length": 31.0, "steepness": 0.075},
	{"dir": -30.0, "length": 17.0, "steepness": 0.065},
	{"dir": 70.0, "length": 9.5, "steepness": 0.05},
	{"dir": 145.0, "length": 6.0, "steepness": 0.04},
]
## Weather multiplier on wave amplitude. 0 is a flat calm, 1 a normal day
## (swell up to about 0.6 m), 2 to 3 is rough.
var amplitude_scale := 1.0
## Ocean time in seconds. Advanced on physics ticks so it is deterministic.
var time := 0.0
## Where waves are measured from for the distance fade (the active camera).
var fade_origin := Vector3.ZERO

# Cached per-wave constants: [dir_x, dir_z, k, speed, steepness].
var _cache: Array[PackedFloat32Array] = []


func _ready() -> void:
	process_priority = -100
	_rebuild_cache()


func _physics_process(delta: float) -> void:
	time += delta
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		fade_origin = cam.global_position


func set_waves(new_waves: Array[Dictionary]) -> void:
	waves = new_waves
	_rebuild_cache()


## Height of the water surface at world position (x, z).
func height_at(x: float, z: float) -> float:
	var fade := _fade(x, z)
	if fade <= 0.0 or amplitude_scale <= 0.0:
		return 0.0
	# Gerstner waves also move water sideways, so the point that ends up above
	# (x, z) started somewhere else. Two fixed-point steps find it closely.
	var px := x
	var pz := z
	for i in 2:
		var d := _displacement(px, pz, fade)
		px = x - d.x
		pz = z - d.z
	return _displacement(px, pz, fade).y


## Parameters in the layout the ocean shader expects: one vec4 per wave
## (dir_x, dir_z, steepness, wavelength).
func shader_wave_params() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for w in waves:
		var a := deg_to_rad(float(w["dir"]))
		out.append(Vector4(cos(a), sin(a), float(w["steepness"]), float(w["length"])))
	while out.size() < 4:
		out.append(Vector4(1, 0, 0, 1))
	return out


func _fade(x: float, z: float) -> float:
	var dist := Vector2(x - fade_origin.x, z - fade_origin.z).length()
	return 1.0 - smoothstep(FADE_START, FADE_END, dist)


func _displacement(x: float, z: float, fade: float) -> Vector3:
	var out := Vector3.ZERO
	for c in _cache:
		var f := c[2] * (c[0] * x + c[1] * z - c[3] * time)
		var a := c[4] / c[2] * amplitude_scale * fade
		var cf := cos(f)
		out.x += c[0] * a * cf
		out.z += c[1] * a * cf
		out.y += a * sin(f)
	return out


func _rebuild_cache() -> void:
	_cache.clear()
	for w in waves:
		var a := deg_to_rad(float(w["dir"]))
		var k := TAU / float(w["length"])
		_cache.append(PackedFloat32Array([cos(a), sin(a), k, sqrt(GRAVITY / k), float(w["steepness"])]))
