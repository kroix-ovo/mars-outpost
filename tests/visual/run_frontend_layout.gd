extends SceneTree
## Rendered walkthrough of the front end: title, settings, load game, customizer, crew lineup,
## landing intro and the hand-over to the colony's tutorial. Asserts that text and controls
## are on screen, readable (16 physical px or larger) and not overlapping, and saves PNGs.
## Needs a window:
##   Godot --path . --resolution 1280x720 --audio-driver Dummy --script tests/visual/run_frontend_layout.gd
##   Godot --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_frontend_layout.gd
## Output: docs/evidence/frontend/<window>/NN_*.png and FRONTEND_LAYOUT_PASS.

const FrontEnd := preload("res://scripts/frontend/front_end.gd")
const Session := preload("res://scripts/frontend/game_session.gd")
const LandingIntro := preload("res://scripts/frontend/landing_intro.gd")

const PROFILE := "user://test_frontend_profile.json"
const SETTINGS := "user://test_frontend_settings.cfg"
const NAME := "Nova Reyes"

var front: Node
var failures: Array[String] = []
var checks := 0
var directory := ""
var bounds: Rect2
var scale := 1.0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func frames(count: int = 4) -> void:
	for i in count:
		await process_frame


func capture(name: String) -> void:
	await frames(5)
	var path := directory + "/" + name + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, name + ": screenshot saved")
	print("FRONTEND_CAPTURE ", ProjectSettings.globalize_path(path))


func on_screen(control: Control, label: String) -> void:
	check(control.is_visible_in_tree(), label + " visible")
	check(bounds.grow(1).encloses(control.get_global_rect()), label + " inside the window")


func readable(control: Control, label: String) -> void:
	var size := control.get_theme_font_size("font_size")
	check(size * scale >= 15.9, "%s text %.1f px >= 16" % [label, size * scale])


func no_overlap(a: Control, b: Control, label: String) -> void:
	check(not a.get_global_rect().intersects(b.get_global_rect()), label + " do not overlap")


