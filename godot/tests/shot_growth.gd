extends SceneTree
# A scripted play session for the screenshot: sow all four beds with different crops, run some days (40 by default)
# with automatic irrigation, select a ready plant, and capture the frame (real renderer, off-screen). Used to eyeball
# the whole scene.
#
#   Godot --path godot --resolution 1600x900 --position -3000,-3000 -s res://tests/shot_growth.gd -- <name> [days]
#
# Saves godot/shots/<name>.png (that folder is git-ignored). A name ending in .jpg is saved as a small JPEG instead,
# which is how the README image is made.
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
	var shot_name: String = OS.get_cmdline_user_args()[0]
	var jpg := shot_name.ends_with(".jpg")      # a name ending in .jpg is saved as a small JPEG (README images)
	var path := ProjectSettings.globalize_path("res://shots/%s" % (shot_name if jpg else shot_name + ".png"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("saved ", path, " err=", img.save_jpg(path, 0.88) if jpg else img.save_png(path))
	quit(0)
