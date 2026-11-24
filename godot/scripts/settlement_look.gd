extends RefCounted
## How the settlement looks in this game (the station game): the hub of Aevoria Station in orbit over the Earth, four docking arms, and a
## greenhouse module on each arm that has been built. scripts/settlement_view.gd (the same in both games) asks for everything here.
## Mars Farming has its own copy of this file, with domes on a plain.
##
## 1 unit is 1 m. The hub is 12 m across, each arm runs from the hub to a docking collar 21 m out, and a greenhouse is 14 m long on the
## far side of its collar, with solar wings.

const PLACE := "station"
const NOUN := "greenhouse"
const TITLE := "AEVORIA STATION"
const MEDIUM := "growing medium"
const TUNING := {}
const PALETTE := {"accent": Color("e8861f"), "panel": Color(0.075, 0.08, 0.09, 0.88), "text": Color("e6e8eb")}
const SITES := [Vector3(0, 0, -21), Vector3(21, 0, 0), Vector3(0, 0, 21), Vector3(-21, 0, 0)]    # the docking collar at the end of each arm
const ARM_FROM := 6.0                                           # the arms start at the hub's wall
const ARM_LENGTH := 15.0

const AMBER := Color("e8861f")

static func make_bay() -> FarmBay:
	return preload("res://scripts/greenhouse.gd").make_bay()

static func camera_start() -> Dictionary:
	return {"pivot": Vector3(0, 0, 0), "yaw": 0.45, "pitch": -0.72, "dist": 100.0}

static func pick_radius() -> float:
	return 9.0

static func label_offset(i: int) -> Vector3:
	return _dir(i) * 8.0 + Vector3(0, 8.5, 0)

static func locked_text(_view: Node) -> String:
	return "The station has no more docking arms: four greenhouses is all it can hold."

# What a built unit is called on the overview, and what a site builds.
static func unit_label(_site: int, number: int) -> String:
	return "Greenhouse %d" % number

static func site_noun(_site: int) -> String:
	return NOUN

static func closed_text(_site: int) -> String:
	return "This arm is not open yet."

static func _dir(i: int) -> Vector3:
	return (SITES[i] as Vector3).normalized()

# ---------------------------------------------------------------------------------------------------------
# small builders
# ---------------------------------------------------------------------------------------------------------

static func _mat(colour: Color, metallic := 0.0, rough := 0.6, glow := Color.BLACK, glow_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metallic
	m.roughness = rough
	if glow_energy > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = glow_energy
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func _mi(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _cyl(radius: float, height: float, segments := 40) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	return c

static func _sphere(radius: float, squash := 1.0, hemisphere := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 * squash if not hemisphere else radius
	s.is_hemisphere = hemisphere
	s.radial_segments = 48
	s.rings = 24
	return s

static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 40
	t.ring_segments = 14
	return t

# ---------------------------------------------------------------------------------------------------------
# the world: space, the Earth, the hub and its arms
# ---------------------------------------------------------------------------------------------------------

static func _star_sky() -> Sky:
	var img := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.006, 0.016))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 1400:
		var x := rng.randi_range(0, 2046)
		var y := rng.randi_range(0, 1022)
		var v := rng.randf_range(0.35, 1.0)
		var tint := Color(v, v, v).lerp(Color(0.8, 0.88, 1.0) if rng.randf() < 0.5 else Color(1.0, 0.92, 0.8), 0.4)
		img.set_pixel(x, y, tint)
		if v > 0.9:
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				img.set_pixel(x + d.x, y + d.y, tint * 0.8)
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = ImageTexture.create_from_image(img)
	var sky := Sky.new()
	sky.sky_material = mat
	return sky

static func _noise_tex(freq: float, seed_value: int, ramp: Gradient, octaves := 5) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = seed_value
	var t := NoiseTexture2D.new()
	t.width = 1024
	t.height = 512
	t.noise = n
	t.color_ramp = ramp
	t.seamless = true
	return t

static func _planet(parent: Node3D) -> void:
	var ground := Gradient.new()
	ground.offsets = PackedFloat32Array([0.0, 0.47, 0.5, 0.56, 0.74, 1.0])
	ground.colors = PackedColorArray([Color("08224f"), Color("103a74"), Color("33603a"), Color("56703a"), Color("8a7b52"), Color("cfcab9")])
	var earth := _mi(parent, _sphere(420.0), _mat(Color(0.78, 0.8, 0.84), 0.0, 0.9), Vector3(0, -470, -80), Vector3(PI * 0.5, 0, 0))
	(earth.material_override as StandardMaterial3D).albedo_texture = _noise_tex(0.006, 4, ground)
	var cloud_ramp := Gradient.new()
	cloud_ramp.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 1.0])
	cloud_ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.78)])
	var cloud_mat := _mat(Color.WHITE, 0.0, 1.0)
	cloud_mat.albedo_texture = _noise_tex(0.009, 9, cloud_ramp, 4)
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mi(parent, _sphere(423.0), cloud_mat, Vector3(0, -470, -80), Vector3(PI * 0.5, 0.6, 0))
	var haze := _mat(Color(0.4, 0.65, 1.0, 0.12), 0.0, 1.0, Color(0.3, 0.55, 1.0), 0.45)       # the thin blue edge of the air
	haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze.cull_mode = BaseMaterial3D.CULL_FRONT
	_mi(parent, _sphere(436.0), haze, Vector3(0, -470, -80))

