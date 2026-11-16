extends Node
## I keep the title, crew setup and mission handoff together here. The normal menu path should reach the same playable camp that I check in the submission tests.

signal page_changed(page: String)

const UI := preload("res://scripts/frontend/frontend_theme.gd")
const Session := preload("res://scripts/frontend/game_session.gd")
const Look := preload("res://scripts/crew/astronaut_look.gd")
const CrewLooks := preload("res://scripts/crew/crew_looks.gd")
const Figure := preload("res://scripts/crew/astronaut_figure.gd")
const TitleStage := preload("res://scripts/frontend/title_stage.gd")
const LandingIntro := preload("res://scripts/frontend/landing_intro.gd")
const Customizer := preload("res://scripts/frontend/astronaut_customizer.gd")

const MUSIC_PATH := "res://assets/audio/music/mondamusic-space-589110.mp3"
const LOGO_PATH := "res://assets/branding/space_apps_challenge.png"
const COLONY_SCENE := "res://scenes/world/main.tscn"
const QUICK_SAVE := "user://outpost_quick_save.json"

## Tests set these before adding the node so nothing touches the real user:// files or scene.
var profile_path := Session.PROFILE_PATH
var settings_path := Session.SETTINGS_PATH
var change_scene_on_start := true

var page := ""
var settings: Dictionary = {}
var look: Dictionary = {}
var has_profile := false
var started := {}

var music: AudioStreamPlayer
var title_stage: Node3D
var intro: Node3D
var ui: CanvasLayer
var title_page: Control
var settings_page: Control
var load_page: Control
var crew_page: Control
var intro_page: Control
var customizer: Control
var new_game_button: Button
var load_button: Button
var settings_button: Button
var quit_button: Button
var begin_button: Button
var skip_button: Button
var logo: TextureRect
var music_slider: HSlider
var fullscreen_toggle: CheckButton
var intro_toggle: CheckButton
var _volume_label: Label
var _countdown: Label
var _caption_title: Label
var _caption_text: Label
var _caption_panel: PanelContainer
var _crew_view: SubViewportContainer
var _crew_figures: Array = []
var _crew_names: Array = []
var _clock := 0.0


func _ready() -> void:
	settings = Session.load_settings(settings_path)
	var stored := Session.load_profile(profile_path)
	look = stored.look
	has_profile = stored.exists
	Session.apply_display(settings)
	title_stage = TitleStage.new()
	title_stage.name = "TitleStage"
	add_child(title_stage)
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	_build_music()
	_build_title()
	_build_settings()
	_build_load()
	_build_crew_page()
	_build_intro_page()
	show_page("title")


# --- Flow -------------------------------------------------------------------------------------

func show_page(name: String) -> void:
	page = name
	title_page.visible = name in ["title", "settings", "load"]
	_set_title_menu_enabled(name == "title")
	settings_page.visible = name == "settings"
	load_page.visible = name == "load"
	crew_page.visible = name == "crew"
	intro_page.visible = name == "intro"
	if customizer != null:
		customizer.visible = name == "customize"
	if name == "intro" and title_stage != null:
		# The intro has its own sky; the space backdrop (and its starfield) must go.
		title_stage.queue_free()
		title_stage = null
	match name:
		"title": _focus.call_deferred(new_game_button)
		"settings": _focus.call_deferred(music_slider)
		"crew": _focus.call_deferred(begin_button)
	page_changed.emit(name)


func open_new_game() -> void:
	if customizer == null:
		customizer = Customizer.new()
		customizer.name = "Customizer"
		ui.add_child(customizer)
		customizer.finished.connect(_on_customized)
		customizer.cancelled.connect(func(): show_page("title"))
	customizer.set_look(look)
	show_page("customize")


func _on_customized(new_look: Dictionary) -> void:
	look = Look.sanitize(new_look)
	has_profile = Session.save_profile(look, profile_path) or has_profile
	_refresh_crew_page()
	show_page("crew")


func begin_landing() -> void:
	if settings.get("play_intro", true):
		play_intro()
	else:
		start_game(1, false)


