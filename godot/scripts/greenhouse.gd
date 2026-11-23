extends Node3D
## The first playable slice: one hydroponics bay on the station. Four planter beds on two benches under LED
## grow lights, a water tank, a window onto space. Click a slot, sow a crop, keep it watered and fed, and
## harvest it when it is ready. Everything you see is built here from recipes (docs/GRAPHICS_GUIDE.md); the
## growing itself is the C++ simulation behind FarmBay.
##
## Left-drag nothing, right-drag orbits, mouse wheel zooms, left-click picks a slot.

# The station's palette: brushed steel, graphite and light aluminium for the hull, the benches and the pipes, warm-white
# light, warm amber accents (the same orange as the crew's suit) and the plants' green. Blue is a small accent only: the
# Earth outside the window, the water gauge, the status lights.
const COL_HULL := Color("2c2f34")         # graphite hull plates
const COL_PANEL := Color(0.075, 0.08, 0.09, 0.88)
const COL_AMBER := Color("e8861f")
const COL_ALU := Color("e6e8eb")
const COL_STEEL := Color("9ba1a8")
const COL_BENCH := Color("b7bcc2")        # brushed aluminium
const COL_LABEL := Color(0.80, 0.79, 0.76)   # the small headings in the panels

const BED_ROWS := 2
const BED_COLS := 4
const BED_CENTERS := [Vector3(-0.78, 0.80, -1.05), Vector3(0.78, 0.80, -1.05), Vector3(-0.78, 0.80, 0.55), Vector3(0.78, 0.80, 0.55)]
const SPEEDS := [["Pause", 0.0], ["1x", 1.0], ["4x", 4.0], ["16x", 16.0], ["64x", 64.0]]

# The Blender-modelled props (blender/build_assets.py). Each replaces its procedural twin through the "model" seam;
# if a file is missing the procedural shape is used instead, so the scene never breaks for want of an asset.
const MODEL_TRAY := "res://models/planter_tray.glb"
const MODEL_LIGHT := "res://models/grow_light.glb"
const MODEL_TANK := "res://models/water_tank.glb"
const MODEL_CRATE := "res://models/seed_crate.glb"
const MODEL_WALL := "res://models/wall_panel.glb"
const REFRESH_SECONDS := 0.25

# How high the LED bars hang above a bench top (the soil is 0.17 m higher still) and where their wires end. Low bars used to
# cut across the far beds in the start view and poke into a full-grown tomato; at 1.55 m they clear the tallest crop (0.7 m)
# by more than half a metre, and from the start view and the orbit views around it no bar hides a slot (greenhouse_test.gd).
const LIGHT_HEIGHT := 1.55
const ROOM_TOP := 3.35

# The crew astronaut (scripts/astronaut.gd puts it together from the modular components in models/astronaut/). It stands
# on the walkway in front of the near bench, beside its left-hand end, looking over the beds at the window and the Earth.
const Astronaut = preload("res://scripts/astronaut.gd")
const ASTRONAUT_POS := Vector3(-1.95, 0.0, 1.55)
const ASTRONAUT_YAW_DEG := -12.0          # 0 faces the window; negative turns toward the beds on its right

# Earth outside the window: low and large, so only its limb shows across the window
const EARTH_POS := Vector3(-4.0, -24.0, -42.0)
const EARTH_RADIUS := 22.0

const SlotButtons = preload("res://scripts/slot_buttons.gd")
const CrewVoice = preload("res://scripts/crew_voice.gd")
const ColonyUI = preload("res://scripts/colony_ui.gd")
const TRAINING_SCENE := "res://scenes/training.tscn"      # the how-to-play training for new players (scripts/training.gd)

var bay := FarmBay.new()
var builder := FarmShapeBuilder.new()
var slot_buttons: Control                  # the floating buttons over the slots (scripts/slot_buttons.gd)
var voice: Node                            # the crew member's voice (scripts/crew_voice.gd)
var hud_palette := {}                       # the HUD's accent, panel and text colours; the training scene dresses its coach panel to match
var colony_ui: Control                     # the colony bar, the difficulty picker, the ending and the leaderboard (scripts/colony_ui.gd); none while the training hosts the game
var ask_difficulty := DisplayServer.get_name() != "headless"      # open the difficulty picker with the scene; headless runs (the tests) start as a sandbox
var colony_place := "station"                    # how the ending texts name the place
var colony_tuning := {}                    # scales for what this bay can grow, by difficulty: {"demand": [...], "reserve": [...]}, 1.0 when absent
var astronaut: Node3D
var astronaut_recipe := {}                  # optional look of the crew member (scripts/astronaut.gd lists the keys); set before the scene enters the tree

