extends SceneTree
const Session = preload("res://scripts/frontend/game_session.gd")
var main: Node
var hud: Control

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 8) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	await frames(10)
	var folder := "res://docs/evidence/hud_refresh"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join(name + ".png")
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if result != OK:
		push_error("Could not save screenshot")
		quit(1)
	print("HUD_SCREENSHOT ", ProjectSettings.globalize_path(path))

func _run() -> void:
	var options := OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720) if options.has("720p") else Vector2i(1600, 900)
	Session.begin({}, 1, false)
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(15)
	hud = main._hud
	hud._time(0)
	main.bridge._backend.process_pending_commands()
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if not args.is_empty() else "checkpoint"
	await capture(prefix + "_overview")
	if args.has("all"):
		hud._skin._navigate("Build") if hud._skin != null else hud._open_tab("Build")
		await capture(prefix + "_build")
		hud._open_tab("Jobs")
		await capture(prefix + "_jobs")
	if args.has("states"):
		hud._skin._navigate("Crew")
		await capture(prefix + "_crew")
		var sim: RefCounted = main.bridge._backend
		for id in sim.get_snapshot().buildings:
			if sim.get_snapshot().buildings[id].definition_id == "battery_bank_mk1":
				hud.select_building(id)
				hud._fault_drill()
				sim.process_pending_commands()
				hud._start_repair()
				break
		await capture(prefix + "_repair")
		var session: Variant = sim.get_repair_state().session
		if session != null: hud._repair_send("repair_input", {"session_id":session.id,"action":"abandon","value":0.0})
		hud._repair_panel.visible = false
		sim.enable_dust_storms()
		hud._send("start_storm_practice", {})
		hud._time(1)
		sim.process_pending_commands()
		sim.step(1.0)
		await frames(8)
		hud._drawer_open = false
		hud._crew_card.visible = false
		hud._apply_layout()
		await capture(prefix + "_storm")
		if args.has("active_storm"):
			hud._storm_save.pressed.emit()
			sim.process_pending_commands()
			for i in 902: sim.step(1.0)
			await frames(75)
			await capture(prefix + "_storm_active")
	if args.has("radiation"):
		var sim: RefCounted = main.bridge._backend
		sim.enable_radiation()
		hud._time(1)
		sim.process_pending_commands()
		for i in 3602: sim.step(1.0)
		await capture(prefix + "_solar_radiation")
	print("HUD_CAPTURE_PASS")
	quit(0)
