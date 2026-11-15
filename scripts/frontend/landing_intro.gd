extends Node3D
## The landing intro: the lander descends onto the plain, then the commander and six crew walk
## down the steps and line up. Fully driven by seek(t), so any moment can be shown or tested.

signal caption_changed(index: int)

const SpaceArt := preload("res://scripts/frontend/space_art.gd")
const Lander := preload("res://scripts/world/lander_art.gd")
const Figure := preload("res://scripts/crew/astronaut_figure.gd")
const CrewLooks := preload("res://scripts/crew/crew_looks.gd")
const Look := preload("res://scripts/crew/astronaut_look.gd")

const DESCENT_S := 9.0
const START_HEIGHT := 34.0
const FIRST_EXIT_S := 11.6
const EXIT_GAP_S := 1.05
const DURATION := 30.0
const CAMERA_A := Vector3(15.0, 2.0, 13.5)
const CAMERA_B := Vector3(9.4, 1.65, 6.5)
const LOOK_B := Vector3(4.9, 1.0, 1.1)
const LINEUP_CENTRE := Vector3(5.9, 0.0, 1.9)
const HATCH := Vector3(1.95, 0.89, 0.0)
const STEP_FOOT := Vector3(2.85, 0.0, 0.0)

var manual_time := false
var time := 0.0
var commander: Dictionary = {}
var captions: Array = []
var caption_index := -1
var camera: Camera3D
var lander: Node3D
var figures: Array = []
var _plume: MeshInstance3D
var _dust: CPUParticles3D
var _hatch_light: OmniLight3D
var _plans: Array = []


func setup(commander_look: Dictionary) -> void:
	commander = Look.sanitize(commander_look)
	captions = build_captions(commander.name)


static func build_captions(commander_name: String) -> Array:
	return [
		{"at": 0.0, "title": "SOL 1 · ARRIVAL", "text": "After about seven months crossing deep space, your lander drops through the thin Martian air."},
		{"at": 4.8, "title": "FINAL DESCENT", "text": "Landing rockets fire. The crew braces for touchdown on the northern plains."},
		{"at": 9.4, "title": "TOUCHDOWN", "text": "Engines off. Red dust drifts across the landing plain."},
		{"at": 12.6, "title": "FIRST STEPS", "text": "Commander %s steps onto Mars, followed by a crew of six." % commander_name},
		{"at": 19.0, "title": "THE FIRST OUTPOST", "text": "Together you will build the first human outpost on Mars."},
		{"at": 24.4, "title": "SURVIVAL", "text": "Air, water and power all have to be made, stored and repaired here. Help from Earth is months away."},
		{"at": DURATION, "title": "TRAINING FIRST", "text": "Before the outpost goes live, mission control runs one training shift. You will learn the controls there, one step at a time."},
	]


func _ready() -> void:
	if captions.is_empty():
		setup(Look.default_look())
	_build_world()
	_build_crew()
	camera = Camera3D.new()
	camera.fov = 52.0
	add_child(camera)
	camera.current = true
	seek(0.0)


func _process(delta: float) -> void:
	if not manual_time:
		seek(minf(time + delta, DURATION + 60.0))


func finished() -> bool:
	return time >= DURATION


