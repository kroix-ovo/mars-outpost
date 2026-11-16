extends SceneTree
const Session = preload("res://scripts/frontend/game_session.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		print("HUD_REFRESH_FAIL ", text)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func _run() -> void:
	Session.begin({}, 1, false)
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(12)
	main.bridge.auto_advance = false
	var hud: Control = main._hud
	var sim: RefCounted = main.bridge._backend
	check(not hud._drawer.visible and not hud._crew_card.visible, "camp opens with context panels hidden")
	check(hud._skin.dock.visible and hud._skin.action.visible, "actions and next step remain findable")
	check(hud._inspect_section.visible == false and hud._placement_section.visible, "build and inspect use separate contexts")
	for key in [0, 1, 5, 20]:
		check(hud._speed_buttons[key].text.is_empty(), "playback has drawn icons instead of text")
		hud._speed_buttons[key].pressed.emit()
		sim.process_pending_commands()
		await frames()
		check(int(sim.get_snapshot().clock.time_scale) == key, "playback icon actually changes speed")
	check(hud._speed_buttons[0].get_parent().get_theme_constant("separation") >= 10, "playback buttons have extra spacing")
	hud._skin.nav.Build.pressed.emit()
	await frames()
	check(hud._drawer.visible and hud._placement_section.visible, "Build button opens the build context")
	hud._skin.nav.Crew.pressed.emit()
	await frames()
	check(hud._crew_card.visible and not hud._drawer.visible, "Crew replaces the previous panel")
	var crew_id: String = str(hud._crew.get_item_metadata(0))
	var crew_row: Button = hud._skin.crew_rows[crew_id]
	check(not crew_row.astronaut_name.text.is_empty() and crew_row.specialty.text.contains("Engineer"), "name and specialty have separate real labels")
	crew_row.pressed.emit()
	await frames()
	check(crew_id in hud._selected_crew(), "new portrait row selects the actual astronaut")
	hud._skin.nav.Jobs.pressed.emit()
	await frames()
	check(not hud._crew_card.visible and hud._drawer.visible, "Jobs replaces Crew")
	var battery := ""
	for id in sim.get_snapshot().buildings:
		if sim.get_snapshot().buildings[id].definition_id == "battery_bank_mk1": battery = id
	hud.select_building(battery)
	await frames()
	check(hud._inspect_section.visible and not hud._placement_section.visible, "world selection opens equipment details")
	hud._skin.nav.Build.pressed.emit()
	await frames()
	check(not hud._inspect_section.visible and hud._placement_section.visible, "Build returns from inspection to construction")
	for resolution in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]:
		root.size = resolution
		await frames(8)
		hud.refresh_layout()
		hud._skin.refresh(true)
		await frames()
		check(hud._alerts.text == "No active alerts", "untruncated no-alert label at " + str(resolution))
		check(hud._alerts.size.x >= hud._alerts.get_minimum_size().x, "alert text fits its control")
		check(hud._top.get_global_rect().end.x <= hud.size.x + 1, "status strip stays within viewport")
		check(hud._skin.dock.get_global_rect().end.y <= hud.size.y + 1, "dock stays within viewport")
		check(hud._skin.transport.get_global_rect().end.x < hud._skin.dock.get_global_rect().position.x, "time and navigation do not overlap")
	hud._skin.nav.Build.pressed.emit()
	await frames()
	hud._skin.action.pressed.emit()
	await frames()
	check(main.placement.active, "primary mission button starts real map placement")
	hud._skin.action.pressed.emit()
	await frames()
	check(not main.placement.active, "placement action becomes a real Cancel button")
	sim.enable_dust_storms()
	hud._send("start_storm_practice", {})
	hud._time(1)
	sim.process_pending_commands()
	sim.step(1.0)
	await frames()
	check(hud.storm_state().status == "forecast", "storm warning comes from the real simulation")
	hud._storm_save.pressed.emit()
	sim.process_pending_commands()
	await frames()
	check(hud.storm_state().response == "save_power" and int(sim.get_snapshot().clock.time_scale) == 1, "storm choice commits policy and resumes the forecast")
	for text in failures: print("HUD_REFRESH_FAIL ", text)
	if failures.is_empty(): print("HUD_REFRESH_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
