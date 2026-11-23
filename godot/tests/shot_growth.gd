extends SceneTree
# A scripted play session for the screenshot: sow all four beds with different crops, run some days (40 by default)
# with automatic irrigation, select a ready plant, and capture the frame (real renderer, off-screen). Used to eyeball
# the whole scene.
#
#   Godot --path godot --resolution 1600x900 --position -3000,-3000 -s res://tests/shot_growth.gd -- <name> [days] [view] [idle_seconds]
#
# Saves godot/shots/<name>.png (that folder is git-ignored). A name ending in .jpg is saved as a small JPEG instead,
# which is how the README image is made.
#   view: default (the camera the game starts with), `at:x,y,z:distance:yaw:pitch` (look at any point from there),
#         `wide` (pulled back to take in the whole room) or `window` (turned to face the window).
#   idle_seconds: where the astronaut's idle animation is frozen (default 3.0).
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var shot_name: String = args[0] if args.size() > 0 else "greenhouse"
	var days := int(args[1]) if args.size() > 1 else 40
	var view: String = args[2] if args.size() > 2 else "default"
	var idle_t := float(args[3]) if args.size() > 3 else 3.0
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
	scene.bay.advance_hours(24.0 * days)
	scene._refresh_all()
	scene.voice.set_audio(false)                 # captions only: a screenshot must not speak through the speakers
	scene.select_slot(0, 2)
	scene.bay.set_setting("light_on_hour", 0.0)
	if view.begins_with("at:"):          # at:x,y,z:distance:yaw:pitch  - look at any point
		var parts := view.substr(3).split(":")
		var p := parts[0].split(",")
		scene._pivot.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		scene._dist = float(parts[1])
		scene._yaw = float(parts[2])
		scene._pitch = float(parts[3])
		scene._apply_camera()
	elif view == "wide":
		scene._yaw = 0.5
		scene._pitch = -0.35
		scene._dist = 9.0
		scene._apply_camera()
	elif view == "window":
		scene._pivot.position = Vector3(0, 1.4, -1.5)
		scene._yaw = 0.0
		scene._pitch = -0.1
		scene._dist = 4.0
		scene._apply_camera()
	scene._toast_time = 0.0                      # no toast in the picture
	scene._toast.modulate.a = 0.0
	if scene.astronaut != null:
		scene.astronaut.look_at_point(scene.voice.slot_point(0, 2), 10.0, true)
	if scene.astronaut != null:
		scene.astronaut.set_process(false)
		scene.astronaut.pose(idle_t)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var jpg := shot_name.ends_with(".jpg")      # a name ending in .jpg is saved as a small JPEG (README images)
	var path := ProjectSettings.globalize_path("res://shots/%s" % (shot_name if jpg else shot_name + ".png"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("saved ", path, " err=", img.save_jpg(path, 0.88) if jpg else img.save_png(path))
	quit(0)
