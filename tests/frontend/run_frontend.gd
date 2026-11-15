extends SceneTree
## Headless checks for the title screen, astronaut looks, crew designs, landing intro and the
## hand-over to the colony. Runs under --headless; the rendered walkthrough is
## tests/visual/run_frontend_layout.gd.
##   Godot --headless --path . --script tests/frontend/run_frontend.gd
## Output: FRONTEND_PASS checks=N

const Look := preload("res://scripts/crew/astronaut_look.gd")
const Figure := preload("res://scripts/crew/astronaut_figure.gd")
const CrewLooks := preload("res://scripts/crew/crew_looks.gd")
const Session := preload("res://scripts/frontend/game_session.gd")
const FrontEnd := preload("res://scripts/frontend/front_end.gd")
const LandingIntro := preload("res://scripts/frontend/landing_intro.gd")

const PROFILE := "user://test_headless_profile.json"
const SETTINGS := "user://test_headless_settings.cfg"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func frames(count: int = 3) -> void:
	for i in count:
		await process_frame


func _cleanup() -> void:
	for path in [PROFILE, SETTINGS]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	_cleanup()
	Session.reset()
	_looks()
	_crew_designs()
	_storage()
	await _figures()
	await _intro()
	await _front_end()
	await _colony_from_session()
	# The title music outlives the front end while it fades; stop it before quitting.
	for node in root.get_children():
		if node is AudioStreamPlayer:
			node.stop()
			node.stream = null
			node.queue_free()
	await frames(3)
	Session.reset()
	_cleanup()
	for failure in failures:
		print("FRONTEND_FAIL ", failure)
	if failures.is_empty():
		print("FRONTEND_PASS checks=", checks)
	else:
		print("FRONTEND_FAILED failures=", failures.size(), " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _looks() -> void:
	var base := Look.default_look()
	check(Look.sanitize(base) == base, "default look is already valid")
	var broken := Look.sanitize({"skin": "plaid", "hair_style": 7, "name": "  \tAda\n  Lovelace   "})
	check(broken.skin == Look.SKIN_TONES[0].id, "unknown option falls back")
	check(broken.hair_style == Look.HAIR_STYLES[0].id, "non-string option falls back")
	check(broken.name == "Ada Lovelace", "names drop control characters and extra spaces")
	check(Look.sanitize({"name": "   "}).name == base.name, "blank names fall back")
	check(Look.clean_name("x".repeat(60)).length() == Look.MAX_NAME_LENGTH, "names are capped")
	check(Look.sanitize("not a look") == base, "non-dictionary looks fall back")
	check(Look.SKIN_TONES.size() >= 10 and Look.HAIR_STYLES.size() >= 12, "wide range of skin tones and hair styles")
	var ids := {}
	for entry in Look.HAIR_STYLES: ids[entry.id] = true
	for style in ["afro", "braids", "headscarf", "bald", "curly", "long"]:
		check(ids.has(style), "hair style offered: " + style)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var look := Look.random_look(rng)
		check(Look.sanitize(look).hash() == look.hash(), "random look %d is valid" % i)


func _crew_designs() -> void:
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/crew/outpost_roster.json"))
	var seen := {}
	var skins := {}
	var styles := {}
	for definition in roster.definitions:
		var id: String = definition.id
		check(CrewLooks.has_design(id), "designed look for " + definition.display_name)
		var look := CrewLooks.look_for(id)
		check(look.name == definition.display_name, "design name matches the roster: " + definition.display_name)
		check(CrewLooks.ROSTER[id].role == definition.primary_skill, "design role matches the primary skill: " + definition.display_name)
		var key := "%s|%s|%s|%s" % [look.skin, look.hair_style, look.hair_color, look.suit]
		check(not seen.has(key), "distinct look for " + definition.display_name)
		seen[key] = true
		skins[look.skin] = true
		styles[look.hair_style] = true
	check(skins.size() >= 7, "the crew spans at least seven skin tones (%d)" % skins.size())
	check(styles.size() >= 8, "the crew spans at least eight hair styles (%d)" % styles.size())
	for id in CrewLooks.LANDING_CREW:
		check(CrewLooks.ROSTER.has(id), "landing crew member is designed: " + id)
	var fallback := {}
	for letter in "abcdefghi":
		var look := CrewLooks.look_for("fixture_crew_" + letter, "Fixture Crew " + letter.to_upper())
		fallback["%s|%s" % [look.skin, look.hair_style]] = true
		var named_id := "outpost_crew_%02d" % (letter.unicode_at(0) - 96)
		check(look == CrewLooks.look_for(named_id), "training astronaut keeps the landing crew identity and appearance")
		check(CrewLooks.display_name("Fixture Crew " + letter.to_upper()) == look.name, "training HUD uses the landing crew name")
	check(fallback.size() == 9, "nine fixture crew get nine different looks")
	check(CrewLooks.display_name("Kai Moana") == "Kai Moana", "custom crew names remain intact")


func _storage() -> void:
	var missing := Session.load_profile(PROFILE)
	check(not missing.exists and missing.look == Look.default_look(), "missing profile falls back")
	var look := Look.default_look()
	look.name = "Kai Moana"
	look.hair_style = "afro"
	look.glasses = "sunglasses"
	check(Session.save_profile(look, PROFILE), "profile saves")
	var loaded := Session.load_profile(PROFILE)
	check(loaded.exists and loaded.look == Look.sanitize(look), "profile round-trips")
	var file := FileAccess.open(PROFILE, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	check(not Session.load_profile(PROFILE).exists, "corrupt profile is ignored")
	var defaults := Session.load_settings(SETTINGS)
	check(defaults == Session.DEFAULT_SETTINGS, "default settings")
	check(Session.save_settings({"music_volume": 3.0, "fullscreen": true, "play_intro": false}, SETTINGS), "settings save")
	var stored := Session.load_settings(SETTINGS)
	check(stored.music_volume == 1.0 and stored.fullscreen and not stored.play_intro, "settings round-trip and clamp")
	check(Session.volume_db(0.0) <= -79.0 and absf(Session.volume_db(1.0)) < 0.01, "volume mapping")
	_cleanup()


func _figures() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var heights := {}
	for height in Look.HEIGHTS:
		for style in Look.HAIR_STYLES:
			var figure := Figure.new()
			figure.manual_time = true
			holder.add_child(figure)
			var look := Look.default_look()
			look.height = height.id
			look.hair_style = style.id
			look.facial_hair = "beard"
			look.glasses = "square"
			figure.apply_look(look)
			for mode in ["idle", "walk", "wave", "cheer"]:
				figure.mode = mode
				figure.pose(1.3)
			heights[height.id] = figure.figure_height()
			check(figure.get_node("Rig/Head/Helmet") != null, "helmet built for %s/%s" % [height.id, style.id])
	check(heights.short < heights.average and heights.average < heights.tall, "height option changes the figure")
	check(heights.average > 1.2 and heights.average < 1.7, "figure is human scale (%.2f m)" % heights.average)
	var walker := Figure.new()
	walker.manual_time = true
	holder.add_child(walker)
	var shaded := Look.default_look()
	shaded.glasses = "sunglasses"
	walker.apply_look(shaded)
	check(walker.has_node("Rig/Head/SunglassesLeft") and walker.has_node("Rig/Head/SunglassesRight"), "sunglasses render two opaque lenses")
	walker.apply_look(Look.default_look())
	check(not walker.has_node("Rig/Head/SunglassesLeft"), "switching glasses removes the sunglasses")
	walker.mode = "walk"
	walker.pose(0.1)
	var hip_a: float = walker.get_node("Rig").get_child(0).rotation.x
	walker.pose(0.35)
	check(not is_equal_approx(hip_a, walker.get_node("Rig").get_child(0).rotation.x), "walking swings the legs")
	holder.queue_free()
	await frames()


func _intro() -> void:
	var look := Look.default_look()
	look.name = "Kai Moana"
	var intro := LandingIntro.new()
	intro.manual_time = true
	intro.setup(look)
	root.add_child(intro)
	await frames()
	check(intro.captions.size() == 7, "seven intro captions")
	var last := -1.0
	for caption in intro.captions:
		check(float(caption.at) > last, "captions in time order: " + caption.title)
		last = float(caption.at)
	check(intro.captions[3].text.contains("Kai Moana"), "intro names the commander")
	check(intro.captions[4].text.contains("first human outpost on Mars"), "intro says they are the first outpost")
	check(intro.captions[-1].text.contains("training"), "intro leads into the training mission")
	intro.seek(0.0)
	check(intro.lander.position.y > 20.0 and intro.get_node("Lander/Plume").visible, "lander starts high with engines burning")
	for figure in intro.figures:
		check(not figure.visible, "crew stay aboard during descent")
	intro.seek(LandingIntro.DESCENT_S + 0.5)
	check(is_zero_approx(intro.lander.position.y) and not intro.get_node("Lander/Plume").visible, "lander settles and shuts down")
	intro.seek(LandingIntro.DURATION)
	check(intro.finished(), "intro reports finished")
	var spots := {}
	for i in intro.figures.size():
		var figure: Node3D = intro.figures[i]
		check(figure.visible, "crew member %d is out" % i)
		spots[str(figure.position.snapped(Vector3.ONE * 0.1))] = true
		check(figure.get_node("Name").modulate.a > 0.99, "crew member %d name tag shown" % i)
	check(spots.size() == 7, "seven crew stand in seven places")
	check(intro.figures[0].look.name == "Kai Moana", "the commander walks out first")
	intro.queue_free()
	await frames()


func _front_end() -> void:
	var front := FrontEnd.new()
	front.profile_path = PROFILE
	front.settings_path = SETTINGS
	front.change_scene_on_start = false
	root.add_child(front)
	await frames(4)
	check(front.page == "title", "front end opens on the title")
	check(front.music != null and front.music.stream != null and not front.music.playing, "title music is ready (silent in headless runs)")
	check(front.music.stream is AudioStreamMP3 and front.music.stream.loop, "title music loops")
	check(front.logo.texture != null, "Space Apps logo loads")
	check(not front.has_profile, "fresh start has no profile")
	front.load_button.pressed.emit()
	await frames()
	check(front.page == "load", "Load Game opens")
	check(front.load_page.find_child("NoSaves", true, false) != null, "no saves explained")
	front._unhandled_input(_key(KEY_ESCAPE))
	check(front.page == "title", "Escape closes Load Game")
	front.new_game_button.pressed.emit()
	await frames()
	check(front.page == "customize", "New Game opens the customizer")
	var custom: Control = front.customizer
	custom.name_edit.text = ""
	custom.name_edit.text_changed.emit("")
	check(custom.continue_button.disabled, "a name is required")
	custom.name_edit.text = "Kai Moana"
	custom.name_edit.text_changed.emit("Kai Moana")
	custom.step("hair_style", 1)
	check(custom.look.hair_style == Look.HAIR_STYLES[1].id, "stepping changes the hair style")
	custom.step("hair_style", -2)
	check(custom.look.hair_style == Look.HAIR_STYLES[-1].id, "stepping wraps around")
	custom.choose("skin", "ebony")
	check(custom.figure.look.skin == "ebony", "preview follows the skin choice")
	custom.continue_button.pressed.emit()
	await frames()
	check(front.page == "crew", "customizer continues to the crew")
	check(Session.load_profile(PROFILE).look.skin == "ebony", "profile saved on continue")
	check(front._crew_figures[3].look.name == "Kai Moana", "commander stands in the centre of the lineup")
	front.settings.play_intro = false
	front.begin_button.pressed.emit()
	await frames()
	check(front.started == {"world": 0, "tutorial": true, "load_save": false}, "intro off: Begin landing goes straight to training")
	check(Session.active and Session.commander.name == "Kai Moana", "commander handed over")
	check(front.music == null, "music hands off to fade out")
	front.queue_free()
	await frames()
	Session.reset()
	_cleanup()


func _colony_from_session() -> void:
	var look := Look.default_look()
	look.name = "Kai Moana"
	Session.begin(look, 1, false)
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(6)
	check(main.world_index == 1, "Load Game's reference colony opens world 1")
	check(main._hud._tour.active == false, "free play keeps the tutorial off")
	check(main.lander.get_node_or_null("Commander") != null, "commander stands by the habitat")
	main.queue_free()
	await frames()
	Session.begin(look, 0, true)
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(6)
	main._hud._tour_refresh()
	check(str(main._hud._tour_step.get("title", "")) == "Welcome, Commander Kai Moana", "tutorial greets the commander")
	main.queue_free()
	await frames()
	Session.reset()
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(6)
	main._hud._tour_refresh()
	check(str(main._hud._tour_step.get("title", "")) == "Welcome, commander", "opened directly, the colony keeps its plain greeting")
	check(main.lander.get_node_or_null("Commander") == null, "opened directly, no commander figure")
	main.queue_free()
	await frames()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event