func play_intro() -> void:
	if intro != null:
		intro.queue_free()
	intro = LandingIntro.new()
	intro.name = "LandingIntro"
	intro.setup(look)
	intro.caption_changed.connect(_on_caption)
	add_child(intro)
	move_child(intro, 0)
	show_page("intro")
	_on_caption(intro.caption_index)


func start_game(world_index: int, with_tutorial: bool, load_save: bool = false) -> void:
	## Hands the commander and choice of colony to the colony scene, then loads it.
	Session.begin(look, world_index, with_tutorial)
	Session.load_save_on_start = load_save
	started = {"world": world_index, "tutorial": with_tutorial, "load_save": load_save}
	_fade_out_music()
	if change_scene_on_start:
		get_tree().change_scene_to_file(COLONY_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		match page:
			"settings", "load": _close_overlay()
			"crew": open_new_game()
			"intro": start_game(1, false)
			"customize": show_page("title")
		get_viewport().set_input_as_handled()


# --- Music ------------------------------------------------------------------------------------

func _build_music() -> void:
	music = AudioStreamPlayer.new()
	music.name = "TitleMusic"
	var stream: AudioStream = load(MUSIC_PATH)
	if stream is AudioStreamMP3:
		stream.loop = true # Endless: the track restarts seamlessly when it ends.
	music.stream = stream
	music.volume_db = Session.volume_db(settings.music_volume)
	add_child(music)
	# Headless runs (CI, checks) have no one listening, and the dummy mixer never retires a
	# playback that is still open at exit; the HUD skips its sounds there for the same reason.
	if DisplayServer.get_name() != "headless":
		music.play()


func _exit_tree() -> void:
	# Release the stream when the game quits from the title so the engine shuts down cleanly.
	if music != null:
		music.stop()
		music.stream = null


func _fade_out_music() -> void:
	if music == null:
		return
	if not music.playing:
		music.queue_free()
		music = null
		return
	# Survive the scene change so the track fades under the colony instead of cutting off.
	var player := music
	music = null
	player.reparent(get_tree().root)
	var tween := player.create_tween()
	tween.tween_property(player, "volume_db", -60.0, 3.0)
	tween.tween_callback(player.queue_free)


func quit_game() -> void:
	# Stop the music a frame before quitting so the audio server releases the stream.
	if music != null:
		music.stop()
		music.stream = null
	await get_tree().process_frame
	get_tree().quit()


func set_music_volume(linear: float) -> void:
	settings.music_volume = clampf(linear, 0.0, 1.0)
	if music != null:
		music.volume_db = Session.volume_db(settings.music_volume)
	if _volume_label != null:
		_volume_label.text = "%d%%" % roundi(settings.music_volume * 100.0)
	Session.save_settings(settings, settings_path)


# --- Title ------------------------------------------------------------------------------------

func _build_title() -> void:
	title_page = Control.new()
	title_page.name = "Title"
	title_page.theme = UI.build()
	title_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title_page)
	# A soft dark wash behind the text column keeps it readable over the stars.
	var wash := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.02, 0.78))
	gradient.set_color(1, Color(0.0, 0.0, 0.02, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	wash.texture = texture
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.anchor_bottom = 1.0
	wash.anchor_right = 0.62
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_page.add_child(wash)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.anchor_bottom = 1.0
	column.offset_left = 64
	column.offset_right = 64 + 560
	column.offset_top = 28
	column.offset_bottom = -58
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	title_page.add_child(column)
	var title_block := VBoxContainer.new()
	title_block.add_theme_constant_override("separation", -8)
	column.add_child(title_block)
	var line_one := UI.heading("MARS OUTPOST", 64)
	line_one.name = "TitleLine1"
	line_one.add_theme_font_override("font", preload("res://assets/fonts/russo_one/RussoOne-Regular.ttf"))
	line_one.add_theme_font_size_override("font_size", 60)
	title_block.add_child(line_one)
	var line_two := UI.heading("SURVIVAL", 64)
	line_two.name = "TitleLine2"
	line_two.add_theme_font_override("font", preload("res://assets/fonts/russo_one/RussoOne-Regular.ttf"))
	line_two.add_theme_color_override("font_color", UI.AMBER)
	title_block.add_child(line_two)
	var subtitle := UI.label("A Junior Astronaut Mission Trainer", 26, Color("#f4e9d8"))
	subtitle.name = "Subtitle"
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	column.add_child(gap)
	var story := UI.label("Your lander is on final approach to Mars. After seven months in deep space, you and six crewmates are about to touch down and build the first human outpost there.", 18, UI.INK)
	story.name = "Story"
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size.x = 500
	column.add_child(story)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 8
	column.add_child(gap2)
	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.add_theme_constant_override("separation", 10)
	menu.custom_minimum_size.x = 320
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(menu)
	new_game_button = _menu_button(menu, "New Game", open_new_game)
	UI.primary(new_game_button, 24)
	load_button = _menu_button(menu, "Load Game", func(): _open_overlay("load"))
	settings_button = _menu_button(menu, "Settings", func(): _open_overlay("settings"))
	quit_button = _menu_button(menu, "Quit", quit_game)
	# Status strip: the ship's approach, with a countdown to touchdown.
	_countdown = UI.label("", 16, Color("#9fd6e8"))
	_countdown.name = "ApproachStatus"
	_countdown.anchor_top = 1.0
	_countdown.anchor_bottom = 1.0
	_countdown.offset_left = 64
	_countdown.offset_top = -46
	_countdown.offset_bottom = -20
	_countdown.anchor_right = 0.62
	_countdown.offset_right = 0
	_countdown.clip_text = true
	title_page.add_child(_countdown)
	logo = TextureRect.new()
	logo.name = "SpaceAppsLogo"
	# The supplied PNG has excess blue padding on the right. Center the complete
	# official mark and wordmark by excluding that padding, without redrawing it.
	var badge := AtlasTexture.new()
	badge.atlas = load(LOGO_PATH)
	badge.region = Rect2(0, 0, 370, 226)
	logo.texture = badge
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left = 1.0
	logo.anchor_right = 1.0
	logo.offset_left = -24 - 210
	logo.offset_right = -24
	logo.offset_top = 22
	logo.offset_bottom = 22 + 110
	logo.tooltip_text = "Made for the NASA Space Apps Challenge"
	title_page.add_child(logo)
	var credit := UI.label("Music: “Space” by mondamusic (Pixabay)", 16, Color(1, 1, 1, 0.6))
	credit.name = "MusicCredit"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.anchor_left = 1.0
	credit.anchor_right = 1.0
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = -440
	credit.offset_right = -24
	credit.offset_top = -46
	credit.offset_bottom = -20
	title_page.add_child(credit)


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.name = text.replace(" ", "")
	button.custom_minimum_size = Vector2(320, 48)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _focus(control: Control) -> void:
	## Deferred focus for keyboard players; skipped if the page changed in the meantime.
	if is_instance_valid(control) and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus()


func _set_title_menu_enabled(enabled: bool) -> void:
	for button in [new_game_button, load_button, settings_button, quit_button]:
		if button != null:
			button.disabled = not enabled
			button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


func _process(delta: float) -> void:
	_clock += delta
	if _countdown != null and title_page.visible:
		var remaining := maxi(0, 47 * 60 + 12 - int(_clock))
		_countdown.text = "●  ON APPROACH  ·  Mars orbit  ·  Landing site: northern plains  ·  Touchdown in %02d:%02d" % [remaining / 60, remaining % 60]
	if page == "intro" and intro != null:
		begin_button_visible(intro.finished())
	for figure in _crew_figures:
		if is_instance_valid(figure):
			figure.rotation.y = lerp_angle(figure.rotation.y, 0.0, 0.1)


# --- Overlays: settings and load --------------------------------------------------------------

func _overlay_shell(name: String, heading: String) -> Array:
	var shade := ColorRect.new()
	shade.name = name
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.theme = UI.build()
	ui.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size.x = 560
	center.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)
	stack.add_child(UI.heading(heading, 30))
	return [shade, stack]


func _open_overlay(name: String) -> void:
	if name == "load":
		_refresh_load()
	show_page(name)


func _close_overlay() -> void:
	show_page("title")


func _build_settings() -> void:
	var parts := _overlay_shell("Settings", "Settings")
	settings_page = parts[0]
	var stack: VBoxContainer = parts[1]
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 14)
	var volume_title := UI.label("Music volume", 18)
	volume_title.custom_minimum_size.x = 170
	volume_row.add_child(volume_title)
	music_slider = HSlider.new()
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.value = settings.music_volume
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_slider.custom_minimum_size.y = 28
	music_slider.value_changed.connect(set_music_volume)
	volume_row.add_child(music_slider)
	_volume_label = UI.label("%d%%" % roundi(settings.music_volume * 100.0), 18)
	_volume_label.custom_minimum_size.x = 56
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_label)
	stack.add_child(volume_row)
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "Full screen"
	fullscreen_toggle.button_pressed = settings.fullscreen
	fullscreen_toggle.toggled.connect(func(on: bool):
		settings.fullscreen = on
		Session.apply_display(settings)
		Session.save_settings(settings, settings_path))
	stack.add_child(fullscreen_toggle)
	intro_toggle = CheckButton.new()
	intro_toggle.text = "Play the landing intro when starting a new game"
	intro_toggle.button_pressed = settings.play_intro
	intro_toggle.toggled.connect(func(on: bool):
		settings.play_intro = on
		Session.save_settings(settings, settings_path))
	stack.add_child(intro_toggle)
	stack.add_child(UI.label("Settings save automatically.", 16, UI.DIM))
	var done := Button.new()
	done.text = "Done"
	done.name = "Done"
	UI.primary(done, 20)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(_close_overlay)
	stack.add_child(done)


