extends Node3D
## A tall glowing column over wherever the active job wants you to go, so it
## can be seen from across the water. Hidden when there is no job.

var _label: Label3D


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.8, 0.25, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 60.0
	cyl.radial_segments = 12
	cyl.cap_top = false
	cyl.cap_bottom = false
	column.mesh = cyl
	column.material_override = mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position.y = 30.0
	add_child(column)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 28
	_label.outline_size = 8
	_label.no_depth_test = true
	_label.position.y = 14.0
	add_child(_label)
	Jobs.active_changed.connect(func(_j): _update())
	Jobs.objective_advanced.connect(func(_j): _update())
	_update()


func _update() -> void:
	var job := Jobs.active
	var obj := job.current_objective() if job else {}
	visible = not obj.is_empty()
	if visible:
		global_position = Locations.position_of(obj["location"])
		_label.text = Locations.name_of(obj["location"])