var selected := Vector2i(-1, -1)          # (bed, slot), or (-1, -1)
var crop_key := "lettuce"

var _tray_recipe := {}
var _slot_offsets: PackedVector3Array
var _plants := {}                          # Vector2i -> Node3D, the plant standing in that slot
var _plant_keys := {}                      # Vector2i -> String, what that visual was built from
var _bars: Array = []                      # [{node, box (world), meshes, fade, blocking}] per LED bar, see fade_blocking_lights()
var _lights: Array = []                    # [{led: StandardMaterial3D, omni: OmniLight3D}] per bed
var _ring: MeshInstance3D
var _refresh := 0.0
var _species: Array = []

var _cam: Camera3D
var _pivot: Node3D
# The start view: over the astronaut's shoulder at the benches, the window and the Earth beyond. The pivot sits left of
# the middle so the walkway is in the picture; every slot stays clear of the HUD panels (greenhouse_test.gd checks).
const START_PIVOT := Vector3(-0.3, 1.02, 0.35)
var _yaw := 0.14
var _pitch := -0.42
var _dist := 5.1
var _orbiting := false

# HUD
var _status_label: Label
var _tank_bar: ProgressBar
var _harvest_label: Label
var _sel_title: Label
var _sel_info: Label
var _sel_progress: ProgressBar
var _sel_health: ProgressBar
var _crop_picker: OptionButton
var _plant_btn: Button
var _sow_btn: Button
var _water_btn: Button
var _feed_btn: Button
var _harvest_btn: Button
var _remove_btn: Button
var _auto_check: CheckBox
var _led_slider: HSlider
var _toast: Label
var _toast_time := 0.0

func _ready() -> void:
	_species = bay.get_species_list()
	bay.name = "Bay"
	add_child(bay)
	for i in BED_CENTERS.size():
		bay.add_bed(BED_ROWS, BED_COLS, 0.72)
	bay.time_scale = 4.0
	bay.plant_stage_changed.connect(_on_stage_changed)
	bay.plant_died.connect(func(b, s): _say("A plant in bed %d died" % (b + 1)))

	get_viewport().msaa_3d = Viewport.MSAA_4X       # the suit's plates and hoses have fine edges
	_build_environment()
	_build_room()
	_build_beds()
	_build_window()
	_build_astronaut()
	_build_camera()
	_build_hud()
	_apply_camera()
	_refresh_all()

# ---------------------------------------------------------------------------------------------------------
# the world
# ---------------------------------------------------------------------------------------------------------

func _build_environment() -> void:
	# The background is black space, seen through the window and over the walls. The SKY is never drawn: it lights the room
	# and is what the metal reflects (warm white overhead, graphite underfoot), which is most of what makes steel look like steel.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.80, 0.77, 0.72)
	sky_mat.sky_horizon_color = Color(0.62, 0.60, 0.57)
	sky_mat.ground_horizon_color = Color(0.30, 0.30, 0.31)
	sky_mat.ground_bottom_color = Color(0.08, 0.08, 0.09)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("040405")
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color("fff0d6")
	key.light_energy = 1.0
	key.rotation_degrees = Vector3(-58, 20, 0)
	key.shadow_enabled = true
	add_child(key)

	# a warm white lamp in the middle of the ceiling, so leaves read green under the LEDs
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("fff0dc")
	lamp.light_energy = 1.1
	lamp.omni_range = 10.0
	lamp.position = Vector3(0, 3.0, -0.3)
	add_child(lamp)

func _box(name: String, pos: Vector3, size: Vector3, color: Color, rough := 0.7, metal := 0.0) -> Node3D:
	var n: Node3D = builder.build_node({"shape": "box", "name": name, "size": size, "albedo_color": color, "roughness": rough, "metallic": metal})
	n.position = pos
	add_child(n)
	if name in ["BenchTop", "BenchLeg", "BenchTrim", "Hanger"]:
		n.add_to_group("furniture")
	return n

