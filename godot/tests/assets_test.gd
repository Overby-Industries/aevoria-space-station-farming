extends SceneTree
# The Blender-modelled props must be drop-in replacements for the procedural shapes: same size, same origin, same
# planting slots. This builds each both ways through FarmShapeBuilder and compares them, then checks the materials
# and node names the game relies on.
#
#   Godot --headless --path godot --import   (once, so the .glb files are imported)
#   Godot --headless --path godot -s res://tests/assets_test.gd

var checks := 0
var failures := 0

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL  ", what)

# the bounding box of everything drawable under `node`, in the node's own space
func bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		if n is Node3D and n != node:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var box: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
			out = box if first else out.merge(box)
			first = false
		for c in n.get_children():
			stack.append([c, xf])
	return out

func find_material(node: Node, material_name: String) -> StandardMaterial3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m != null and m.resource_name == material_name:
					return m as StandardMaterial3D
		var deeper := find_material(c, material_name)
		if deeper != null:
			return deeper
	return null

func _initialize() -> void:
	var sb := FarmShapeBuilder.new()

	# ---- the planter ----
	var tray_recipe := {"shape": "planter_tray", "rows": 2, "cols": 4}
	var proc: Node3D = sb.build_node(tray_recipe)
	var model: Node3D = sb.build_node({"shape": "planter_tray", "rows": 2, "cols": 4, "model": "res://models/planter_tray.glb"})
	check(model.get_child_count() > 0 and model.name == "planter_tray" or model.name == &"planter_tray", "the planter model is the imported scene (%s)" % model.name)
	var pb := bounds(proc)
	var mb := bounds(model)
	check(absf(pb.size.y - mb.size.y) < 0.01, "planter height matches: %f vs %f" % [pb.size.y, mb.size.y])
	check(absf(pb.size.z - mb.size.z) < 0.02, "planter width matches: %f vs %f" % [pb.size.z, mb.size.z])
	check(absf(pb.size.x - mb.size.x) < 0.05, "planter length matches (the model adds an inlet pipe): %f vs %f" % [pb.size.x, mb.size.x])
	check(absf(pb.position.y - mb.position.y) < 0.005, "planter origin is at the bottom in both")
	check(absf((pb.position.z + pb.size.z * 0.5) - (mb.position.z + mb.size.z * 0.5)) < 0.01, "planter is centred on z in both")
	# the slots: the empties in the model sit where the C++ code says
	var slots := sb.get_slot_positions(tray_recipe)
	for i in slots.size():
		var marker := model.get_node_or_null("Slot_%d" % i) as Node3D
		check(marker != null, "the model has Slot_%d" % i)
		if marker != null:
			check(marker.position.distance_to(slots[i]) < 0.002, "Slot_%d is at %s, C++ says %s" % [i, str(marker.position), str(slots[i])])
	check(find_material(model, "Soil_Dark") != null, "the planter has its soil material")
	proc.free(); model.free()

	# ---- the grow light ----
	var lp: Node3D = sb.build_node({"shape": "grow_light"})
	var lm: Node3D = sb.build_node({"shape": "grow_light", "model": "res://models/grow_light.glb"})
	var lpb := bounds(lp)
	var lmb := bounds(lm)
	check(absf(lpb.size.x - lmb.size.x) < 0.03, "light length matches: %f vs %f" % [lpb.size.x, lmb.size.x])
	check(absf(lpb.size.z - lmb.size.z) < 0.02, "light depth matches")
	check(absf((lpb.position.y + lpb.size.y) - (lmb.position.y + lmb.size.y)) < 0.01, "the hangers reach the same height")
	check(absf(lpb.position.y - lmb.position.y) < 0.01, "the LED face is at the same height")
	var led := find_material(lm, "LED_Emissive")
	check(led != null and led.emission_enabled, "the model's LED material glows")
	if led != null:
		check(led.emission_energy_multiplier > 1.0, "the LED glow is bright (%f)" % led.emission_energy_multiplier)
	lp.free(); lm.free()

	# ---- the tank ----
	var tp: Node3D = sb.build_node({"shape": "tank"})
	var tm: Node3D = sb.build_node({"shape": "tank", "model": "res://models/water_tank.glb"})
	var tpb := bounds(tp)
	var tmb := bounds(tm)
	check(absf(tpb.size.z - tmb.size.z) < 0.03, "tank width matches: %f vs %f" % [tpb.size.z, tmb.size.z])
	check(tmb.size.y >= tpb.size.y - 0.01 and tmb.size.y < tpb.size.y + 0.15, "tank height matches, plus the fill pipe: %f vs %f" % [tpb.size.y, tmb.size.y])
	check(absf(tpb.position.y - tmb.position.y) < 0.01, "tank origin is at the bottom in both")
	check(find_material(tm, "Gauge_Emissive") != null, "the tank has its glowing gauge")
	tp.free(); tm.free()

	# ---- the extras ----
	var crate: Node3D = sb.build_node({"shape": "box", "model": "res://models/seam_crate_missing.glb"})
	check(crate != null, "a missing model still falls back")
	crate.free()
	var c2: Node3D = sb.build_node({"shape": "box", "model": "res://models/seed_crate.glb"})
	var cb := bounds(c2)
	check(absf(cb.size.x - 0.41) < 0.03 and absf(cb.size.z - 0.31) < 0.03 and cb.size.y > 0.2 and cb.size.y < 0.3, "the seed crate is about 0.4 x 0.25 x 0.3 m: %s" % str(cb.size))
	check(absf(cb.position.y) < 0.005, "the crate stands on y = 0")
	c2.free()
	var wp: Node3D = sb.build_node({"shape": "box", "model": "res://models/wall_panel.glb"})
	var wb := bounds(wp)
	check(absf(wb.size.x - 1.0) < 0.02 and absf(wb.size.y - 3.2) < 0.02 and wb.size.z < 0.2, "the wall panel is 1 x 3.2 m and shallow: %s" % str(wb.size))
	check(wb.position.z + wb.size.z > 0.0 and wb.position.z < 0.0, "the panel straddles its mounting plane")
	check(find_material(wp, "Strip_Emissive") != null, "the panel has its light strip")
	wp.free()

	print("\n%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
