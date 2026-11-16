extends Node3D
## Draws the ocean and keeps its shader in step with the Waves service.
##
## A finely subdivided plane follows the camera, snapped to its own vertex
## spacing so vertices never swim. A flat ring around it reaches the horizon;
## waves fade out before the fine plane ends (see Waves.FADE_END), so the two
## meet without a seam.

const SHADER := preload("res://world/ocean/ocean.gdshader")

@export var near_size := 1000.0
@export var near_subdivisions := 499
@export var far_size := 24000.0

var _material: ShaderMaterial
var _near: MeshInstance3D
var _far: MeshInstance3D


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER

	var near_mesh := PlaneMesh.new()
	near_mesh.size = Vector2(near_size, near_size)
	near_mesh.subdivide_width = near_subdivisions
	near_mesh.subdivide_depth = near_subdivisions
	near_mesh.material = _material
	_near = MeshInstance3D.new()
	_near.name = "NearWater"
	_near.mesh = near_mesh
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Waves move vertices up to a couple of metres; keep culling generous.
	_near.extra_cull_margin = 8.0
	add_child(_near)

	_far = MeshInstance3D.new()
	_far.name = "FarWater"
	_far.mesh = _build_far_ring(near_size * 0.5 - 30.0, far_size * 0.5)
	_far.material_override = _material
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_far)

	_push_waves()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var step := near_size / float(near_subdivisions + 1)
		var p := cam.global_position
		_near.global_position = Vector3(snappedf(p.x, step), 0.0, snappedf(p.z, step))
		_far.global_position = _near.global_position
	_material.set_shader_parameter("wave_time", Waves.time)
	_material.set_shader_parameter("amp_scale", Waves.amplitude_scale)
	_material.set_shader_parameter("fade_origin", Waves.fade_origin)


## Call after changing Waves.waves (for example when the weather changes).
func _push_waves() -> void:
	var p := Waves.shader_wave_params()
	_material.set_shader_parameter("wave_a", p[0])
	_material.set_shader_parameter("wave_b", p[1])
	_material.set_shader_parameter("wave_c", p[2])
	_material.set_shader_parameter("wave_d", p[3])
	_material.set_shader_parameter("fade_start", Waves.FADE_START)
	_material.set_shader_parameter("fade_end", Waves.FADE_END)


## A flat square ring from `inner` to `outer` half-width, as four quads.
func _build_far_ring(inner: float, outer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var quads := [
		Rect2(-outer, -outer, outer * 2.0, outer - inner),
		Rect2(-outer, inner, outer * 2.0, outer - inner),
		Rect2(-outer, -inner, outer - inner, inner * 2.0),
		Rect2(inner, -inner, outer - inner, inner * 2.0),
	]
	for r: Rect2 in quads:
		var a := Vector3(r.position.x, 0, r.position.y)
		var b := Vector3(r.end.x, 0, r.position.y)
		var c := Vector3(r.end.x, 0, r.end.y)
		var d := Vector3(r.position.x, 0, r.end.y)
		# Clockwise seen from above, which is Godot's front face.
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	return st.commit()