func _build_room() -> void:
	# a hab-ring module 8 m wide, 3.2 m high, 6.5 m deep: graphite hull plates, a steel deck; the camera looks in through the missing near wall
	var half_w := 4.0
	var h := 3.2
	_deck_skin(_box("Floor", Vector3(0, -0.05, -0.5), Vector3(half_w * 2, 0.1, 6.5), Color(1, 1, 1), 0.5, 0.7))
	# no ceiling: the room is a cutaway, so the camera can look down into it
	_brushed(_box("WallLeft", Vector3(-half_w - 0.05, h * 0.5, -0.5), Vector3(0.1, h, 6.5), COL_HULL, 0.5, 0.7), 1.2)
	_brushed(_box("WallRight", Vector3(half_w + 0.05, h * 0.5, -0.5), Vector3(0.1, h, 6.5), COL_HULL, 0.5, 0.7), 1.2)
	# wall panels along both side walls (they face the room; the boxes above are their backing)
	for i in 6:
		for side in [-1.0, 1.0]:
			var panel: Node3D = builder.build_node({"shape": "box", "name": "WallPanel", "model": MODEL_WALL, "size": Vector3(1.0, 3.2, 0.1), "albedo_color": COL_HULL})
			panel.position = Vector3(side * half_w, 0.0, -3.25 + float(i))
			panel.rotation_degrees.y = 90.0 if side < 0.0 else -90.0   # local +z, the room side, turns to face the middle of the room
			add_child(panel)
	# back wall with a wide window slot, from four pieces
	var back_z := -3.8
	_box("BackLow", Vector3(0, 0.45, back_z), Vector3(half_w * 2, 0.9, 0.1), COL_HULL, 0.5, 0.7)
	_box("BackHigh", Vector3(0, 2.95, back_z), Vector3(half_w * 2, 0.5, 0.1), COL_HULL, 0.5, 0.7)
	_box("BackLeft", Vector3(-3.1, 1.65, back_z), Vector3(1.8, 1.8, 0.1), COL_HULL, 0.5, 0.7)
	_box("BackRight", Vector3(3.1, 1.65, back_z), Vector3(1.8, 1.8, 0.1), COL_HULL, 0.5, 0.7)
	# gold trim along the window and the floor line
	_box("TrimBottom", Vector3(0, 0.92, back_z + 0.06), Vector3(4.4, 0.06, 0.06), COL_AMBER, 0.35, 0.6)
	_box("TrimTop", Vector3(0, 2.72, back_z + 0.06), Vector3(4.4, 0.06, 0.06), COL_AMBER, 0.35, 0.6)
	_box("TrimLeft", Vector3(-2.2, 1.82, back_z + 0.06), Vector3(0.06, 1.86, 0.06), COL_AMBER, 0.35, 0.6)
	_box("TrimRight", Vector3(2.2, 1.82, back_z + 0.06), Vector3(0.06, 1.86, 0.06), COL_AMBER, 0.35, 0.6)
	for side in [-1.0, 1.0]:
		_box("Stripe", Vector3(side * (half_w - 0.0), 0.35, -0.5), Vector3(0.02, 0.06, 6.5), COL_AMBER, 0.4, 0.5)

	# two benches the beds stand on: a steel top on four legs
	for z in [-1.05, 0.55]:
		_brushed(_box("BenchTop", Vector3(0, 0.76, z), Vector3(3.5, 0.04, 0.74), COL_BENCH, 0.34, 0.85), 1.6)
		for x in [-1.65, 1.65]:
			for dz in [-0.3, 0.3]:
				_box("BenchLeg", Vector3(x, 0.37, z + dz), Vector3(0.05, 0.74, 0.05), COL_STEEL, 0.33, 0.9)
		_box("BenchTrim", Vector3(0, 0.74, z + 0.372), Vector3(3.5, 0.03, 0.01), COL_AMBER, 0.4, 0.5)