func seek(t: float) -> void:
	time = t
	# Lander descent with an ease-out, engine plume and dust.
	var fall := clampf(t / DESCENT_S, 0.0, 1.0)
	var height := START_HEIGHT * pow(1.0 - fall, 2.3)
	lander.position = Vector3(-0.6 * (1.0 - fall), height, 0.4 * (1.0 - fall))
	lander.rotation.z = 0.05 * (1.0 - fall) * sin(t * 1.7)
	var burning := t < DESCENT_S + 0.3
	_plume.visible = burning
	if burning:
		var throttle := 0.7 + 0.5 * smoothstep(0.4, 1.0, fall)
		_plume.scale = Vector3(1.0, throttle * (0.9 + 0.1 * sin(t * 31.0)), 1.0)
	_dust.emitting = height < 9.0 and t < DESCENT_S + 1.2
	_hatch_light.light_energy = smoothstep(10.6, 11.4, t) * 1.6
	# Camera: track the descent, then swing round to the crew.
	var blend := smoothstep(9.6, 13.0, t)
	# Aim between the lander and the ground so the horizon stays in frame during descent.
	var look_a := Vector3(lander.position.x, lander.position.y * 0.45 + 2.4, lander.position.z)
	camera.position = CAMERA_A.lerp(CAMERA_B, blend) + Vector3(sin(t * 0.3) * 0.15, 0, 0)
	camera.look_at(look_a.lerp(LOOK_B, blend), Vector3.UP)
	for i in figures.size():
		_pose_crew(i, t)
	var index := 0
	for k in captions.size():
		if t >= float(captions[k].at):
			index = k
	if index != caption_index:
		caption_index = index
		caption_changed.emit(index)


func lineup_position(slot: int) -> Vector3:
	var right := Vector3(0.72, 0, -0.69).normalized()
	return LINEUP_CENTRE + right * (slot - 3) * 0.95


func _pose_crew(i: int, t: float) -> void:
	var figure: Node3D = figures[i]
	var plan: Dictionary = _plans[i]
	var start: float = plan.start
	var label: Label3D = figure.get_node("Name")
	if t < start:
		figure.visible = false
		return
	figure.visible = true
	var goal: Vector3 = plan.goal
	var steps_s := 1.0
	var walk_s: float = STEP_FOOT.distance_to(goal) / 1.35
	var local := t - start
	var facing := Vector3.ZERO
	if local < steps_s:
		var k := local / steps_s
		figure.position = HATCH.lerp(STEP_FOOT, k)
		facing = STEP_FOOT - HATCH
		figure.mode = "walk"
	elif local < steps_s + walk_s:
		var k := (local - steps_s) / walk_s
		figure.position = STEP_FOOT.lerp(goal, k)
		facing = goal - STEP_FOOT
		figure.mode = "walk"
	else:
		figure.position = goal
		facing = camera.global_position - goal if camera != null else Vector3(1, 0, 1)
		var all_out := FIRST_EXIT_S + EXIT_GAP_S * (figures.size() - 1) + steps_s + 3.0
		figure.mode = "idle"
		if t >= all_out and t < all_out + 4.5:
			figure.mode = "wave"
		elif t >= DURATION - 2.0:
			figure.mode = "cheer"
	figure.rotation.y = atan2(facing.x, facing.z)
	figure.pose(t)
	label.modulate.a = clampf((local - steps_s - walk_s) / 0.6, 0.0, 1.0)
	label.outline_modulate.a = label.modulate.a


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.46, 0.36, 0.33)
	sky_material.sky_horizon_color = Color(0.86, 0.66, 0.5)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.3, 0.18, 0.12)
	sky_material.ground_horizon_color = Color(0.78, 0.56, 0.42)
	sky_material.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Same exposure and colour grade as the colony scene (scenes/world/main.tscn).
	sky_material.sky_energy_multiplier = 0.9
	sky_material.sun_curve = 0.2
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.62, 0.6, 0.66)
	environment.ambient_light_sky_contribution = 0.45
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.8, 0.6, 0.46)
	environment.fog_light_energy = 0.9
	environment.fog_density = 0.0065
	environment.fog_sky_affect = 0.35
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 0.95
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.93, 0.84)
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -0.55, -0.7), Vector3.UP)
	add_child(SpaceArt.mars_ground(420.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 70:
		var at := Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 30))
		# Keep the landing pad, the crew's path and the camera's view clear.
		if at.distance_to(Vector3(3, 0, 1)) < 9.0 or Vector2(at.x - 12, at.z - 10).length() < 7.0:
			continue
		var stone := SpaceArt.rock(rng.randf_range(0.15, 0.9), rng.randi())
		stone.position = at
		add_child(stone)
	for i in 9:
		var angle := -2.4 + i * 0.32
		var hill := SpaceArt.rock(rng.randf_range(26, 48), 100 + i)
		hill.position = Vector3(cos(angle) * 150.0, -6.0, sin(angle) * 150.0)
		hill.scale = Vector3(1.6, 0.28, 1.2)
		add_child(hill)
	lander = Node3D.new()
	lander.name = "Lander"
	lander.set_script(Lander)
	add_child(lander)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(1.0, 0.72, 0.4, 0.75)
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume = MeshInstance3D.new()
	_plume.name = "Plume"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.04
	cone.height = 2.2
	_plume.mesh = cone
	_plume.material_override = flame
	_plume.position = Vector3(0, -0.85, 0)
	_plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lander.add_child(_plume)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.7, 0.4)
	glow.light_energy = 2.0
	glow.omni_range = 8.0
	glow.position = Vector3(0, -0.6, 0)
	_plume.add_child(glow)
	_hatch_light = OmniLight3D.new()
	_hatch_light.light_color = Color(1.0, 0.78, 0.5)
	_hatch_light.omni_range = 2.6
	_hatch_light.position = Vector3(2.2, 1.6, 0)
	add_child(_hatch_light)
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 140
	_dust.lifetime = 2.6
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_radius = 2.2
	_dust.emission_ring_inner_radius = 1.0
	_dust.emission_ring_height = 0.1
	_dust.direction = Vector3(1, 0.25, 0)
	_dust.spread = 180.0
	_dust.flatness = 0.85
	_dust.initial_velocity_min = 3.0
	_dust.initial_velocity_max = 7.0
	_dust.damping_min = 2.0
	_dust.damping_max = 3.0
	_dust.gravity = Vector3(0, 0.15, 0)
	_dust.scale_amount_min = 0.8
	_dust.scale_amount_max = 2.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.82, 0.58, 0.42, 0.75))
	ramp.set_color(1, Color(0.82, 0.58, 0.42, 0.0))
	_dust.color_ramp = ramp
	var puff := QuadMesh.new()
	puff.size = Vector2(1.2, 1.2)
	var puff_material := StandardMaterial3D.new()
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var puff_texture := GradientTexture2D.new()
	puff_texture.gradient = soft
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(1.0, 0.5)
	puff_texture.width = 64
	puff_texture.height = 64
	puff_material.albedo_texture = puff_texture
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.vertex_color_use_as_albedo = true
	puff.material = puff_material
	_dust.mesh = puff
	_dust.position = Vector3(0, 0.3, 0)
	_dust.emitting = false
	add_child(_dust)


