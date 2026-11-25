class_name BuildKit
extends RefCounted
## Small helpers for placeholder architecture: boxes with collision, signs,
## materials and interaction points. Everything in the town and on the jetties
## is built from these, so real art can replace them one piece at a time.

static var _materials: Dictionary = {}


## A flat-coloured material, shared between every box of the same colour.
static func material(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


## A box with a mesh and, if `body` is given, a matching collision shape.
## `pos` and `size` are in `parent`'s space; `body` must share that space.
static func box(parent: Node3D, body: CollisionObject3D, pos: Vector3, size: Vector3,
		color: Color, tilt_x := 0.0, yaw := 0.0) -> MeshInstance3D:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt_x), pos)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material(color)
	mesh.transform = xf
	parent.add_child(mesh)
	if body:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		col.transform = xf
		body.add_child(col)
	return mesh


## A painted sign that always turns to face the camera around its upright.
static func sign_text(parent: Node3D, text: String, pos: Vector3, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 12
	l.modulate = Color(1, 0.97, 0.88)
	l.outline_modulate = Color(0.1, 0.08, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	parent.add_child(l)
	return l


## A box-shaped spot the player can use with E.
static func interaction(parent: Node3D, node_name: String, prompt: String, pos: Vector3,
		size := Vector3(2.0, 2.2, 2.0)) -> Interactable:
	var i := Interactable.new()
	i.name = node_name
	i.prompt = prompt
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	i.add_child(col)
	i.position = pos
	parent.add_child(i)
	return i


## Where a dock or jetty should meet the land: walking inland from the
## shoreline, the first point where the ground is as high as the deck. A deck
## that started further inland would be buried in the hillside.
static func land_end(shore: Vector3, outward: Vector3, deck_height: float, ground: Callable) -> Vector3:
	var p := Vector3(shore.x, 0.0, shore.z)
	if not ground.is_valid():
		return p - outward * 1.0
	for i in 40:
		if (ground.call(p.x, p.z) as float) >= deck_height - 0.05:
			break
		p -= outward * 0.25
	return p