func _build_beds() -> void:
	var soil_skin := {"kind": "soil", "seed": 3, "dark_color": Color("1d140d"), "base_color": Color("3a2a1c"), "highlight_color": Color("6b5238")}
	_tray_recipe = {"shape": "planter_tray", "rows": BED_ROWS, "cols": BED_COLS, "soil_skin": soil_skin, "model": MODEL_TRAY}
	_slot_offsets = builder.get_slot_positions(_tray_recipe)

	for bi in BED_CENTERS.size():
		var origin: Vector3 = BED_CENTERS[bi]
		var tray: Node3D = builder.build_node(_tray_recipe)
		tray.name = "Bed%d" % bi
		tray.position = origin
		add_child(tray)
		tray.add_to_group("furniture")

		# a grow light hung LIGHT_HEIGHT above the bench, well clear of the tallest crop and out of the way of the camera
		var light: Node3D = builder.build_node({"shape": "grow_light", "model": MODEL_LIGHT})
		light.name = "GrowLight%d" % bi
		light.position = origin + Vector3(0, LIGHT_HEIGHT, 0)
		add_child(light)
		light.add_to_group("furniture")
		var bar_meshes := _bar_meshes(light)
		var bar_box := AABB()
		for i in bar_meshes.size():
			var mi := bar_meshes[i] as MeshInstance3D
			var b := mi.global_transform * mi.mesh.get_aabb()
			bar_box = b if i == 0 else bar_box.merge(b)
		_bars.append({"node": light, "box": bar_box, "meshes": bar_meshes, "fade": 0.0, "blocking": false})
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.9, 0.76)
		omni.omni_range = 2.8                       # far enough to reach the soil from that height
		omni.light_energy = 1.0
		omni.position = light.position + Vector3(0, -0.15, 0)
		add_child(omni)
		_lights.append({"led": _find_led(light), "omni": omni})
		# the ceiling hangers: wires from the bar's own hangers up to the top of the room
		var wire_from := light.position.y + 0.12
		for sx in [-0.4, 0.4]:
			_box("Hanger", Vector3(origin.x + sx, (wire_from + ROOM_TOP) * 0.5, origin.z), Vector3(0.012, ROOM_TOP - wire_from, 0.012), COL_STEEL, 0.35, 0.9)

		# one pick body per slot
		for si in _slot_offsets.size():
			var body := StaticBody3D.new()
			body.set_meta("slot", Vector2i(bi, si))
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.12, 0.46, 0.12)
			shape.shape = box
			body.add_child(shape)
			body.position = origin + _slot_offsets[si] + Vector3(0, 0.22, 0)
			add_child(body)

	# the water tank at the end of the room
	var tank: Node3D = builder.build_node({"shape": "tank", "model": MODEL_TANK})
	tank.position = Vector3(3.1, 0.0, -2.9)
	add_child(tank)
	tank.add_to_group("furniture")

	# a few seed crates by the near end of the benches
	for spec in [[Vector3(3.3, 0.0, 1.1), 12.0], [Vector3(3.3, 0.25, 1.1), -6.0], [Vector3(3.35, 0.0, 0.55), -14.0], [Vector3(2.8, 0.0, 1.3), 8.0]]:
		var crate: Node3D = builder.build_node({"shape": "box", "name": "SeedCrate", "model": MODEL_CRATE, "size": Vector3(0.4, 0.25, 0.3)})
		crate.position = spec[0]
		crate.rotation_degrees.y = spec[1]
		add_child(crate)
		crate.add_to_group("furniture")

	# the selection ring
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.058
	torus.outer_radius = 0.07
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_AMBER
	mat.emission_enabled = true
	mat.emission = COL_AMBER
	mat.emission_energy_multiplier = 2.5
	torus.material = mat
	_ring.mesh = torus
	_ring.visible = false
	add_child(_ring)

# the LED material of a grow light: the procedural one stores it in metadata, a modelled one names it
func _find_led(light: Node) -> StandardMaterial3D:
	if light.has_meta("led_material"):
		return light.get_meta("led_material")
	return _find_material(light, "LED_Emissive")

func _find_material(node: Node, material_name: String) -> StandardMaterial3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m != null and m.resource_name == material_name:
					return m as StandardMaterial3D
		var deeper := _find_material(c, material_name)
		if deeper != null:
			return deeper
	return null

func _build_window() -> void:
	# Earth, low in the window so its limb arcs across it with black space above, a thin atmosphere along the edge, and a
	# scatter of stars behind. Everything else in the room is metal; this is the one big patch of blue, and it is outside.
	var gen := FarmSkinGenerator.new()
	var earth_tex := gen.generate_texture({"kind": "cellular", "seed": 11, "frequency": 0.012, "dark_color": Color("0e3a7a"), "base_color": Color("1f6fb8"), "highlight_color": Color("e8f2ff")}, 512, 256)
	var earth := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = EARTH_RADIUS
	sphere.height = EARTH_RADIUS * 2.0
	var em := StandardMaterial3D.new()
	em.albedo_texture = earth_tex
	em.roughness = 0.9
	em.emission_enabled = true
	em.emission = Color("2a6fd0")
	em.emission_energy_multiplier = 0.25
	sphere.material = em
	earth.mesh = sphere
	earth.position = EARTH_POS
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)

	# the atmosphere: a slightly larger shell seen from inside (front faces culled), so only the rim beyond the globe shows
	var haze := MeshInstance3D.new()
	var shell := SphereMesh.new()
	shell.radius = EARTH_RADIUS * 1.035
	shell.height = EARTH_RADIUS * 2.07
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(0.35, 0.62, 1.0, 0.55)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.cull_mode = BaseMaterial3D.CULL_FRONT
	shell.material = hm
	haze.mesh = shell
	haze.position = EARTH_POS
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)

	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1, 1, 1)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = sm
	mm.mesh = quad
	mm.instance_count = 260
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-30, 30), rng.randf_range(-6, 18), rng.randf_range(-45, -18))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), p))
	stars.multimesh = mm
	add_child(stars)

