extends SceneTree
# A scripted play session for the screenshot: sow all four beds with different crops, run 40 days with automatic
# irrigation, select a ready plant, and capture the frame. Used to eyeball the whole scene.
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var scene: Node3D = (load("res://scenes/greenhouse.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_speed(0.0)
	var crops := ["lettuce", "radish", "tomato", "potato"]
	for b in 4:
		scene.crop_key = crops[b]
		scene.select_slot(b, 0)
		scene.action_sow_bed()
	scene.bay.set_setting("auto_irrigate", true)
	scene.bay.set_setting("nutrient_stock", 40.0)
	for b in 4:
		scene.bay.feed(b, 3.0)
	var days := int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 40
	scene.bay.advance_hours(24.0 * days)
	scene._refresh_all()
	scene.select_slot(0, 2)
	scene.bay.set_setting("light_on_hour", 0.0)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("saved ", path, " err=", img.save_png(path))
	quit(0)
