class_name DevDesigns
## Designs built in code for development and tests. The test tinny is what
## step 2's tutorial will teach the player to build from their starter kit.

## A 3.5 m by 1.75 m aluminium tinny with a 15 hp outboard. Bow is towards -Z.
static func test_tinny() -> VesselDesign:
	var d := VesselDesign.new()
	d.design_name = "Test tinny"
	var hull := &"hull_aluminium"
	var wedge := &"hull_aluminium_wedge"
	# Rotate a wedge so its slope faces down and forward: the raked bow.
	var bow_rot := Orientations.index_of(Basis(Vector3.FORWARD, PI))
	const X0 := -3
	const X1 := 3
	const Z_BOW := -7
	const Z_STERN := 6
	for x in range(X0, X1 + 1):
		d.add_block(wedge, Vector3i(x, 0, Z_BOW), bow_rot)
		for z in range(Z_BOW + 1, Z_STERN + 1):
			d.add_block(hull, Vector3i(x, 0, z))
		# Bow wall and transom.
		d.add_block(hull, Vector3i(x, 1, Z_BOW + 1))
		d.add_block(hull, Vector3i(x, 1, Z_STERN))
	for z in range(Z_BOW + 2, Z_STERN):
		d.add_block(hull, Vector3i(X0, 1, z))
		d.add_block(hull, Vector3i(X1, 1, z))
	# Fittings.
	d.add_block(&"bench_seat", Vector3i(-2, 1, -2))
	d.add_block(&"bench_seat", Vector3i(-1, 1, -2))
	d.add_block(&"bench_seat", Vector3i(0, 1, -2))
	d.add_block(&"bench_seat", Vector3i(1, 1, -2))
	d.add_block(&"bench_seat", Vector3i(2, 1, -2))
	d.add_block(&"seat_helm", Vector3i(-1, 1, 4))
	d.add_block(&"fuel_tank_12l", Vector3i(1, 1, 5))
	# Outboard hangs off the transom, leg down below the hull.
	d.add_block(&"outboard_15hp", Vector3i(0, -2, Z_STERN + 1))
	return d