# Brushed metal: faint streaks along x (a grey multiplier on the box's colour), tiled by triplanar mapping.
var _brushed_texture: ImageTexture

func _brushed(node: Node3D, per_metre := 1.0) -> void:
	if _brushed_texture == null:
		var n := 256
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		var rows := PackedFloat32Array()
		for y in n:
			rows.append(rng.randf())
		var bytes := PackedByteArray()
		bytes.resize(n * n * 3)
		for y in n:
			for x in n:
				var streak := 0.7 * rows[y] + 0.3 * rng.randf()
				var v := int(clampf(1.0 - 0.16 * streak, 0.0, 1.0) * 255.0)
				var i := (y * n + x) * 3
				bytes[i] = v
				bytes[i + 1] = v
				bytes[i + 2] = v
		var img := Image.create_from_data(n, n, false, Image.FORMAT_RGB8, bytes)
		img.generate_mipmaps()
		_brushed_texture = ImageTexture.create_from_image(img)
	var m := ((node.get_child(0) as MeshInstance3D).mesh as BoxMesh).material as StandardMaterial3D
	m.albedo_texture = _brushed_texture
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * per_metre
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

# Deck plating: a "panel" skin (plates with seams, each a slightly different tone) tiled across the floor by triplanar
# mapping, so the box needs no UVs.
func _deck_skin(node: Node3D) -> void:
	var gen := FarmSkinGenerator.new()
	var tex := gen.generate_texture({"kind": "panel", "seed": 5, "cells": 4, "frequency": 0.02, "dark_color": Color("2c2e32"), "base_color": Color("4d5157"), "highlight_color": Color("767b81"), "seam_color": Color("1c1d20")}, 512, 512)
	var mi := node.get_child(0) as MeshInstance3D
	var m := (mi.mesh as BoxMesh).material as StandardMaterial3D
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5          # a tile every 2 m: plates half a metre across
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func _build_astronaut() -> void:
	astronaut = Astronaut.new()
	astronaut.name = "Astronaut"
	astronaut.recipe = astronaut_recipe
	astronaut.position = ASTRONAUT_POS
	astronaut.rotation_degrees.y = ASTRONAUT_YAW_DEG
	add_child(astronaut)

func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.position = START_PIVOT
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.far = 120.0
	_pivot.add_child(_cam)
	_cam.make_current()

func _apply_camera() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_cam.position = Vector3(0, 0, _dist)

# ---------------------------------------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist - 0.3, 1.6, 8.0)
			_apply_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist + 0.3, 1.6, 8.0)
			_apply_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pick(mb.position)
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, -1.35, -0.1)
		_apply_camera()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		voice.ask()                 # "C" asks the crew what to do next, like the Ask crew button

func _pick(screen_pos: Vector2) -> void:
	var from := _cam.project_ray_origin(screen_pos)
	var to := from + _cam.project_ray_normal(screen_pos) * 30.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.has("collider") and (hit["collider"] as Object).has_meta("slot"):
		var s: Vector2i = (hit["collider"] as Object).get_meta("slot")
		select_slot(s.x, s.y)
	else:
		select_slot(-1, -1)

# ---------------------------------------------------------------------------------------------------------
# actions, also what the tests drive
# ---------------------------------------------------------------------------------------------------------

func select_slot(bed: int, slot: int) -> void:
	selected = Vector2i(bed, slot)
	if bed >= 0:
		_ring.position = BED_CENTERS[bed] + _slot_offsets[slot] + Vector3(0, 0.004, 0)
	_ring.visible = bed >= 0
	_refresh_hud()

func action_plant() -> bool:
	if selected.x < 0:
		return false
	var ok := bay.plant(selected.x, selected.y, crop_key)
	_refresh_all()
	return ok

func action_sow_bed() -> int:
	if selected.x < 0:
		return 0
	var n := 0
	for s in BED_ROWS * BED_COLS:
		if bay.plant(selected.x, s, crop_key):
			n += 1
	_refresh_all()
	return n

func action_water() -> float:
	if selected.x < 0:
		return 0.0
	var moved := bay.irrigate(selected.x, 2.0)
	if moved <= 0.0:
		_say("Nothing to add: the bed is full or the tank is empty")
	_refresh_hud()
	return moved