var _load_list: VBoxContainer

func _build_load() -> void:
	var parts := _overlay_shell("LoadGame", "Load game")
	load_page = parts[0]
	_load_list = parts[1]


func _refresh_load() -> void:
	while _load_list.get_child_count() > 1:
		var child := _load_list.get_child(1)
		_load_list.remove_child(child)
		child.queue_free()
	_load_list.add_child(UI.label("SAVED COLONIES", 16, UI.AMBER))
	if FileAccess.file_exists(QUICK_SAVE):
		var resume := Button.new()
		resume.text = "Continue your last saved colony"
		resume.name = "LoadQuickSave"
		resume.pressed.connect(func(): start_game(0, false, true))
		_load_list.add_child(resume)
	else:
		var none := UI.label("No saved colonies yet. Saving a colony becomes available once the outpost's save system is finished.", 17, UI.DIM)
		none.name = "NoSaves"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = 500
		_load_list.add_child(none)
	_load_list.add_child(UI.label("START A MISSION", 16, UI.AMBER))
	var who := UI.label(("Playing as Commander %s." % look.name) if has_profile else "You will play as the default commander. Choose New Game to design your own astronaut.", 17, UI.INK)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.custom_minimum_size.x = 500
	_load_list.add_child(who)
	var training := Button.new()
	training.name = "LoadTraining"
	training.text = "Legacy training shift  ·  synthetic tutorial"
	training.pressed.connect(func(): start_game(0, true))
	_load_list.add_child(training)
	var reference := Button.new()
	reference.name = "LoadReference"
	reference.text = "Camp mission  ·  build the farm, handle a fault, reach Level 1"
	reference.pressed.connect(func(): start_game(1, false))
	_load_list.add_child(reference)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(_close_overlay)
	_load_list.add_child(back)
	_focus.call_deferred(training)