static func build_world(root: Node3D) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _star_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.06
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.9
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.rotation = Vector3(-0.8, 0.75, 0.0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.directional_shadow_max_distance = 260.0
	root.add_child(sun)
	_planet(root)

	var metal := _mat(Color("c8ccd2"), 0.8, 0.36)
	var dark := _mat(Color("2c2f34"), 0.7, 0.45)
	var trim := _mat(AMBER, 0.3, 0.4, AMBER, 0.5)
	var window := _mat(Color("fff3d6"), 0.0, 0.3, Color("ffe9b8"), 1.6)
	# the hub: a drum with an amber band, a glass dome and an antenna
	_mi(root, _cyl(6.0, 3.6, 56), metal, Vector3(0, 0, 0))
	_mi(root, _torus(5.95, 6.4), trim, Vector3(0, 0, 0))
	_mi(root, _cyl(6.1, 0.5, 56), dark, Vector3(0, -1.8, 0))
	_mi(root, _sphere(4.0, 1.0, true), _mat(Color(0.55, 0.78, 1.0, 0.35), 0.0, 0.1, Color(0.4, 0.65, 1.0), 0.35), Vector3(0, 1.8, 0))
	_mi(root, _cyl(0.12, 6.0, 8), metal, Vector3(0, 6.5, 0))
	_mi(root, _sphere(0.4), trim, Vector3(0, 9.6, 0))
	for k in 12:                                                    # a ring of lit windows around the drum
		var a := TAU * k / 12.0
		_mi(root, _box(Vector3(0.9, 0.7, 0.25)), window, Vector3(sin(a) * 6.05, 0.4, cos(a) * 6.05), Vector3(0, a, 0))
	# the four arms, each ending in a docking port at its collar
	for i in SITES.size():
		var d := _dir(i)
		var arm := Node3D.new()
		arm.position = d * ARM_FROM
		arm.rotation.y = atan2(d.x, d.z)
		root.add_child(arm)
		_mi(arm, _box(Vector3(2.8, 2.4, ARM_LENGTH)), metal, Vector3(0, 0, ARM_LENGTH * 0.5))
		_mi(arm, _box(Vector3(0.7, 0.14, ARM_LENGTH)), trim, Vector3(0, 1.22, ARM_LENGTH * 0.5))
		_mi(arm, _box(Vector3(0.7, 0.14, ARM_LENGTH)), trim, Vector3(0, -1.22, ARM_LENGTH * 0.5))
		for k in 4:
			_mi(arm, _box(Vector3(0.2, 0.8, 1.1)), window, Vector3(1.42, 0.0, 2.2 + k * 3.4))
			_mi(arm, _box(Vector3(0.2, 0.8, 1.1)), window, Vector3(-1.42, 0.0, 2.2 + k * 3.4))
		_mi(arm, _cyl(2.0, 1.0, 32), dark, Vector3(0, 0, ARM_LENGTH + 0.2), Vector3(PI * 0.5, 0, 0))   # the docking port at its end
	return {"environment": env, "sun": sun}

# ---------------------------------------------------------------------------------------------------------
# a free site: the docking collar, waiting; a unit: a greenhouse module
# ---------------------------------------------------------------------------------------------------------

static func make_pad(i: int) -> Node3D:
	var d := _dir(i)
	var pad := Node3D.new()
	pad.name = "Pad"
	pad.rotation.y = atan2(d.x, d.z)
	var collar := _mi(pad, _torus(2.5, 3.2), _mat(AMBER, 0.2, 0.4, AMBER, 1.0), Vector3(0, 0, 1.2), Vector3(PI * 0.5, 0, 0))
	collar.name = "Collar"
	for k in 4:                                                      # four beacons round the collar
		var a := TAU * k / 4.0 + PI * 0.25
		var beacon := _mi(pad, _sphere(0.4), _mat(AMBER, 0.0, 0.3, AMBER, 2.0), Vector3(sin(a) * 3.0, cos(a) * 3.0, 1.2))
		beacon.name = "Beacon%d" % k
	var ghost := _mi(pad, _cyl(3.7, 13.0, 36), _mat(Color(1.0, 0.8, 0.45, 0.06), 0.0, 1.0, AMBER, 0.15), Vector3(0, 0, 8.0), Vector3(PI * 0.5, 0, 0))
	ghost.name = "Ghost"
	return pad

static func make_unit(i: int) -> Node3D:
	var d := _dir(i)
	var unit := Node3D.new()
	unit.name = "Unit"
	unit.rotation.y = atan2(d.x, d.z)
	var metal := _mat(Color("c8ccd2"), 0.8, 0.36)
	var trim := _mat(AMBER, 0.3, 0.4, AMBER, 0.5)
	var glass := _mat(Color(0.7, 0.95, 0.85, 0.26), 0.0, 0.08, Color(0.5, 0.95, 0.6), 0.22)
	var green := _mat(Color("5fbf4a"), 0.0, 0.7, Color("6fe05a"), 0.8)
	var panel := _mat(Color("1a2a52"), 0.5, 0.3, Color("2b4a9a"), 0.35)
	_mi(unit, _cyl(3.6, 2.4, 40), metal, Vector3(0, 0, 1.2), Vector3(PI * 0.5, 0, 0))                      # the collar end
	_mi(unit, _cyl(3.7, 9.4, 48), glass, Vector3(0, 0, 7.1), Vector3(PI * 0.5, 0, 0))                     # the glass hall
	for k in 6:                                                                                           # ribs along it
		_mi(unit, _torus(3.6, 3.85), metal, Vector3(0, 0, 3.0 + k * 1.75), Vector3(PI * 0.5, 0, 0))
	for row in 3:                                                                                         # the beds inside
		_mi(unit, _box(Vector3(1.0, 0.7, 8.4)), green, Vector3(-1.9 + row * 1.9, -1.9, 7.1))
	_mi(unit, _cyl(3.6, 2.2, 40), metal, Vector3(0, 0, 12.9), Vector3(PI * 0.5, 0, 0))                    # the far end
	_mi(unit, _sphere(3.6, 0.55, true), metal, Vector3(0, 0, 14.0), Vector3(PI * 0.5, 0, 0))
	for side in [-1.0, 1.0]:                                                                             # solar wings on struts
		_mi(unit, _box(Vector3(6.0, 0.12, 8.0)), panel, Vector3(side * 10.2, 3.4, 8.0))
		_mi(unit, _box(Vector3(4.2, 0.3, 0.3)), metal, Vector3(side * 5.0, 3.4, 8.0))
		_mi(unit, _box(Vector3(0.25, 3.0, 0.25)), metal, Vector3(side * 3.0, 1.9, 8.0))
	_mi(unit, _box(Vector3(0.7, 0.16, 9.0)), trim, Vector3(0, 3.76, 7.1))
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 1.0, 0.7)
	glow.light_energy = 1.4
	glow.omni_range = 16.0
	glow.position = Vector3(0, 0.5, 7.1)
	unit.add_child(glow)
	return unit