func action_feed() -> float:
	if selected.x < 0:
		return 0.0
	var used := bay.feed(selected.x, 1.0)
	if used <= 0.0:
		_say("Nothing to add: the bed is full or the stock is out")
	_refresh_hud()
	return used

func action_harvest() -> Dictionary:
	if selected.x < 0:
		return {"ok": false}
	var h := bay.harvest(selected.x, selected.y)
	if h["ok"]:
		_say("Harvested %.2f kg of %s" % [h["kg"], h["species"]])
	_refresh_all()
	return h

func action_remove() -> bool:
	if selected.x < 0:
		return false
	var ok := bay.remove(selected.x, selected.y)
	_refresh_all()
	return ok

func set_speed(hours_per_second: float) -> void:
	bay.time_scale = hours_per_second

# ---------------------------------------------------------------------------------------------------------
# visuals that follow the simulation
# ---------------------------------------------------------------------------------------------------------

func _on_stage_changed(bed: int, slot: int, stage: int) -> void:
	_refresh_slot(bed, slot)
	if stage == FarmBay.STAGE_READY:
		_say("%s in bed %d is ready" % [bay.get_plant(bed, slot)["name"], bed + 1])

# An LED bar that stands between the camera and any slot fades to a ghost, so from any orbit angle every crop location can be
# seen and picked (the bars hang high, but a steep or sideways view can still look through one). Returns how many bars are in
# the way; `delta` is the time to fade by (the tests use a big one).
func fade_blocking_lights(delta: float) -> int:
	if _cam == null:
		return 0
	var eye := _cam.global_position
	var blocking := 0
	for bar in _bars:
		var blocks := false
		for bi in BED_CENTERS.size():
			for si in _slot_offsets.size():
				if (bar["box"] as AABB).intersects_segment(eye, BED_CENTERS[bi] + _slot_offsets[si] + Vector3(0, 0.12, 0)) != null:
					blocks = true
					break
			if blocks:
				break
		bar["blocking"] = blocks
		blocking += 1 if blocks else 0
		bar["fade"] = move_toward(bar["fade"], 0.88 if blocks else 0.0, delta * 3.0)
		for mi in bar["meshes"]:
			(mi as GeometryInstance3D).transparency = bar["fade"]
	return blocking

func _bar_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_bar_meshes(c))
	return out

func _refresh_all() -> void:
	for b in BED_CENTERS.size():
		for s in BED_ROWS * BED_COLS:
			_refresh_slot(b, s)
	_refresh_hud()

func _refresh_slot(bed: int, slot: int) -> void:
	var key := Vector2i(bed, slot)
	var p := bay.get_plant(bed, slot)
	var visual_key := "empty"
	if not p["empty"]:
		visual_key = "%s|%d|%d|%d" % [p["species"], p["stage"], int(p["progress"] * 50.0), int(p["health"] * 10.0)]
	if _plant_keys.get(key, "") == visual_key:
		return
	_plant_keys[key] = visual_key
	if _plants.has(key):
		(_plants[key] as Node3D).queue_free()
		_plants.erase(key)
	if p["empty"]:
		return
	var node: Node3D = builder.build_node({
		"shape": "plant", "species": p["species"], "progress": p["progress"], "stage": p["stage"],
		"health": p["health"], "seed": p["visual_seed"],
	})
	node.position = BED_CENTERS[bed] + _slot_offsets[slot]
	add_child(node)
	_plants[key] = node

func _process(delta: float) -> void:
	_refresh += delta
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _refresh >= REFRESH_SECONDS:
		_refresh = 0.0
		for b in BED_CENTERS.size():
			for s in BED_ROWS * BED_COLS:
				_refresh_slot(b, s)
		_refresh_hud()
	var on: bool = bay.get_status()["lights_on"]
	for i in _lights.size():
		var led: StandardMaterial3D = _lights[i]["led"]
		led.emission_energy_multiplier = (2.5 * (0.35 + 0.65 * bay.get_bed_info(i)["light_level"])) if on else 0.0
		(_lights[i]["omni"] as OmniLight3D).light_energy = (1.7 * bay.get_bed_info(i)["light_level"]) if on else 0.0
	fade_blocking_lights(delta)

# ---------------------------------------------------------------------------------------------------------
# the HUD
# ---------------------------------------------------------------------------------------------------------