# --- Crew lineup ------------------------------------------------------------------------------

func _build_crew_page() -> void:
	crew_page = Control.new()
	crew_page.name = "Crew"
	crew_page.theme = UI.build()
	crew_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(crew_page)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.05, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crew_page.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	crew_page.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	stack.add_child(UI.heading("Meet your crew", 34))
	var blurb := UI.label("Six specialists land with you: engineers build and repair, botanists grow food, a geologist reads the ground, a medic keeps everyone healthy and a pilot flies the lander. You give the orders.", 18, UI.DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(blurb)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	_crew_view = SubViewportContainer.new()
	_crew_view.stretch = true
	_crew_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_crew_view)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	_crew_view.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#2a1b16")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.68, 0.72)
	env.environment.ambient_light_energy = 0.65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-35, 30, 0)
	viewport.add_child(key)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 7.0
	camera.position = Vector3(0, 0.8, 6)
	viewport.add_child(camera)
	for i in 7:
		var figure := Figure.new()
		figure.name = "Lineup%d" % i
		figure.phase = i * 0.9
		figure.position = Vector3((i - 3) * 1.0, 0.0, 0.0)
		viewport.add_child(figure)
		_crew_figures.append(figure)
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	inner.add_child(names)
	for i in 7:
		var tag := UI.label("", 17, UI.INK)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag.custom_minimum_size.x = 60
		names.add_child(tag)
		_crew_names.append(tag)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	stack.add_child(footer)
	var back := Button.new()
	back.text = "Back to my astronaut"
	back.pressed.connect(open_new_game)
	footer.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	begin_button = Button.new()
	begin_button.name = "BeginLanding"
	begin_button.text = "Begin landing  ›"
	UI.primary(begin_button)
	begin_button.pressed.connect(begin_landing)
	footer.add_child(begin_button)


