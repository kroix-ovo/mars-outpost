extends SceneTree
## Rendered layout checks and fresh screenshots for the guided missions.
var main: Node
var hud: Control
var frame := 0
var stage := 0
var failures: Array[String] = []

func _initialize() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 12: return false
	frame = 0
	hud = main._hud
	var bounds := root.get_visible_rect()
	for panel in [hud._top, hud._crew_card, hud._drawer]:
		if not bounds.encloses(panel.get_global_rect()): failures.append("panel outside viewport: " + panel.name)
	if hud._alerts.get_global_rect().end.x > bounds.end.x - 8:
		failures.append("status strip contents overflow")
	var scale: float = DisplayServer.window_get_size().y / bounds.size.y
	if hud._tutorial_text.get_theme_font_size("font_size") * scale < 15.9:
		failures.append("guide text below 16 physical pixels")
	var window := DisplayServer.window_get_size()
	var directory := "res://docs/evidence/first_shift/%dx%d" % [window.x, window.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var names := ["01_training_guide", "02_training_eva", "03_reference_guide"]
	var path: String = directory + "/" + names[stage] + ".png"
	if root.get_texture().get_image().save_png(path) != OK: failures.append("could not save screenshot")
	print("FIRST_SHIFT_CAPTURE ", path)
	match stage:
		0:
			hud._crew.select(0, false)
			hud._crew.select(1, false)
			hud._refresh_selection()
			hud._mission_next()
		1:
			main.load_world(1)
		2:
			for failure in failures: print("FIRST_SHIFT_LAYOUT_FAIL ", failure)
			if failures.is_empty(): print("FIRST_SHIFT_LAYOUT_PASS")
			quit(0 if failures.is_empty() else 1)
	stage += 1
	return false