func _say(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast_time = 3.5
	_toast.modulate.a = 1.0
	if voice != null:
		voice.on_toast(text)

func _panel(parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_AMBER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	pc.add_child(box)
	return box

func _label(parent: Control, text: String, size := 14, color := COL_ALU) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.11, 0.12, 0.14, 0.9)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	parent.add_child(bar)
	return bar

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var theme := Theme.new()
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.11, 0.12, 0.14, 0.95), "hover": Color(0.20, 0.21, 0.24, 1.0), "pressed": Color(0.42, 0.27, 0.10, 1.0), "disabled": Color(0.10, 0.10, 0.11, 0.7)}[state]
		sb.border_color = COL_AMBER if state != "disabled" else Color(0.38, 0.38, 0.38)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6)
		theme.set_stylebox(state, "Button", sb)
	theme.set_color("font_color", "Button", COL_ALU)
	theme.set_color("font_disabled_color", "Button", Color(0.52, 0.52, 0.52))
	theme.set_color("font_color", "CheckBox", COL_ALU)
	root.theme = theme

	# floating buttons over the crop slots (Harvest, Water, Feed ...), added first so the panels below draw over them
	slot_buttons = SlotButtons.new()
	root.add_child(slot_buttons)
	slot_buttons.setup(self, {"feed": COL_AMBER})

	# left: the bay
	var left := MarginContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.add_theme_constant_override("margin_left", 14)
	left.add_theme_constant_override("margin_top", 14)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)
	var lbox := _panel(left)
	lbox.custom_minimum_size = Vector2(290, 0)
	_label(lbox, "HYDROPONICS BAY 1", 16, COL_AMBER)
	_status_label = _label(lbox, "")
	_label(lbox, "Water tank", 12, COL_LABEL)
	_tank_bar = _bar(lbox, Color("3aa0e0"))
	_auto_check = CheckBox.new()
	_auto_check.text = "Automatic irrigation"
	_auto_check.toggled.connect(func(on): bay.set_setting("auto_irrigate", on))
	lbox.add_child(_auto_check)
	_label(lbox, "LED brightness (all beds)", 12, COL_LABEL)
	_led_slider = HSlider.new()
	_led_slider.min_value = 0.0
	_led_slider.max_value = 1.0
	_led_slider.step = 0.05
	_led_slider.value = 0.6
	_led_slider.value_changed.connect(func(v): for i in BED_CENTERS.size(): bay.set_bed_light_level(i, v))
	lbox.add_child(_led_slider)
	_harvest_label = _label(lbox, "", 13, Color(0.8, 0.95, 0.8))

	# right: the selected slot
	var right := MarginContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.add_theme_constant_override("margin_right", 14)
	right.add_theme_constant_override("margin_top", 14)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)
	var rbox := _panel(right)
	rbox.custom_minimum_size = Vector2(290, 0)
	_sel_title = _label(rbox, "Nothing selected", 16, COL_AMBER)
	_sel_info = _label(rbox, "Click a slot in a bed.", 13)
	_label(rbox, "Growth", 12, COL_LABEL)
	_sel_progress = _bar(rbox, Color("7bd35a"))
	_label(rbox, "Health", 12, COL_LABEL)
	_sel_health = _bar(rbox, COL_AMBER)
	_crop_picker = OptionButton.new()
	for sp in _species:
		_crop_picker.add_item("%s (%d days)" % [sp["name"], int(sp["days_to_mature"])])
	_crop_picker.item_selected.connect(func(i): crop_key = _species[i]["key"])
	rbox.add_child(_crop_picker)
	_plant_btn = _button(rbox, "Sow this slot", action_plant)
	_sow_btn = _button(rbox, "Sow the whole bed", func(): action_sow_bed())
	_water_btn = _button(rbox, "Water the bed (+2 L)", func(): action_water())
	_feed_btn = _button(rbox, "Feed the bed (+1 unit)", func(): action_feed())
	_harvest_btn = _button(rbox, "Harvest", func(): action_harvest())
	_remove_btn = _button(rbox, "Clear the slot", func(): action_remove())

	# bottom: time
	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("margin_bottom", 14)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	var bbox := _panel(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bbox.add_child(row)
	for sp in SPEEDS:
		var speed: float = sp[1]
		_button(row, sp[0], func(): set_speed(speed))
	row.add_child(VSeparator.new())
	_button(row, "Ask crew (C)", func(): voice.ask())
	var voice_check := CheckBox.new()
	voice_check.text = "Crew voice"
	voice_check.button_pressed = true
	voice_check.toggled.connect(func(on): voice.set_audio(on))
	row.add_child(voice_check)
	var how_sep := VSeparator.new()
	row.add_child(how_sep)
	var how_btn := _button(row, "How to play", func(): get_tree().change_scene_to_file(TRAINING_SCENE))
	how_sep.visible = not has_meta("training")        # the training scene hosts this farm and shows its own coach instead
	how_btn.visible = not has_meta("training")

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 70
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", COL_AMBER)
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)

	# the crew member's voice: speech, captions along the bottom, and the astronaut turning to look at what it describes
	voice = CrewVoice.new()
	add_child(voice)
	hud_palette = {"accent": COL_AMBER, "panel": COL_PANEL, "text": COL_ALU}
	voice.setup(self, astronaut, root, hud_palette)

	# the colony: its bar, the choice of difficulty and voice, the ending and the leaderboard (the training hosts the game without one)
	if not has_meta("training"):
		colony_ui = ColonyUI.new()
		root.add_child(colony_ui)
		colony_ui.setup(self, hud_palette, ask_difficulty)

