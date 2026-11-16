extends SceneTree
## Actual native game rendering. Setup uses gameplay commands; weather practice is staged.
const Session = preload("res://scripts/frontend/game_session.gd")
var main: Node
var hud: Control
var sim: RefCounted
var folder := "res://docs/evidence/submission_slides"

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 12) -> void:
	for i in count: await process_frame

func shot(name: String) -> void:
	await frames(20)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(folder.path_join(name + ".png"))
	root.get_texture().get_image().save_png(path)
	print("SLIDE_SCREENSHOT ", path)

func camera(focus: Vector3, distance: float, pitch: float = 48.0, yaw: float = 35.0) -> void:
	var rig: Node3D = main.camera_rig
	rig.input_enabled = false
	rig._target_focus = focus
	rig._target_distance = distance
	rig._target_pitch = pitch
	rig._target_yaw = yaw
	rig.position = focus
	rig.distance_m = distance
	rig.pitch_deg = pitch
	rig.yaw_deg = yaw
	rig._apply_camera()

func send(type: String, payload: Dictionary) -> void:
	hud._send(type, payload)
	sim.process_pending_commands()

func ticks(count: int) -> void:
	for i in count: sim.step(1.0)
	await frames()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	Session.begin({}, 1, false)
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(20)
	hud = main._hud
	sim = main.bridge._backend
	var centre: Vector3 = main.camera_rig.position
	camera(centre, 18.0, 43.0)
	await shot("01_arrival_gameplay")
	# Clean title background from the same live scene, also retain an unmodified HUD shot.
	hud.visible = false
	await shot("01_title_clean")
	hud.visible = true
	var cell: Array = [20, 28]
	for candidate in [[20,28], [22,16], [9,20], [24,24], [10,12]]:
		if main.bridge.world_service.validate_placement({"definition_id":"greenhouse_mk1", "cell":candidate,"rotation_quarters":0}, sim.get_snapshot()).get("valid", false):
			cell = candidate
			break
	hud._skin._mission_action()
	main.placement.set_process_unhandled_input(false)
	main.placement.hover_cell = cell
	main.placement._refresh()
	camera((centre + Vector3(cell[0],0,cell[1])) * 0.5, 22.0)
	await shot("02_build_placement")
	main.placement.cancel_placement()
	send("place_building", {"definition_id":"greenhouse_mk1","cell":cell,"rotation_quarters":0})
	await frames()
	hud._skin._mission_action()
	sim.process_pending_commands()
	var farm := ""
	for id in sim.get_snapshot().buildings:
		if sim.get_snapshot().buildings[id].definition_id == "greenhouse_mk1": farm = id
	if farm.is_empty():
		push_error("No farm placed")
		quit(1)
		return
	await ticks(120)
	hud._skin._navigate("Crew")
	await shot("04_crew_work")
	await ticks(1500)
	hud._skin._navigate("Crew")
	hud._skin._mission_action()
	sim.process_pending_commands()
	await ticks(10)
	hud._drawer_open = false
	hud._crew_card.visible = false
	hud._apply_layout()
	await frames()
	hud._skin._mission_action()
	sim.process_pending_commands()
	await frames()
	await shot("05_circuit_repair")
	for attempt in 8:
		var session: Variant = sim.get_repair_state().session
		if session == null: break
		var left: int = session.connected.size()
		hud._repair_panel._select_left(left)
		hud._repair_panel._connect(session.right_order.find(left))
		await frames(2)
	hud._repair_panel.visible = false
	await ticks(5)
	hud._time(0)
	sim.process_pending_commands()
	hud.select_building(farm)
	await shot("03_resource_tradeoffs")
	hud._drawer_open = false
	hud._crew_card.visible = false
	hud._apply_layout()
	await shot("07_established_outpost")
	hud.visible = false
	await shot("07_established_clean")
	hud.visible = true
	hud._skin._navigate("Crew")
	camera(Vector3(cell[0]+1,0,cell[1]+1), 12.0, 40.0)
	await shot("04_crew_work_closeup")
	if OS.get_cmdline_user_args().has("framing"):
		print("SLIDE_FRAMING_PASS")
		quit(0)
		return
	hud._drawer_open = false
	hud._crew_card.visible = false
	hud._apply_layout()
	camera((centre + Vector3(cell[0],0,cell[1])) * 0.5, 22.0)
	# Use the game's explicit storm practice command for a reproducible active event.
	sim.enable_dust_storms()
	send("start_storm_practice", {})
	send("set_time_scale", {"time_scale":1})
	await ticks(1)
	await shot("06a_dust_warning")
	send("set_storm_response", {"response":"save_power"})
	send("set_time_scale", {"time_scale":1})
	await ticks(905)
	await frames(160)
	await shot("06b_dust_storm_active")
	# Run the current storm to its real end, then capture the non-overlapping radiation event.
	for i in 15000:
		sim.step(1.0)
		if sim.get_storm_state().status == "cooldown": break
	sim.enable_radiation()
	send("set_time_scale", {"time_scale":1})
	for i in 4000:
		sim.step(1.0)
		if sim.get_radiation_state().status == "warning": break
	await frames(160)
	await shot("06c_solar_radiation_warning")
	send("set_radiation_shelter", {"enabled":true})
	await ticks(905)
	await shot("06d_solar_radiation_active")
	print("SLIDE_CAPTURE_PASS")
	quit(0)
