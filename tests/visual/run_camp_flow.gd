extends SceneTree
## The camp mission as launched from the title menu: objective card steps 1 to 6 with the
## automatic incident (no manual Fault drill). Needs a window. Marker: CAMP_FLOW_PASS.
const Session = preload("res://scripts/frontend/game_session.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("CAMP_FLOW_FAIL ", message)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func _run() -> void:
	# Same hand-off the title screen's "Begin camp mission" performs.
	Session.begin({}, 1, false)
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(12)
	var hud: Control = main._hud
	var sim: RefCounted = main.bridge._backend
	check(main.world_index == 1 and sim.supports_building("greenhouse_mk1"), "title hand-off opens the colony that supports the greenhouse")
	check(not hud._tour.active and hud._camp_card.visible and hud.camp_objective().step == 1, "objective card starts on step 1 with the old tutorial off")
	check(hud._save_button.disabled and hud._load_button.disabled, "save and load are disabled, with a reason, while faults and storms cannot be saved")
	var placed := false
	for cell in [[20, 28], [22, 16], [9, 20], [24, 24], [10, 12]]:
		hud._send("place_building", {"definition_id": "greenhouse_mk1", "cell": cell, "rotation_quarters": 0})
		sim.process_pending_commands()
		for b in sim.get_snapshot().buildings.values():
			if b.definition_id == "greenhouse_mk1": placed = true
		if placed: break
	await frames()
	check(placed and hud.camp_objective().step == 2, "placing the farm moves to step 2 (assign builder)")
	var farm := ""
	for id in sim.get_snapshot().buildings:
		if sim.get_snapshot().buildings[id].definition_id == "greenhouse_mk1": farm = id
	var job: String = sim.get_snapshot().buildings[farm].construction_task_id
	# Recovery: cancelling the job refunds materials and returns to step 1.
	hud._send("cancel_task", {"task_id": job})
	sim.process_pending_commands()
	await frames()
	check(hud.camp_objective().step == 1 and sim.get_snapshot().resources.alloy.amount == 24.0, "cancelled construction refunds and the card returns to step 1")
	hud._send("place_building", {"definition_id": "greenhouse_mk1", "cell": sim._journal.values().back().normalized.payload.get("cell", [20, 28]), "rotation_quarters": 0})
	for cell in [[20, 28], [22, 16], [9, 20], [24, 24], [10, 12]]:
		farm = ""
		for id in sim.get_snapshot().buildings:
			if sim.get_snapshot().buildings[id].definition_id == "greenhouse_mk1": farm = id
		if not farm.is_empty(): break
		hud._send("place_building", {"definition_id": "greenhouse_mk1", "cell": cell, "rotation_quarters": 0})
		sim.process_pending_commands()
	job = sim.get_snapshot().buildings[farm].construction_task_id
	var builder: String = hud._adapter.recommended_crew(sim.get_snapshot().tasks[job], sim.get_snapshot())[0]
	hud._send("assign_task", {"task_id": job, "crew_ids": [builder], "priority": 60})
	sim.process_pending_commands()
	await frames()
	check(hud.camp_objective().step == 3, "assigning the builder moves to step 3")
	hud._time(1)
	sim.process_pending_commands()
	for i in 1500:
		sim.step(1.0)
		if sim.get_snapshot().buildings[farm].lifecycle == "commissioned": break
	for i in 5: sim.step(1.0)
	await frames()
	check(hud.camp_objective().step == 4 and "botanist" in hud._camp_text.text and hud.repair_state().faults.is_empty(), "step 4 asks for a botanist; no incident yet")
	var tend := ""
	for id in sim.get_snapshot().tasks:
		if sim.get_snapshot().tasks[id].kind == "farm": tend = id
	hud._send("assign_task", {"task_id": tend, "crew_ids": [hud._adapter.recommended_crew(sim.get_snapshot().tasks[tend], sim.get_snapshot())[0]], "priority": 40})
	sim.process_pending_commands()
	sim.step(1.0)
	await frames(6)
	sim.process_pending_commands()
	await frames()
	var faults: Dictionary = hud.repair_state().faults
	check(faults.size() == 1 and hud.camp_objective().step == 5 and "Incident" in hud._camp_text.text, "the incident happens once, by itself, after the farm is staffed")
	for i in 20: sim.step(1.0)
	await frames()
	check(hud.repair_state().faults.size() == 1, "the incident is not repeated")
	hud.select_building(faults.keys()[0])
	hud._start_repair()
	await frames()
	check(hud._repair_panel.is_open() and not hud._camp_card.visible, "Start repair opens the challenge")
	for attempt in 8:
		var session: Variant = sim.get_repair_state().session
		if session == null: break
		var left: int = session.connected.size()
		var slot: int = session.right_order.find(left)
		hud._repair_panel._select_left(left)
		hud._repair_panel._connect(slot)
		await frames(2)
	hud._repair_panel.visible = false
	for i in 3: sim.step(1.0)
	await frames()
	await frames(4)
	check(hud.camp_progress().level_one and hud.camp_objective().step == 6 and sim.get_storm_state().enabled, "repair done: Camp Level 1, storms now possible")
	# A locked repair with unsafe reserves must not claim an established camp.
	sim._state.repairs.faults[faults.keys()[0]].status = "locked"
	sim._state.repairs.faults[faults.keys()[0]].locked_until_tick = int(sim.get_snapshot().clock.tick_index) + 86400
	sim.step(1.0)
	await frames()
	check(hud.camp_progress().level_one and hud.camp_stability().ok, "locked repair with life support powered and oxygen in reserve: Level 1 on backup")
	sim._state.records.resources.oxygen_kg.amount = 0.2
	for id in sim.get_snapshot().buildings:
		if sim.get_snapshot().buildings[id].definition_id in ["water_electrolyzer_mk1", "greenhouse_mk1"]: hud._send("set_building_enabled", {"building_id": id, "enabled": false})
	sim.process_pending_commands()
	for i in 3: sim.step(1.0)
	await frames()
	var unsafe: Dictionary = hud.camp_progress()
	check(not unsafe.level_one and unsafe.emergency and not hud.camp_stability().ok and hud.camp_objective().step == 5 and "NOT resolved" in hud._camp_text.text, "locked repair with unsafe oxygen: no Level 1, emergency shown: " + str(hud.camp_stability().reasons))
	print("CAMP_FLOW_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty(): print("CAMP_FLOW_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
