extends Node3D
## A development showcase: every crop at every stage, plus the props, on one table. Open it in the editor to
## look at the procedural art, or capture it with tests/shot.gd. Nothing here is gameplay.

const SPECIES := ["lettuce", "radish", "tomato", "potato"]
const SPACING := 0.30

var _builder := FarmShapeBuilder.new()

func _stages() -> Array:
	return [
		[FarmBay.STAGE_SEED, 0.03], [FarmBay.STAGE_SPROUT, 0.15], [FarmBay.STAGE_VEGETATIVE, 0.45],
		[FarmBay.STAGE_FLOWERING, 0.62], [FarmBay.STAGE_FRUITING, 0.85], [FarmBay.STAGE_READY, 1.0],
		[FarmBay.STAGE_OVERRIPE, 1.0], [FarmBay.STAGE_DEAD, 0.5],
	]

func _ready() -> void:
	_build_environment()
	_build_table()
	_build_lineup()
	_build_props()
	_build_camera()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0a0a0b")
	# a sky nobody sees, for the metal to reflect and the room to be lit by (see greenhouse.gd)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.80, 0.77, 0.72)
	sky_mat.sky_horizon_color = Color(0.62, 0.60, 0.57)
	sky_mat.ground_horizon_color = Color(0.30, 0.30, 0.31)
	sky_mat.ground_bottom_color = Color(0.08, 0.08, 0.09)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.shadow_enabled = true
	add_child(sun)

func _build_table() -> void:
	add_child(_builder.build_node({"shape": "box", "name": "Table", "size": Vector3(3.0, 0.04, 2.6),
			"albedo_color": Color("3a3d42"), "roughness": 0.45, "metallic": 0.7}))
	($Table as Node3D).position = Vector3(1.05, -0.02, -0.2)

func _build_lineup() -> void:
	var stages := _stages()
	for r in SPECIES.size():
		for c in stages.size():
			var node: Node3D = _builder.build_node({
				"shape": "plant", "species": SPECIES[r], "stage": stages[c][0], "progress": stages[c][1],
				"health": 0.25 if stages[c][0] == FarmBay.STAGE_DEAD else 1.0, "seed": 100 + r * 10 + c,
			})
			node.position = Vector3(c * SPACING, 0.0, r * SPACING)
			add_child(node)

func _build_props() -> void:
	var recipe := {"shape": "planter_tray", "rows": 2, "cols": 4,
			"soil_skin": {"kind": "soil", "seed": 3, "dark_color": Color("1d140d"), "base_color": Color("3a2a1c"), "highlight_color": Color("6b5238")}}
	var tray: Node3D = _builder.build_node(recipe)
	tray.position = Vector3(0.7, 0.0, -0.95)
	add_child(tray)
	var slots := _builder.get_slot_positions(recipe)
	var kinds := ["lettuce", "radish", "tomato", "potato"]
	for i in slots.size():
		var plant: Node3D = _builder.build_node({"shape": "plant", "species": kinds[i % 4], "stage": FarmBay.STAGE_READY, "progress": 1.0, "seed": 40 + i})
		plant.position = tray.position + slots[i]
		add_child(plant)

	var light: Node3D = _builder.build_node({"shape": "grow_light"})
	light.position = tray.position + Vector3(0, 0.78, 0)
	add_child(light)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.9, 0.76)
	glow.light_energy = 1.6
	glow.omni_range = 1.6
	glow.position = light.position + Vector3(0, -0.12, 0)
	add_child(glow)

	var tank: Node3D = _builder.build_node({"shape": "tank"})
	tank.position = Vector3(2.15, 0.0, -0.9)
	add_child(tank)

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 48.0
	add_child(cam)
	cam.position = Vector3(1.05, 1.15, 2.35)
	cam.look_at(Vector3(1.05, 0.12, -0.15))
	cam.make_current()