func _run() -> void:
	var window := DisplayServer.window_get_size()
	directory = "res://docs/evidence/frontend/%dx%d" % [window.x, window.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for path in [PROFILE, SETTINGS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Session.reset()
	front = FrontEnd.new()
	front.profile_path = PROFILE
	front.settings_path = SETTINGS
	front.change_scene_on_start = false
	root.add_child(front)
	await frames(8)
	bounds = root.get_visible_rect()
	scale = window.y / bounds.size.y
	# --- Title -----------------------------------------------------------------------------
	check(front.page == "title", "opens on the title")
	var title1: Label = front.title_page.find_child("TitleLine1", true, false)
	var title2: Label = front.title_page.find_child("TitleLine2", true, false)
	var subtitle: Label = front.title_page.find_child("Subtitle", true, false)
	check(title1.text == "MARS OUTPOST" and title2.text == "SURVIVAL", "title reads Mars Outpost Survival")
	check(title1.get_theme_font("font").resource_path.ends_with("RussoOne-Regular.ttf"), "title uses the bundled game display font")
	check(title1.get_theme_font("font").get_string_size(title1.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title1.get_theme_font_size("font_size")).x <= title1.size.x, "title lettering fits its column")
	check(subtitle.text == "A Junior Astronaut Mission Trainer", "subtitle")
	for node in [title1, title2, subtitle, front.new_game_button, front.load_button, front.settings_button, front.logo]:
		on_screen(node, "title: " + str(node.name))
	readable(front.title_page.find_child("Story", true, false), "story")
	readable(front.title_page.find_child("MusicCredit", true, false), "music credit")
	var logo: Rect2 = front.logo.get_global_rect()
	check(logo.position.x > bounds.size.x * 0.6 and logo.position.y < bounds.size.y * 0.25, "Space Apps logo sits in the top-right corner")
	for node in [title1, title2, subtitle, front.new_game_button]:
		no_overlap(front.logo, node, "logo and " + str(node.name))
	no_overlap(front.new_game_button, front.load_button, "New Game and Load Game")
	no_overlap(front.load_button, front.settings_button, "Load Game and Settings")
	no_overlap(front.title_page.find_child("ApproachStatus", true, false), front.title_page.find_child("MusicCredit", true, false), "status strip and credit")
	check(front.new_game_button.has_focus(), "New Game has keyboard focus")
	check(front.music.playing and front.music.stream is AudioStreamMP3 and front.music.stream.loop, "title music plays and loops")
	await capture("01_title")
	# --- Settings --------------------------------------------------------------------------
	front.settings_button.pressed.emit()
	await frames()
	check(front.page == "settings", "settings opens")
	on_screen(front.music_slider, "settings: volume slider")
	on_screen(front.fullscreen_toggle, "settings: full screen")
	on_screen(front.intro_toggle, "settings: intro toggle")
	front.music_slider.value = 0.45
	await frames()
	check(absf(Session.load_settings(SETTINGS).music_volume - 0.45) < 0.01, "music volume saved")
	check(absf(db_to_linear(front.music.volume_db) - 0.45) < 0.01, "music volume applied")
	await capture("02_settings")
	front.settings_page.find_child("Done", true, false).pressed.emit()
	await frames()
	check(front.page == "title", "settings closes back to the title")
	# --- Load --------------------------------------------------------------------------------
	front.load_button.pressed.emit()
	await frames()
	check(front.page == "load", "load opens")
	for id in ["LoadTraining", "LoadReference", "Back"]:
		on_screen(front.load_page.find_child(id, true, false), "load: " + id)
	await capture("03_load_game")
	front.load_page.find_child("Back", true, false).pressed.emit()
	await frames()
	# --- Customizer -------------------------------------------------------------------------
	front.new_game_button.pressed.emit()
	await frames(6)
	var custom: Control = front.customizer
	check(front.page == "customize" and custom.visible, "New Game opens the customizer")
	on_screen(custom.preview, "customizer: preview")
	on_screen(custom.continue_button, "customizer: continue")
	on_screen(custom.randomize_button, "customizer: surprise me")
	on_screen(custom.name_edit, "customizer: name")
	await capture("04_customizer_default")
	custom.name_edit.text = NAME
	custom.name_edit.text_changed.emit(NAME)
	for pick in [["skin", "umber"], ["hair_style", "braids"], ["hair_color", "blue"], ["glasses", "sunglasses"],
			["suit", "orange"], ["accent", "violet"], ["build", "broad"], ["height", "tall"]]:
		custom.choose(pick[0], pick[1])
	await frames()
	check(custom.figure.look.hair_style == "braids" and custom.figure.look.skin == "umber", "preview follows choices")
	var colour_title: Label = custom.find_child("hair_colorTitle", true, false)
	check(colour_title.text == "Eyebrows and facial hair colour", "colour control describes eyebrows and facial hair")
	on_screen(colour_title, "eyebrow colour label")
	no_overlap(colour_title, custom._value_labels.hair_color, "colour label and choice")
	check(custom.figure.has_node("Rig/Head/SunglassesLeft") and custom._value_labels.glasses.text == "Sunglasses", "sunglasses choice updates label and preview")
	await capture("05_customizer_custom")
	custom.randomize_look()
	await frames()
	check(custom.look.name == NAME, "Surprise me keeps the name")
	await capture("06_customizer_random")
	custom.set_look(custom.look.merged({"skin": "umber", "hair_style": "braids", "hair_color": "blue",
		"glasses": "sunglasses", "suit": "orange", "accent": "violet", "build": "broad", "height": "tall",
		"facial_hair": "none", "eye_color": "dark"}, true))
	custom.continue_button.pressed.emit()
	await frames(6)
	# --- Crew lineup ------------------------------------------------------------------------
	check(front.page == "crew", "customizer continues to the crew")
	check(Session.load_profile(PROFILE).look.name == NAME, "profile saved")
	var tags: Array = front._crew_names
	check(tags.size() == 7, "seven crew name tags")
	for i in tags.size():
		on_screen(tags[i], "crew tag %d" % i)
		readable(tags[i], "crew tag %d" % i)
		if i > 0: no_overlap(tags[i - 1], tags[i], "crew tags %d/%d" % [i - 1, i])
	check(tags[3].text.begins_with(NAME), "commander in the centre of the lineup")
	on_screen(front.begin_button, "crew: begin landing")
	await capture("07_meet_the_crew")
	# --- Intro ------------------------------------------------------------------------------
	front.begin_button.pressed.emit()
	await frames(4)
	check(front.page == "intro" and front.intro != null, "Begin landing plays the intro")
	var intro: Node3D = front.intro
	intro.manual_time = true
	var shots := [[2.5, "08_intro_descent"], [8.2, "09_intro_final_descent"], [11.0, "10_intro_touchdown"],
		[16.5, "11_intro_first_steps"], [22.0, "12_intro_first_outpost"], [27.0, "13_intro_survival"],
		[LandingIntro.DURATION + 0.5, "14_intro_training_first"]]
	var caption: PanelContainer = front._caption_panel
	for shot in shots:
		intro.seek(shot[0])
		await frames(3)
		on_screen(caption, shot[1] + " caption")
		readable(front._caption_text, shot[1] + " caption")
		check(front._caption_text.text == intro.captions[intro.caption_index].text, shot[1] + " shows the current caption")
		if shot[0] < LandingIntro.DURATION:
			on_screen(front.skip_button, shot[1] + " skip")
			no_overlap(front.skip_button, caption, shot[1] + " skip and caption")
		await capture(shot[1])
	check(intro.captions[3].text.contains(NAME), "intro names the commander")
	var begin: Button = caption.find_child("BeginTraining", true, false)
	on_screen(begin, "intro: begin training")
	check(not front.skip_button.visible, "skip hides once the intro ends")
	for figure in intro.figures:
		check(figure.visible, "every crew member is on the plain at the end")
	# --- Hand-over to the colony ------------------------------------------------------------
	begin.pressed.emit()
	await frames()
	check(Session.active and Session.world_index == 0 and Session.tutorial, "starts the training shift with the tutorial")
	check(Session.commander.name == NAME, "commander handed to the colony")
	front.queue_free()
	await frames(2)
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var hud: Control = main._hud
	hud._tour_refresh()
	await frames(3)
	check(str(hud._tour_step.get("id", "")) == "welcome", "tutorial welcome is waiting")
	check(str(hud._tour_step.get("title", "")) == "Welcome, Commander " + NAME, "tutorial greets the commander by name")
	check(main.lander.get_node_or_null("Commander") != null, "commander stands by the habitat")
	check("Inez Solis" in hud._crew.get_item_text(0) and "Amara Okafor" in hud._crew.get_item_text(1), "colony roster keeps the landing crew names")
	on_screen(hud._tour_primary, "colony: Start tutorial")
	await capture("15_colony_welcome")
	# The title music outlives the front end while it fades; stop it before quitting.
	for node in root.get_children():
		if node is AudioStreamPlayer:
			node.stop()
			node.stream = null
			node.queue_free()
	await frames(3)
	Session.reset()
	for path in [PROFILE, SETTINGS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for failure in failures:
		print("FRONTEND_LAYOUT_FAIL ", failure)
	print("FRONTEND_LAYOUT_RESULT checks=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("FRONTEND_LAYOUT_PASS")
	quit(0 if failures.is_empty() else 1)
