extends Node3D
## Headless checks for the workshop: editing rules, inventory accounting,
## undo, the tutorial blueprint, and the workshop scene itself.
## Run: godot --headless --path . res://tests/editor_test.tscn

var _failures: Array[String] = []


func _ready() -> void:
	Inventory.clear()
	StarterKit.give_kit()
	var kit := StarterKit.kit_counts()
	var f: Dictionary = GameState.FACILITIES[&"personal_dock"]
	var ed := DesignEditor.new(VesselDesign.new(), f["min"], f["max"])

	# Placement rules.
	_check(ed.place(&"hull_aluminium", Vector3i(0, 0, 0), 0) == "", "places a hull block")
	_check(ed.place(&"hull_aluminium", Vector3i(0, 0, 0), 0) != "", "refuses to overlap")
	_check(ed.place(&"hull_aluminium", Vector3i(40, 0, 0), 0) != "", "refuses outside the facility")
	_check(Inventory.count(&"hull_aluminium") == kit[&"hull_aluminium"] - 1, "placing uses a block from the inventory")
	ed.undo()
	_check(ed.design.blocks.is_empty() and Inventory.count(&"hull_aluminium") == kit[&"hull_aluminium"], "undo returns the block")
	ed.redo()
	_check(ed.design.blocks.size() == 1, "redo puts it back")
	ed.clear_all()
	_check(ed.design.blocks.is_empty() and Inventory.count(&"hull_aluminium") == kit[&"hull_aluminium"], "clear returns everything")

	# A dragged rectangle is one undo step.
	var rect: Array[Vector3i] = []
	for x in 3:
		for z in 4:
			rect.append(Vector3i(x, 0, z))
	_check(ed.place_many(&"hull_aluminium", rect, 0) == 12, "a 3 by 4 drag places 12 blocks")
	ed.undo()
	_check(ed.design.blocks.is_empty(), "one undo removes the whole drag")

	# The outboard hangs from the cell you click.
	var o := DesignEditor.origin_for_target(&"outboard_15hp", Vector3i(0, 1, 7), 0)
	_check(o == Vector3i(0, -2, 7), "outboard anchors by its top cell (%s)" % o)

	# Build the blueprint the way the tutorial does, step by step.
	var bp := StarterKit.blueprint()
	var steps := StarterKit.tutorial_steps()
	for s in steps:
		for e in bp.blocks:
			if (s["covers"] as Callable).call(e) and not ed.matches_blueprint_entry(e):
				var target: Vector3i = e["cell"] + Orientations.rotate_cell(e["rot"], BlockLibrary.get_block(e["id"]).anchor)
				var problem := ed.place(e["id"], DesignEditor.origin_for_target(e["id"], target, e["rot"]), e["rot"])
				if problem != "":
					_check(false, "blueprint block %s at %s: %s" % [e["id"], e["cell"], problem])
		var p := ed.blueprint_progress(bp, s["covers"])
		_check(p.x == p.y and p.y > 0, "tutorial step \"%s\" complete (%d / %d)" % [s["title"], p.x, p.y])
	for id in StarterKit.SPARES:
		_check(Inventory.count(id) == StarterKit.SPARES[id], "only the spare %s are left over" % id)
	var a := VesselBuilder.analyse(ed.design)
	_check((a["problems"] as Array).is_empty(), "finished tinny has no problems %s" % [a["problems"]])
	_check((a["warnings"] as Array).is_empty(), "finished tinny has no warnings %s" % [a["warnings"]])
	var est: Dictionary = a["estimates"]
	print("Estimates: draft %.1f cm, freeboard %.0f cm, top speed %.1f kn" % [
		est["draft"] * 100.0, est["freeboard"] * 100.0, est["top_speed_kn"]])
	_check(est["top_speed_kn"] > 13.0 and est["top_speed_kn"] < 20.0, "estimated top speed is close to the simulated 16 kn")

	# Problems the workshop should catch.
	var floating := VesselDesign.new()
	floating.add_block(&"hull_aluminium", Vector3i(0, 0, 0))
	floating.add_block(&"hull_aluminium", Vector3i(3, 0, 0))
	var fa := VesselBuilder.analyse(floating)
	_check((fa["problems"] as Array).any(func(t): return "not attached" in t), "detects loose blocks")
	_check((fa["problems"] as Array).any(func(t): return "helm" in t), "requires a helm seat")
	var high := StarterKit.blueprint()
	for e in high.blocks:
		if e["id"] == &"outboard_15hp":
			e["cell"] = Vector3i(0, 1, 7)
	_check((VesselBuilder.analyse(high)["warnings"] as Array).any(func(t): return "propeller" in t), "warns when the propeller is out of the water")

	# Outboards: one tiller motor with the driver in reach, or remote motors
	# steered from a helm seat with a wheel, never both.
	var has := func(design: VesselDesign, word: String) -> bool:
		return (VesselBuilder.analyse(design)["problems"] as Array).any(func(t): return word in t)
	var bp_stats := VesselBuilder.compute_stats(StarterKit.blueprint())
	var grip: Vector3 = bp_stats["engines"][0]["grip"]
	var seat: Vector3 = bp_stats["helm_position"]
	_check(bp_stats["has_helm"] and Vector2(seat.x - grip.x, seat.z - grip.z).length() < VesselBuilder.TILLER_REACH,
			"the starter boat's driver sits within reach of the tiller")
	var two_tillers := StarterKit.blueprint()
	two_tillers.add_block(&"outboard_15hp", Vector3i(-2, -2, 7))
	_check(has.call(two_tillers, "only one tiller"), "only one tiller outboard per boat")
	var mixed := StarterKit.blueprint()
	mixed.add_block(&"outboard_15hp_remote", Vector3i(-2, -2, 7))
	_check(has.call(mixed, "mixed"), "tiller and remote outboards can't be mixed")
	var far := StarterKit.blueprint()
	for e in far.blocks:
		if e["id"] == &"bench_seat" and e["cell"] == Vector3i(-1, 1, 5):
			e["cell"] = Vector3i(-1, 1, 0)
	_check(has.call(far, "within reach"), "the driver's seat must be within reach of the tiller")
	var remote := StarterKit.blueprint()
	for e in remote.blocks:
		if e["id"] == &"outboard_15hp":
			e["id"] = &"outboard_15hp_remote"
	_check(has.call(remote, "wheel"), "remote outboards need a helm seat with a wheel")
	remote.add_block(&"seat_helm", Vector3i(-1, 1, 3))
	remote.add_block(&"outboard_15hp_remote", Vector3i(-2, -2, 7))
	var ra := VesselBuilder.analyse(remote)
	_check((ra["problems"] as Array).is_empty(), "twin remote outboards with a wheel are fine %s" % [ra["problems"]])
	_check(is_equal_approx(ra["stats"]["total_thrust"], 4800.0), "both remote outboards push")
	_check((ra["stats"]["wheel_grips"] as Array).size() == 2, "the wheel gives both hands a place")

	# Loading needs the blocks.
	var big := VesselDesign.new()
	for x in 9:
		for z in 19:
			big.add_block(&"hull_aluminium", Vector3i(x - 4, 0, z - 9))
	var before := ed.design.blocks.size()
	_check(ed.load_design(big) != "" and ed.design.blocks.size() == before, "loading a design you lack blocks for is refused")

	# Grid raycast: straight down onto a block hits its top face.
	var occ := {Vector3i(1, 0, 2): 0}
	var hit := GridRaycast.cast(Vector3(1.2, 6.0, 2.1), Vector3.DOWN, occ)
	_check(hit["hit"] and hit["cell"] == Vector3i(1, 0, 2) and hit["normal"] == Vector3i(0, 1, 0), "raycast finds the top face")

	# The workshop scene opens with the tutorial and tracks progress.
	Inventory.clear()
	StarterKit.give_kit()
	var ws: Node3D = preload("res://vessel/editor/workshop.gd").new()
	add_child(ws)
	ws.call(&"open", VesselDesign.new(), f, true)
	var text: String = ws.call(&"tutorial_text")
	_check(text.begins_with("Step 1 of 5"), "workshop starts the tutorial at step 1")
	var wed: DesignEditor = ws.get(&"editor")
	var bottom: Array[Vector3i] = []
	for e in StarterKit.blueprint().blocks:
		if e["id"] == &"hull_aluminium" and e["cell"].y == 0:
			bottom.append(e["cell"])
	wed.place_many(&"hull_aluminium", bottom, 0)
	_check((ws.call(&"tutorial_text") as String).begins_with("Step 2 of 5"), "laying the bottom moves the tutorial to step 2")
	var outline: MeshInstance3D = ws.get(&"_outline")
	_check(outline.mesh != null and outline.mesh.get_surface_count() > 0, "step 2 shows an outline of the bow blocks")
	_check(ws.get(&"selected_block") == &"hull_aluminium_wedge", "step 2 selects the angled hull block")
	_check(ws.call(&"current_rot") == StarterKit.blueprint().blocks.filter(
			func(e): return e["id"] == &"hull_aluminium_wedge")[0]["rot"], "step 2 pre-rotates the block to match")

	print("%d failure(s)" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