# ---------------------------------------------------------------------------------------------------------
# a site's look follows its state; the pads breathe when a unit may be built
# ---------------------------------------------------------------------------------------------------------

static func set_pad_state(pad: Node3D, state: String, selected: bool) -> void:
	var collar := pad.get_node_or_null("Collar") as MeshInstance3D
	if collar == null:
		return
	var colour: Color = {"ready": Color("ffd27a"), "waiting": AMBER, "locked": Color(0.45, 0.5, 0.58)}.get(state, AMBER)
	var m := collar.material_override as StandardMaterial3D
	m.albedo_color = colour
	m.emission = colour
	(pad.get_node("Ghost") as MeshInstance3D).visible = state == "ready" or selected
	for k in 4:
		var b := pad.get_node("Beacon%d" % k) as MeshInstance3D
		(b.material_override as StandardMaterial3D).emission = colour
		(b.material_override as StandardMaterial3D).albedo_color = colour

static func pulse(pad: Node3D, clock: float, state: String) -> void:
	var collar := pad.get_node_or_null("Collar") as MeshInstance3D
	if collar == null or not pad.visible:
		return
	var base: float = {"ready": 2.4, "waiting": 0.7, "locked": 0.15}.get(state, 0.7)
	var swing := 0.8 * sin(clock * 4.0) if state == "ready" else 0.0
	(collar.material_override as StandardMaterial3D).emission_energy_multiplier = base + swing
	for k in 4:
		var b := pad.get_node("Beacon%d" % k) as MeshInstance3D
		var on := state == "ready" and int(floor(clock * 3.0 + k)) % 4 == 0
		(b.material_override as StandardMaterial3D).emission_energy_multiplier = (3.5 if on else (0.9 if state != "locked" else 0.1))

# Anything in the world that moves (the station: nothing; Mars: its sky and its greening).
static func animate(_world: Dictionary, _clock: float, _terraform: Dictionary) -> void:
	pass