func _build_crew() -> void:
	var looks: Array = [commander]
	var labels: Array = ["Commander %s" % commander.name]
	for id in CrewLooks.LANDING_CREW:
		looks.append(CrewLooks.look_for(id))
		labels.append("%s\n%s" % [CrewLooks.ROSTER[id].name, CrewLooks.role_label(id)])
	labels[0] = "%s\nCommander (you)" % commander.name
	# The commander takes the centre slot; the crew fill outward alternately.
	var slots := [3, 2, 4, 1, 5, 0, 6]
	for i in looks.size():
		var figure := Figure.new()
		figure.manual_time = true
		figure.phase = i * 0.7
		figure.name = "Crew%d" % i
		add_child(figure)
		figure.apply_look(looks[i])
		var label := Label3D.new()
		label.name = "Name"
		label.text = labels[i]
		label.font_size = 30
		label.outline_size = 10
		label.pixel_size = 0.0036
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		# Alternate tag heights so neighbouring names never collide.
		label.position = Vector3(0, figure.figure_height() + (0.3 if slots[i] % 2 == 0 else 0.68), 0)
		label.modulate = Color(1, 0.86, 0.6) if i == 0 else Color(0.97, 0.95, 0.9)
		label.outline_modulate = Color(0.05, 0.04, 0.05, 0.9)
		figure.add_child(label)
		figures.append(figure)
		_plans.append({"start": FIRST_EXIT_S + EXIT_GAP_S * i, "goal": lineup_position(slots[i])})