func crew_lineup() -> Array:
	## Lineup order, left to right: three crew, the commander in the centre, three crew.
	var ids: Array = CrewLooks.LANDING_CREW
	return [ids[0], ids[1], ids[2], "commander", ids[3], ids[4], ids[5]]


func _refresh_crew_page() -> void:
	var order := crew_lineup()
	for i in order.size():
		var id: String = order[i]
		var figure: Node3D = _crew_figures[i]
		if id == "commander":
			figure.apply_look(look)
			figure.mode = "wave"
			_crew_names[i].text = "%s\nCommander (you)" % look.name
			_crew_names[i].add_theme_color_override("font_color", UI.AMBER)
		else:
			figure.apply_look(CrewLooks.look_for(id))
			figure.mode = "idle"
			_crew_names[i].text = "%s\n%s" % [CrewLooks.ROSTER[id].name, CrewLooks.role_label(id)]
			_crew_names[i].add_theme_color_override("font_color", UI.INK)


# --- Intro ------------------------------------------------------------------------------------

func _build_intro_page() -> void:
	intro_page = Control.new()
	intro_page.name = "Intro"
	intro_page.theme = UI.build()
	intro_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(intro_page)
	skip_button = Button.new()
	skip_button.name = "SkipIntro"
	skip_button.text = "Skip intro  ›"
	skip_button.anchor_left = 1.0
	skip_button.anchor_right = 1.0
	skip_button.offset_left = -190
	skip_button.offset_right = -24
	skip_button.offset_top = 22
	skip_button.offset_bottom = 70
	skip_button.pressed.connect(func(): start_game(1, false))
	intro_page.add_child(skip_button)
	_caption_panel = PanelContainer.new()
	_caption_panel.name = "Caption"
	_caption_panel.anchor_left = 0.5
	_caption_panel.anchor_right = 0.5
	_caption_panel.anchor_top = 1.0
	_caption_panel.anchor_bottom = 1.0
	_caption_panel.offset_left = -400
	_caption_panel.offset_right = 400
	_caption_panel.offset_bottom = -28
	_caption_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	intro_page.add_child(_caption_panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	_caption_panel.add_child(stack)
	_caption_title = UI.label("", 17, UI.AMBER)
	stack.add_child(_caption_title)
	_caption_text = UI.label("", 22, Color.WHITE)
	_caption_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_text.custom_minimum_size.x = 740
	stack.add_child(_caption_text)
	var start := Button.new()
	start.name = "BeginTraining"
	start.text = "Begin camp mission  ›"
	UI.primary(start)
	start.size_flags_horizontal = Control.SIZE_SHRINK_END
	start.visible = false
	start.pressed.connect(func(): start_game(1, false))
	stack.add_child(start)


func begin_button_visible(show: bool) -> void:
	var start: Button = _caption_panel.find_child("BeginTraining", true, false)
	if start != null and start.visible != show:
		start.visible = show
		skip_button.visible = not show
		if show:
			_focus.call_deferred(start)


func _on_caption(index: int) -> void:
	if intro == null or index < 0 or index >= intro.captions.size():
		return
	_caption_title.text = intro.captions[index].title
	_caption_text.text = intro.captions[index].text
