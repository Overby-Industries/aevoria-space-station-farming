extends SceneTree
# Drives the greenhouse scene the way a player would, without a window: pick a slot, sow, water, feed, grow a
# lettuce to harvest, and check that the scene's visuals, HUD and the C++ simulation agree.
#
#   Godot --headless --path godot -s res://tests/greenhouse_test.gd

var checks := 0
var failures := 0

func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL  ", what)

func plant_nodes(scene: Node) -> int:
	var n := 0
	for c in scene.get_children():
		if c is Node3D and c.get_child_count() == 1 and c.get_child(0) is MeshInstance3D and (c.get_child(0) as MeshInstance3D).name == "Plant":
			n += 1
	return n

# every drawable box under `node`, in world space
func world_boxes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).is_visible_in_tree():
		out.append((node as MeshInstance3D).global_transform * (node as MeshInstance3D).mesh.get_aabb())
	for c in node.get_children():
		out.append_array(world_boxes(c))
	return out

func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	root.size = Vector2i(1600, 900)      # headless windows are tiny: lay the HUD and the camera out as they are in the game
	var packed: PackedScene = load("res://scenes/greenhouse.tscn")
	check(packed != null, "the greenhouse scene loads")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_speed(0.0)   # the test advances time itself

	var bay: FarmBay = scene.bay
	check(bay.get_bed_count() == 4, "four beds")
	check(bay.get_bed_info(0)["slots"] == 8, "eight slots per bed")
	check(plant_nodes(scene) == 0, "no plants at the start")

	# nothing selected: actions do nothing
	check(not scene.action_plant(), "no selection, no planting")

	# pick a slot and sow
	scene.select_slot(0, 0)
	check(scene.selected == Vector2i(0, 0), "slot selected")
	check(scene.action_plant(), "sow a lettuce")
	check(bay.get_plant(0, 0)["species"] == "lettuce", "the bay holds a lettuce")
	check(plant_nodes(scene) == 1, "a seed mound appears")
	check(not scene.action_plant(), "an occupied slot cannot be sown again")

	# a whole bed of radishes
	scene.crop_key = "radish"
	scene.select_slot(1, 0)
	check(scene.action_sow_bed() == 8, "sow eight radishes")
	check(plant_nodes(scene) == 9, "nine plants stand in the room")

	# water and feed
	bay.get_bed_info(1)
	var before: float = bay.get_status()["tank_l"]
	scene.select_slot(1, 0)
	var bed: Dictionary = bay.get_bed_info(1)
	check(scene.action_water() > 0.0 or bed["water_l"] >= bed["water_capacity_l"] - 0.01, "watering moves water or the bed is full")
	check(bay.get_status()["tank_l"] <= before, "the tank did not gain water")
	bay.set_setting("nutrient_stock", 10.0)
	check(scene.action_feed() >= 0.0, "feeding runs")

	# grow: lettuce to ready, with automatic irrigation so it does not dry out
	bay.set_setting("auto_irrigate", true)
	bay.advance_hours(24.0 * 34.0)
	scene._refresh_all()
	var p: Dictionary = bay.get_plant(0, 0)
	check(p["stage"] == FarmBay.STAGE_READY, "the lettuce is ready after 34 days (stage %s)" % p["stage_name"])
	scene.select_slot(0, 0)
	check(scene.action_harvest()["ok"], "harvest the lettuce")
	check(bay.get_plant(0, 0)["empty"], "the slot is empty again")
	check(bay.get_status()["harvested_kg"] > 0.0, "the harvest is counted")
	await process_frame   # queue_free() takes effect at the end of the frame
	check(plant_nodes(scene) == 8, "the harvested plant's model is gone (%d left)" % plant_nodes(scene))

	# the HUD talks
	check((scene._status_label as Label).text.begins_with("Day "), "the status panel shows the day")
	check((scene._harvest_label as Label).text.contains("Harvested"), "the harvest line shows")

	# clearing
	scene.select_slot(1, 3)
	check(scene.action_remove(), "clear a radish")
	check(not scene.action_remove(), "an empty slot cannot be cleared")

	# ---- the crew astronaut ----
	var man: Node3D = scene.astronaut
	check(man != null and man.is_inside_tree() and man.get_parent() == scene and man.name == "Astronaut", "the astronaut is in the scene tree")
	check(man.assembled and man.missing.is_empty() and man.parts.size() == 11, "assembled from all eleven suit components")
	check(man.global_position.is_equal_approx(scene.ASTRONAUT_POS), "it stands where the scene puts it: %s" % str(man.global_position))
	check(man.is_processing(), "its idle animation runs")
	check(man.find_children("*", "CollisionObject3D", true, false).is_empty(), "it has no collision bodies, so clicks go through to the beds")

	var man_boxes := world_boxes(man)
	var whole := AABB()
	for i in man_boxes.size():
		whole = man_boxes[i] if i == 0 else whole.merge(man_boxes[i])
	check(absf(whole.size.y - 1.8) < 0.05, "it is 1.8 m tall: %.3f m" % whole.size.y)
	check(absf(whole.position.y) < 0.01, "its boots are on the floor")

	# it looks at the crops: toward the window and the nearest bed, within 50 degrees
	var fwd: Vector3 = flat(-man.global_transform.basis.z)
	var best := -1.0
	for centre in scene.BED_CENTERS:
		best = maxf(best, fwd.dot(flat(centre - man.global_position)))
	check(best > cos(deg_to_rad(50.0)), "it faces the beds: its heading is %.0f degrees off the nearest" % rad_to_deg(acos(clampf(best, -1.0, 1.0))))
	check(fwd.z < -0.9, "and the window beyond them (heading z = %.2f)" % fwd.z)

	# clear of the racks, benches, crates, tank and lights: no box of the suit touches a box of the room's furniture
	var furniture: Array = []
	for c in scene.get_tree().get_nodes_in_group("furniture"):
		if scene.is_ancestor_of(c) and c != man:
			furniture.append_array(world_boxes(c))
	check(furniture.size() > 60, "there are furniture boxes to keep clear of (%d)" % furniture.size())
	var touching := 0
	for b in furniture:
		for m in man_boxes:
			if (b as AABB).intersects(m):
				touching += 1
	check(touching == 0, "it intersects no bed, bench, crate, tank, light or hanger (%d overlaps)" % touching)
	var room_to_walk := whole.grow(0.25)
	var crowded := 0
	for b in furniture:
		if (b as AABB).intersects(room_to_walk):
			crowded += 1
	check(crowded == 0, "and there is a quarter of a metre of walkway around it (%d boxes closer)" % crowded)

	# it does not hide a slot in the view the game starts in, and the slots and the astronaut clear the HUD panels
	await process_frame
	await process_frame
	var cam: Camera3D = scene._cam
	var cam_pos := cam.global_position
	var panels: Array = []
	for pc in scene.find_children("*", "PanelContainer", true, false):
		if pc.get_parent() is MarginContainer and pc.get_parent().name != "CrewCaption" and (pc as Control).is_visible_in_tree():      # the HUD's three panels, not a popup's frame
			panels.append((pc as Control).get_global_rect().grow(6.0))
	check(panels.size() == 3, "three HUD panels (left, right, bottom): %s" % str(panels))
	var view := Rect2(Vector2.ZERO, Vector2(1600, 900))
	var hidden := 0
	var under_hud := 0
	var off_screen := 0
	for bi in scene.BED_CENTERS.size():
		for si in scene._slot_offsets.size():
			var at: Vector3 = scene.BED_CENTERS[bi] + scene._slot_offsets[si] + Vector3(0, 0.12, 0)
			for m in man_boxes:
				if (m as AABB).intersects_segment(cam_pos, at) != null:
					hidden += 1
					break
			var px := cam.unproject_position(at)
			if not view.grow(-8.0).has_point(px):
				off_screen += 1
			for r in panels:
				if (r as Rect2).has_point(px):
					under_hud += 1
					break
	check(hidden == 0, "it hides none of the 32 slots from the camera (%d hidden)" % hidden)
	check(off_screen == 0, "every slot is on screen in the start view (%d off)" % off_screen)
	check(under_hud == 0, "and no slot is under a HUD panel (%d under)" % under_hud)
	for point in [Vector3(0, 1.65, 0), Vector3(0, 1.25, 0), Vector3(0, 0.5, 0)]:
		var px := cam.unproject_position(man.global_position + point)
		var clear := view.grow(-4.0).has_point(px)
		for r in panels:
			if (r as Rect2).has_point(px):
				clear = false
		check(clear, "the astronaut's %s is in view and clear of the HUD (%s)" % [str(point), str(px)])

	# clicking works with the astronaut standing there: pick a slot of each bed through the screen
	await physics_frame
	await physics_frame
	for bi in scene.BED_CENTERS.size():
		var slot := 5
		var at: Vector3 = scene.BED_CENTERS[bi] + scene._slot_offsets[slot] + Vector3(0, 0.22, 0)
		scene._pick(cam.unproject_position(at))
		check(scene.selected == Vector2i(bi, slot), "a click on bed %d slot %d picks it (picked %s)" % [bi + 1, slot + 1, str(scene.selected)])

	# ---- the LED bars hang high enough to see and pick every slot ----
	var light_boxes: Array = []
	var lowest := INF
	var bars := 0
	for c in scene.get_children():
		if c is Node3D and str(c.name).begins_with("GrowLight"):
			bars += 1
			for b in world_boxes(c):
				light_boxes.append(b)
				lowest = minf(lowest, (b as AABB).position.y)
	check(bars == 4, "four LED bars")
	var soil_top: float = scene.BED_CENTERS[0].y + 0.17
	check(lowest - soil_top > 1.0, "the lowest bar hangs %.2f m above the soil: over a metre clear of even a full-grown tomato" % (lowest - soil_top))
	# from the view the game starts in no bar stands between the camera and a slot; from steep or sideways orbit views a bar that
	# would is faded to a ghost, so every slot can be seen and picked from any angle
	check(scene.fade_blocking_lights(1.0) == 0, "no bar stands between the start view's camera and a slot")
	var start_view := [scene._yaw, scene._pitch, scene._dist]
	var poses := 0
	var poses_with_a_bar_in_the_way := 0
	var solid_blockers := 0
	for dyaw in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		for pitch in [-0.3, -0.5, -0.8, -1.1]:
			scene._yaw = start_view[0] + dyaw
			scene._pitch = pitch
			scene._apply_camera()
			poses += 1
			if scene.fade_blocking_lights(10.0) > 0:
				poses_with_a_bar_in_the_way += 1
			for bar in scene._bars:
				if bar["blocking"] and bar["fade"] < 0.6:
					solid_blockers += 1
	scene._yaw = start_view[0]
	scene._pitch = start_view[1]
	scene._dist = start_view[2]
	scene._apply_camera()
	scene.fade_blocking_lights(10.0)
	check(poses_with_a_bar_in_the_way > 0, "(some of the %d orbit poses do have a bar in the way: %d)" % [poses, poses_with_a_bar_in_the_way])
	check(solid_blockers == 0, "and in every one of them the bar in the way is faded (%d solid)" % solid_blockers)
	var back: bool = true
	for bar in scene._bars:
		back = back and float(bar["fade"]) == 0.0
	check(back, "back in the start view every bar is solid again")

	scene.queue_free()
	await process_frame
	await process_frame
	print("\n%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
