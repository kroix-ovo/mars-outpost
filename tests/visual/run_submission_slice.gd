extends SceneTree
## Rendered walkthrough of the submission slice: fault drill, both repair challenges
## (one failed, one solved) and a placed greenhouse. Needs a window:
##   Godot --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_submission_slice.gd
## Output: docs/evidence/submission/NN_*.png and SUBMISSION_SLICE_PASS.
var main: Node
var hud: Control
var sim: RefCounted
var checks := 0
var failures: Array[String] = []
var shot := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("SUBMISSION_SLICE_FAIL ", message)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func capture(name: String) -> void:
	await frames(6)
	shot += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/evidence/submission"))
	var path := "res://docs/evidence/submission/%02d_%s.png" % [shot, name]
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, name + ": screenshot saved")

func find(definition: String) -> String:
	for id in sim.get_snapshot().buildings:
		if sim.get_snapshot().buildings[id].definition_id == definition: return id
	return ""

func _run() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames(8)
	main.load_world(1)
	await frames(8)
	hud = main._hud
	sim = main.bridge._backend
	hud._tour.skip()
	hud._tour_refresh()
	await frames(4)
	check(hud._camp_card.visible and "Build the farm wing" in hud._camp_text.text, "camp objective card opens on the farm step")
	await capture("camp_objective_card")
	check(sim.has_method("get_repair_state"), "live game runs the simulation with repair challenges")
	# Circuit challenge on the battery, failed on purpose through wrong connections.
	var battery := find("battery_bank_mk1")
	hud.select_building(battery)
	hud._fault_drill()
	sim.process_pending_commands()
	await capture("fault_reported")
	hud._start_repair()
	await frames(4)
	check(hud._repair_panel.is_open() and sim.get_repair_state().session != null, "repair modal opens from the simulation's session")
	await capture("circuit_challenge")
	var tick: int = sim.get_snapshot().clock.tick_index
	hud._time(5)
	await frames(30)
	check(sim.get_snapshot().clock.tick_index == tick, "colony clock frozen during the challenge")
	for attempt in 4:
		var session: Variant = sim.get_repair_state().session
		if session == null: break
		var slot := 0
		while int(session.right_order[slot]) == 0: slot += 1
		hud._repair_panel._select_left(0)
		hud._repair_panel._connect(slot)
		await frames(2)
	check(sim.get_repair_state().faults[battery].status == "locked" and sim.get_snapshot().buildings[battery].condition == 0.0, "failed repair: component broken and locked")
	await capture("circuit_failed_lockout")
	hud._repair_panel.visible = false
	hud._start_repair()
	await frames(4)
	check(not hud._repair_panel.is_open(), "locked component cannot be retried by another attempt")
	await capture("lockout_in_build_panel")
	# Alignment challenge on a solar array, solved by locking inside the band.
	sim._state.repairs.faults[battery].status = "resolved"  # test-only: free the single drill slot
	var solar := find("solar_array_mk1")
	hud.select_building(solar)
	hud._fault_drill()
	sim.process_pending_commands()
	hud._start_repair()
	await frames(6)
	check(hud._repair_panel.is_open() and sim.get_repair_state().session.kind == "alignment", "alignment modal opens for solar equipment")
	await capture("alignment_challenge")
	for i in 3000:
		var session: Variant = sim.get_repair_state().session
		if session == null: break
		var wrapped := fposmod(float(session.phase), 2.0)
		var marker := wrapped if wrapped <= 1.0 else 2.0 - wrapped
		if absf(marker - float(session.targets[int(session.stage)])) <= float(session.tolerance) * 0.6:
			hud._repair_panel._push("lock", 0.0)
		await process_frame
	check(sim.get_repair_state().faults[solar].status == "resolved" and sim.get_snapshot().buildings[solar].condition == 1.0, "calibration solved through real-time locks")
	await capture("alignment_repaired")
	hud._repair_panel.visible = false
	# Farm: place a greenhouse through the real command and let the crew build it.
	var placed := false
	for cell in [[20, 28], [22, 16], [9, 20], [24, 24], [10, 12]]:
		hud._send("place_building", {"definition_id": "greenhouse_mk1", "cell": cell, "rotation_quarters": 0})
		sim.process_pending_commands()
		if not find("greenhouse_mk1").is_empty():
			placed = true
			break
	check(placed, "greenhouse placed")
	var farm := find("greenhouse_mk1")
	var job: String = sim.get_snapshot().buildings[farm].construction_task_id
	hud._send("assign_task", {"task_id": job, "crew_ids": [hud.repair_operator()], "priority": 60})
	sim.process_pending_commands()
	for i in 1500:
		sim.step(1.0)
		if sim.get_snapshot().buildings[farm].lifecycle == "commissioned": break
	for i in 60: sim.step(1.0)
	hud.select_building(farm)
	check(sim.get_snapshot().buildings[farm].lifecycle == "commissioned" and sim.get_snapshot().buildings[farm].operating_fraction > 0.0, "greenhouse built by crew and producing")
	await capture("greenhouse_producing")
	check(hud.camp_progress().level_one, "camp Level 1 reached from real farm and fault state")
	# Specialist: the Jobs tab's Suggest crew picks a botanist for the tending job.
	var tend_id := ""
	for id in sim.get_snapshot().tasks:
		if sim.get_snapshot().tasks[id].kind == "farm": tend_id = id
	var botanist: String = hud._adapter.recommended_crew(sim.get_snapshot().tasks[tend_id], sim.get_snapshot())[0]
	hud._send("assign_task", {"task_id": tend_id, "crew_ids": [botanist], "priority": 40})
	sim.process_pending_commands()
	for i in 40: sim.step(1.0)
	await capture("botanist_tending_farm")
	check(sim.get_snapshot().crew[botanist].status in ["travelling", "working"], "botanist walks to the farm and works")
	# Dust storm through the real HUD banner and both response buttons.
	await frames(4)
	check(sim.get_storm_state().enabled and hud._storm_practice.visible, "storms enabled once Level 1 is reached")
	hud._storm_practice.pressed.emit()
	sim.process_pending_commands()
	hud._time(1)
	sim.process_pending_commands()
	sim.step(1.0)
	await frames(4)
	check(sim.get_storm_state().status == "forecast" and sim.get_snapshot().clock.time_scale == 0 and hud._storm_row.visible, "storm warning pauses the colony and shows the choice")
	await capture("storm_warning")
	hud._storm_save.pressed.emit()
	sim.process_pending_commands()
	hud._time(1)
	sim.process_pending_commands()
	for i in 950: sim.step(1.0)
	await frames(4)
	check(sim.get_storm_state().status == "active" and sim.get_snapshot().buildings[farm].operating_fraction == 0.0, "save-power response switches the farm off during the storm")
	await capture("storm_active_saving_power")
	hud._storm_keep.pressed.emit()
	sim.process_pending_commands()
	sim.step(1.0)
	sim.step(1.0)
	await frames(4)
	check(sim.get_snapshot().buildings[farm].power_requested_kw > 0.0, "keep-farm response restores the farm load")
	hud._tasks_button.pressed.emit()
	await capture("camp_level_one_tasks")
	print("SUBMISSION_SLICE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty(): print("SUBMISSION_SLICE_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