# What the crew voice may add to its usual advice (scripts/crew_voice.gd calls this): the colony's food, the station's power budget.
func voice_notes() -> Array:
	var notes: Array = colony_ui.voice_notes() if colony_ui != null else []
	notes.append_array(_power_notes())
	return notes

func _power_notes() -> Array:
	var s := bay.get_status()
	if s["lights_on"] and s["power_demand_w"] > s["power_budget_w"] * 1.001:
		return [{"key": "power", "text": "We are over the power budget, so the lights on every bed are dimmed. Turn the LED brightness down to save power."}]
	return []

# What cannot wait (scripts/crew_voice.gd calls this): the colony is out of food.
func urgent_notes() -> Array:
	return colony_ui.urgent_notes() if colony_ui != null else []

# While the difficulty picker, an ending or the leaderboard covers the game, the crew does not chat (scripts/crew_voice.gd asks).
func voice_held() -> bool:
	return colony_ui != null and ["picker", "ending", "board"].has(colony_ui.phase)

func _refresh_hud() -> void:
	if _status_label == null:
		return
	var s := bay.get_status()
	var hh := int(s["clock_h"])
	var mm := int((s["clock_h"] - hh) * 60.0)
	_status_label.text = "Day %d   %02d:%02d   lights %s\nTemperature %.1f C\nPower %.0f / %.0f W (%.1f kWh used)\nNutrient stock %.1f units\nWater %.0f / %.0f L (lost %.1f L)" % [
		s["day"], hh, mm, "ON" if s["lights_on"] else "off", s["temp_c"], s["power_demand_w"], s["power_budget_w"],
		s["energy_kwh"], s["nutrient_stock"], s["tank_l"], s["tank_capacity_l"], s["water_lost_l"]]
	_tank_bar.value = s["tank_l"] / maxf(s["tank_capacity_l"], 0.001)
	var parts: PackedStringArray = []
	for k in s["harvested_by_species"]:
		if s["harvested_by_species"][k] > 0.0:
			parts.append("%s %.2f kg" % [k, s["harvested_by_species"][k]])
	_harvest_label.text = "Harvested %.2f kg%s" % [s["harvested_kg"], ("\n" + ", ".join(parts)) if parts.size() > 0 else ""]

	var has := selected.x >= 0
	for b in [_plant_btn, _sow_btn, _water_btn, _feed_btn, _harvest_btn, _remove_btn, _crop_picker]:
		b.disabled = not has
	if not has:
		_sel_title.text = "Nothing selected"
		_sel_info.text = "Click a slot in a bed."
		_sel_progress.value = 0.0
		_sel_health.value = 0.0
		return
	var info := bay.get_bed_info(selected.x)
	var p := bay.get_plant(selected.x, selected.y)
	_sel_title.text = "Bed %d, slot %d" % [selected.x + 1, selected.y + 1]
	var bed_text := "Bed: water %.1f / %.0f L, nutrients %.0f%%, light %.0f umol/m2/s" % [info["water_l"], info["water_capacity_l"], info["nutrient"] * 100.0, info["ppfd"]]
	if p["empty"]:
		_sel_info.text = "Empty.\n" + bed_text
		_sel_progress.value = 0.0
		_sel_health.value = 0.0
		_plant_btn.disabled = false
		_harvest_btn.disabled = true
		_remove_btn.disabled = true
	else:
		_sel_info.text = "%s: %s\nAge %.1f days, quality %.0f%%\n%s" % [p["name"], p["stage_name"], p["age_days"], p["quality"] * 100.0, bed_text]
		_sel_progress.value = p["progress"]
		_sel_health.value = p["health"]
		_plant_btn.disabled = true
		_harvest_btn.disabled = not p["ready"]
