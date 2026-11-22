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

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
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

	print("\n%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
