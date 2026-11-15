extends RefCounted
## Front-end state shared between the title screen and the colony scene, plus the small
## user:// files the front end owns (astronaut profile and settings). The simulation never
## reads these; the colony only uses them for the greeting and the commander figure.

const Look := preload("res://scripts/crew/astronaut_look.gd")

const PROFILE_PATH := "user://astronaut_profile.json"
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SETTINGS := {"music_volume": 0.7, "fullscreen": false, "play_intro": true}

## True once the player has come through the front end. Scenes opened directly (tests,
## the editor's "run current scene") keep the colony's plain defaults.
static var active := false
## Which colony to open: 0 = training shift, 1 = reference colony.
static var world_index := 0
static var tutorial := true
static var commander: Dictionary = {}
## Load Game asked to restore the quick save once the colony is bound.
static var load_save_on_start := false


static func begin(profile: Dictionary, world: int, with_tutorial: bool) -> void:
	active = true
	commander = Look.sanitize(profile)
	world_index = world
	tutorial = with_tutorial


static func reset() -> void:
	active = false
	world_index = 0
	tutorial = true
	commander = {}
	load_save_on_start = false


static func load_profile(path: String = PROFILE_PATH) -> Dictionary:
	## Returns {"exists": bool, "look": Dictionary}; an unreadable file falls back to the default.
	if not FileAccess.file_exists(path):
		return {"exists": false, "look": Look.default_look()}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"exists": false, "look": Look.default_look()}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {"exists": false, "look": Look.default_look()}
	return {"exists": true, "look": Look.sanitize(parsed.get("look", parsed))}


static func save_profile(look: Dictionary, path: String = PROFILE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"schema_version": 1, "look": Look.sanitize(look)}, "  "))
	file.close()
	return true


static func load_settings(path: String = SETTINGS_PATH) -> Dictionary:
	var settings := DEFAULT_SETTINGS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		settings.music_volume = clampf(float(config.get_value("audio", "music_volume", settings.music_volume)), 0.0, 1.0)
		settings.fullscreen = bool(config.get_value("display", "fullscreen", settings.fullscreen))
		settings.play_intro = bool(config.get_value("game", "play_intro", settings.play_intro))
	return settings


static func save_settings(settings: Dictionary, path: String = SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", clampf(float(settings.get("music_volume", 0.7)), 0.0, 1.0))
	config.set_value("display", "fullscreen", bool(settings.get("fullscreen", false)))
	config.set_value("game", "play_intro", bool(settings.get("play_intro", true)))
	return config.save(path) == OK


static func volume_db(linear: float) -> float:
	return -80.0 if linear <= 0.001 else linear_to_db(linear)


static func apply_display(settings: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.get("fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
