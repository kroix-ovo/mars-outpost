extends SceneTree
## Renders every designed crew look side by side (front and three-quarter), then a gallery of
## every hair style across the skin-tone range, for review.
##   Godot --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_crew_lineup.gd
## Output: docs/evidence/frontend/crew_lineup.png, customization_range.png and CREW_LINEUP_PASS.

const Figure := preload("res://scripts/crew/astronaut_figure.gd")
const CrewLooks := preload("res://scripts/crew/crew_looks.gd")
const Look := preload("res://scripts/crew/astronaut_look.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#2a1d1a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.68, 0.72)
	env.environment.ambient_light_energy = 0.6
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	var ids: Array = CrewLooks.ROSTER.keys()
	ids.sort()
	var count := ids.size()
	for row in 2:
		for i in count:
			var figure := Figure.new()
			figure.manual_time = true
			stage.add_child(figure)
			figure.apply_look(CrewLooks.look_for(ids[i]))
			figure.position = Vector3((i - (count - 1) * 0.5) * 0.75, 1.6 - row * 1.75, 0)
			figure.rotation.y = 0.0 if row == 0 else -0.7
			figure.mode = "idle" if row == 0 else ("wave" if i % 2 == 0 else "walk")
			figure.pose(0.3 + i * 0.4)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(0, 1.3, 6)
	stage.add_child(camera)
	camera.current = true
	for i in 6:
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/frontend"))
	var ok := root.get_texture().get_image().save_png("res://docs/evidence/frontend/crew_lineup.png") == OK
	# Every hair style once, cycling skin tones, hair colours, suits, builds and extras.
	for child in stage.get_children():
		if child is Node3D and child.has_method("apply_look"): child.free()
	var styles: Array = Look.HAIR_STYLES
	for i in styles.size():
		var figure := Figure.new()
		figure.manual_time = true
		stage.add_child(figure)
		var look := Look.default_look()
		look.hair_style = styles[i].id
		look.skin = Look.SKIN_TONES[(i * 7) % Look.SKIN_TONES.size()].id
		look.hair_color = Look.HAIR_COLORS[(i * 5) % Look.HAIR_COLORS.size()].id
		look.eye_color = Look.EYE_COLORS[i % Look.EYE_COLORS.size()].id
		look.suit = Look.SUIT_COLORS[i % Look.SUIT_COLORS.size()].id
		look.accent = Look.ACCENT_COLORS[i % Look.ACCENT_COLORS.size()].id
		look.build = Look.BUILDS[i % 3].id
		look.height = Look.HEIGHTS[(i + 1) % 3].id
		look.facial_hair = Look.FACIAL_HAIR[i % 4].id if i % 3 == 0 else "none"
		look.glasses = Look.GLASSES[i % 3].id if i % 2 == 1 else "none"
		figure.apply_look(look)
		figure.position = Vector3(((i % 6) - 2.5) * 1.15, 1.6 - (i / 6) * 1.75, 0)
		figure.rotation.y = 0.35 if i % 2 == 0 else -0.35
		figure.pose(0.5 + i * 0.3)
	for i in 6:
		await process_frame
	ok = ok and root.get_texture().get_image().save_png("res://docs/evidence/frontend/customization_range.png") == OK
	print("CREW_LINEUP_PASS" if ok else "CREW_LINEUP_FAIL")
	quit(0 if ok else 1)
