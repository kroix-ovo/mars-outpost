extends SceneTree
## Plays the interactive tutorial end to end through the real main scene, HUD handlers and the
## production simulation. Every transition is earned by a real UI selection or committed
## snapshot; the test never edits balances, tasks or tutorial progress directly.
## Covers: paused start, welcome, out-of-order selection, collapsed drawer, skip/resume, failed
## tick + restart, one-astronaut salvage shortfall, empty recall, full salvage, blocked placement,
## placement, cancelled construction with refund, assignment, commissioning, reference restart,
## systems inspection, every starting repair, debrief and finish.
## Run: Godot --headless --path . --script tests/crew_ui/run_tutorial_mission.gd  (TUTORIAL_PASS)

var main: Node
var hud: Control
var sim: RefCounted
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message + "  [step=" + step_id() + "]")


func step_id() -> String:
	return str(hud._tour_step.get("id", "<none>")) if hud != null else "<none>"


func settle() -> void:
	sim.process_pending_commands()
	await process_frame
	await process_frame
	hud._tour_refresh()


func press(id: String) -> void:
	hud.tutorial_press(id)
	await settle()


func button_ids() -> Array:
	var ids: Array = []
	for spec in hud._tour_step.get("buttons", []):
		ids.append(spec.id)
	return ids


func open_tab(title: String) -> void:
	for i in hud._tabs.get_tab_count():
		if hud._tabs.get_tab_title(i) == title:
			hud._tabs.current_tab = i
	await settle()


func select_crew(ids: Array) -> void:
	hud._crew.deselect_all()
	for id in ids:
		for i in hud._crew.item_count:
			if hud._crew.get_item_metadata(i) == id:
				hud._crew.select(i, false)
	hud._refresh_selection()
	await settle()


func select_option(widget: OptionButton, id: String) -> void:
	for i in widget.item_count:
		if widget.get_item_metadata(i) == id:
			widget.select(i)
			widget.item_selected.emit(i)
	await settle()


func idle_crew() -> Array:
	var result: Array = []
	var crew: Dictionary = sim.get_snapshot().crew
	var ids := crew.keys()
	ids.sort()
	for id in ids:
		if crew[id].status == "idle": result.append(id)
	return result


func tick_until(predicate: Callable, limit: int, label: String) -> void:
	for i in limit:
		if predicate.call(): break
		var result: Dictionary = sim.step(1.0)
		if not result.ok:
			check(false, label + " tick failed: " + str(result))
			break
	await settle()
	check(predicate.call(), label)


func newest_trip() -> Dictionary:
	var trips: Dictionary = sim.get_snapshot().expeditions
	var ids := trips.keys()
	ids.sort()
	return {} if ids.is_empty() else trips[ids[-1]]


func trip_done() -> bool:
	return newest_trip().get("status", "") in ["completed", "failed"]


func amount(id: String) -> float:
	return float(sim.get_snapshot().resources[id].amount)


func storage_building() -> String:
	var found := ""
	var buildings: Dictionary = sim.get_snapshot().buildings
	var ids := buildings.keys()
	ids.sort()
	for id in ids:
		if buildings[id].definition_id == "fixture_storage_module": found = id
	return found


func construct_task(building_id: String) -> String:
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "construct" and task.target_id == building_id and task.status not in ["cancelled", "failed"]:
			return task.id
	return ""


func set_speed(value: int) -> void:
	hud._speed_buttons[value].pressed.emit()
	await settle()


func rebind() -> void:
	main.bridge.auto_advance = false
	sim = main.bridge._backend
	await settle()


func _run() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	hud = main._hud
	await rebind()

	# --- Paused welcome ---
	check(step_id() == "welcome", "boot shows the welcome step")
	check(int(sim.get_snapshot().clock.time_scale) == 0, "tutorial starts paused")
	check(hud._tour_card.visible and "Start tutorial" in hud._tour_step.buttons[0].label, "welcome card offers Start tutorial")
	var first_targets: Dictionary = hud._tour_overlay.current_targets()
	check(hud._tour_primary != null and hud._tour_primary.text == "Start tutorial", "Start tutorial is the prominent primary action")
	check(first_targets.rects.size() == 1 and first_targets.points.is_empty() and first_targets.rects[0] == hud._tour_primary.get_global_rect(), "fresh launch points at exactly one action: Start tutorial")
	check(hud._hud_title.text.begins_with("TRAINING"), "tutorial runs in the labelled training colony")
	# Out of order: choosing crew before reading the intro neither skips nor breaks it.
	var crew := idle_crew()
	await select_crew([crew[0], crew[1]])
	check(step_id() == "welcome", "selection before Start keeps the welcome visible")
	await press("welcome")
	check(step_id() == "orient", "Start tutorial moves to orientation")
	var orient: Dictionary = hud._tour_overlay.current_targets()
	check(orient.rects.size() == 1 and orient.rects[0] == hud._tour_primary.get_global_rect(), "orientation points only at its Next button")
	check(not orient.context.is_empty(), "habitat shown as quiet context")
	await press("orient")
	check(step_id() == "open_eva", "two crew already selected skips straight to opening EVA")
	check(hud._tour_step.index > 1 and not hud._tour_flash.visible, "progress advances without duplicating completed lessons")

	# --- Collapse and skip/resume ---
	hud._toggle_drawer()
	await settle()
	check("hidden" in hud._tour_recovery.text, "collapsed drawer explains how to reopen it")
	check(not hud._tour_overlay.current_targets().rects.is_empty(), "collapsed drawer highlights the toggle")
	hud._toggle_drawer()
	await settle()
	await press("skip")
	check(hud._tour_step.is_empty() and not hud._tour_card.visible, "skip hides the tutorial")
	hud._tour_resume.pressed.emit()
	await settle()
	check(step_id() == "open_eva", "resume continues where the player left off")
	check(not hud._status.text.begins_with("Tutorial hidden"), "resume clears stale hidden message")

	# --- Failed tick and explicit restart ---
	hud.on_simulation_failed({"reason": "synthetic test failure"})
	await settle()
	check("simulation stopped" in hud._tour_recovery.text and "restart_training" in button_ids(), "failed tick offers a restart")
	await press("restart_training")
	await rebind()
	check(main.world_index == 0 and hud._sim_failed.is_empty(), "restart reloads training and clears the failure")
	check(int(sim.get_snapshot().clock.time_scale) == 0, "restarted colony starts paused")
	check(step_id() in ["select_one", "select_two", "open_eva"], "restart keeps intro acknowledgements and returns to crew selection")

	# --- One astronaut: real salvage shortfall ---
	crew = idle_crew()
	await select_crew([crew[0]])
	check(step_id() == "select_two", "one astronaut asks for a second")
	check(hud._tour_step.buttons.size() == 1 and str(hud._tour_step.buttons[0].id).begins_with("add_crew:"), "multi-select helper offered")
	var row_targets: Dictionary = hud._tour_overlay.current_targets()
	check(row_targets.rects.size() == 1 and hud._tour_primary == null, "only the second astronaut's row is pointed at (helper stays secondary)")
	await open_tab("EVA")
	hud._launch.pressed.emit()  # Player ignores the advice and launches alone.
	await settle()
	check(not newest_trip().is_empty() and newest_trip().crew_ids.size() == 1, "one-astronaut trip launched")
	check(step_id() == "resume", "launched trip waits for time to start")
	await set_speed(20)
	check(step_id() == "watch_trip", "running trip is observed")
	await tick_until(trip_done, 200, "single-astronaut trip returns")
	check(amount("alloy") < 10.0, "one astronaut cannot bring enough alloy")
	check(step_id() in ["select_one", "select_two"] and "storage needs 10" in hud._tour_recovery.text, "shortfall explains the need for two astronauts")

	# --- Empty recall ---
	crew = idle_crew()
	await select_crew([crew[0], crew[1]])
	await open_tab("EVA")
	hud._launch.pressed.emit()
	await settle()
	check(hud._selected(hud._trips) == newest_trip().id, "new trip is selected in the EVA tab")
	hud._recall.pressed.emit()
	await settle()
	await tick_until(trip_done, 200, "recalled trip returns")
	check(newest_trip().cargo.is_empty() and newest_trip().work_completed_s == 0.0, "recall returned before any salvage")
	check(step_id() in ["select_one", "select_two", "open_eva", "forecast", "launch"] and "recalled before" in hud._tour_recovery.text, "empty recall is explained on the current spacewalk step")

	# --- Full salvage, taught in order ---
	crew = idle_crew()
	await select_crew([crew[0]])
	await press("add_crew:" + str(hud._tour_step.buttons[0].id).get_slice(":", 1))
	check(hud._selected_crew().size() == 2, "helper adds the second astronaut")
	await open_tab("Jobs")
	check(step_id() == "open_eva", "wrong tab keeps the open-EVA step")
	await open_tab("EVA")
	check(step_id() in ["forecast", "launch"], "EVA tab advances to the forecast")
	if step_id() == "forecast":
		check(not hud._tour_step.buttons[0].get("disabled", false), "safe forecast enables Next")
		await press("forecast")
	check(step_id() == "launch", "forecast leads to launch")
	var launch_rect: Rect2 = hud._launch.get_global_rect()
	check(hud._launch.is_visible_in_tree() and hud._drawer.get_global_rect().encloses(launch_rect), "Launch is inside the visible drawer")
	check("Safe to launch" in hud._eva_summary.text, "plain-language forecast summary")
	hud._launch.pressed.emit()
	await settle()
	check(step_id() == "watch_trip" or step_id() == "resume", "launch starts the trip")
	await set_speed(5)
	var phases := {}
	for i in 300:
		var status: String = newest_trip().get("status", "")
		phases[status] = true
		if status in ["completed", "failed"]: break
		sim.step(1.0)
		await process_frame
	await settle()
	check(phases.has("outbound") and phases.has("working") and phases.has("returning"), "trip observed outbound, working and returning")
	check(newest_trip().status == "completed" and not newest_trip().cargo.is_empty() or amount("alloy") >= 10.0, "two-astronaut salvage delivered")
	check(amount("alloy") >= 10.0 and amount("electronics") >= 2.0, "salvage pays for storage")
	check(step_id() == "home", "crew home step shown")
	for cid in newest_trip().crew_ids:
		check(not main._crew_view._avatars[cid].visible, "returned astronaut is inside, not standing at the airlock")
	await press("home")

	# --- Build: blocked placement, placement, cancellation refund ---
	await set_speed(0)
	check(step_id() == "open_build", "build begins with the Build tab")
	await open_tab("Build")
	check(step_id() == "choose_storage", "choose storage next")
	check(hud._tour_body.text.contains("oxygen") and not hud._tour_body.text.contains("water"), "storage explanation matches the definition (oxygen only)")
	await select_option(hud._catalog_menu, "fixture_storage_module")
	check(step_id() == "placement_mode", "enter placement mode next")
	hud._place_on_map.pressed.emit()
	await settle()
	var placement: Node3D = main.get_node("Placement")
	check(placement.active and step_id() == "place", "placement mode reaches the place step")
	var airlock: Array = main.bridge.map_data.base_airlock_cell
	placement.hover_cell = airlock.duplicate()
	placement.call("_refresh")
	await settle()
	check("will not work" in hud._tour_recovery.text, "blocked cell is explained")
	var cell: Array = hud._recommended_storage_cell()
	check(not cell.is_empty(), "tutorial recommends a valid cell")
	placement.hover_cell = cell.duplicate()
	placement.call("_refresh")
	await settle()
	var alloy_before := amount("alloy")
	placement.placement_submitted.emit({"definition_id": "fixture_storage_module", "cell": cell.duplicate(), "rotation_quarters": 0})
	await settle()
	var building := storage_building()
	check(not building.is_empty() and sim.get_snapshot().buildings[building].lifecycle == "constructing", "placement creates a constructing module")
	check(not placement.active, "placement mode ends after a successful placement")
	check(amount("alloy") < alloy_before, "placement spends real materials")
	check(step_id() == "open_jobs", "next the player opens Jobs")
	await open_tab("Jobs")
	await select_option(hud._tasks, construct_task(building))
	hud._tasks.item_selected.emit(hud._tasks.selected)
	var cancel_button: Button = null
	for child in hud._tasks.get_parent().get_children():
		if child is Button and child.text == "Cancel job": cancel_button = child
	cancel_button.pressed.emit()
	await settle()
	check(storage_building().is_empty() or sim.get_snapshot().buildings[storage_building()].lifecycle != "constructing", "cancellation removes the unfinished module")
	check(is_equal_approx(amount("alloy"), alloy_before), "cancellation refunds the materials")
	check(step_id() == "open_build", "cancelled construction returns to building")
	await open_tab("Build")
	await select_option(hud._catalog_menu, "fixture_storage_module")
	hud._place_on_map.pressed.emit()
	await settle()
	cell = hud._recommended_storage_cell()
	placement.hover_cell = cell.duplicate()
	placement.call("_refresh")
	placement.placement_submitted.emit({"definition_id": "fixture_storage_module", "cell": cell.duplicate(), "rotation_quarters": 0})
	await settle()
	building = storage_building()
	var task_id := construct_task(building)
	check(not task_id.is_empty(), "replaced module has a construction job")

	# --- Assign and commission ---
	await open_tab("Jobs")
	if step_id() == "select_job":
		await select_option(hud._tasks, task_id)
	check(step_id() in ["suggest", "assign"], "construction job selected")
	await select_crew([])
	check(step_id() == "suggest", "suggest step when nobody is selected")
	hud._suggest_button.pressed.emit()
	await settle()
	check(step_id() == "assign", "suggested crew leads to assign")
	hud._assign_button.pressed.emit()
	await settle()
	check(not sim.get_snapshot().tasks[task_id].assigned_crew_ids.is_empty(), "real assignment committed")
	check(step_id() == "run_build", "assignment leads to running time")
	var capacity_before := float(sim.get_snapshot().resources.oxygen_kg.capacity)
	await set_speed(5)
	await tick_until(func(): return sim.get_snapshot().buildings[building].lifecycle == "commissioned", 300, "storage commissions")
	check(float(sim.get_snapshot().resources.oxygen_kg.capacity) > capacity_before, "commissioning increases actual capacity")
	check(step_id() == "built" and "kg" in hud._tour_body.text, "built step reports capacity change")
	await press("built")
	check(step_id() == "to_reference" and "go_reference" in button_ids(), "training ends with an explicit reference restart")

	# --- Reference colony ---
	await press("go_reference")
	await rebind()
	check(main.world_index == 1 and hud._hud_title.text == "REFERENCE COLONY", "reference colony loaded")
	check(int(sim.get_snapshot().clock.time_scale) == 0, "reference colony starts paused")
	check(step_id() == "ref_welcome", "reference welcome")
	var starting_repairs := 0
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "repair" and task.status != "completed": starting_repairs += 1
	check(starting_repairs != 1 or hud._tour_body.text.contains("One machine starts damaged"), "damaged count matches the colony")
	check(not hud._tour_body.text.contains("Two machines"), "no hard-coded damaged count")
	await press("ref_welcome")
	check(step_id() == "ref_systems", "systems step")
	await open_tab("Systems")
	check(step_id() == "ref_read", "opening Systems advances")
	await press("ref_read")
	# Regression (Codex review): cancelling a starting repair must not leave an impossible Assign step.
	var first_repair := ""
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "repair" and task.status != "completed": first_repair = task.id
	check(hud._tour_body.text.contains("One machine starts damaged") == false, "welcome text already passed")
	await open_tab("Jobs")
	await select_option(hud._tasks, first_repair)
	var cancel_repair: Button = null
	for child in hud._tasks.get_parent().get_children():
		if child is Button and child.text == "Cancel job": cancel_repair = child
	cancel_repair.pressed.emit()
	await settle()
	check(sim.get_snapshot().tasks[first_repair].status == "cancelled", "real cancel_task cancelled the repair")
	check(step_id().ends_with("_lost") and "restart_reference" in button_ids(), "cancelled repair offers a restart instead of Assign")
	check(not hud._tour_step.action.contains("Assign"), "no impossible Assign action after cancellation")
	await press("restart_reference")
	await rebind()
	check(main.world_index == 1 and sim.get_snapshot().tasks[first_repair].status != "cancelled", "restart restores the repair job")
	check(step_id() == "ref_welcome", "restarted reference colony replays its welcome")
	await press("ref_welcome")
	await open_tab("Systems")
	await press("ref_read")
	var repairs: Array = []
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "repair" and task.status != "completed": repairs.append(task.id)
	repairs.sort()
	check(not repairs.is_empty(), "reference colony starts with repair jobs")
	for id in repairs:
		check(step_id().begins_with("repair_" + id), "repair step for " + id)
		await open_tab("Jobs")
		if step_id().ends_with("_select"):
			await select_option(hud._tasks, id)
		await select_crew([])
		hud._suggest_button.pressed.emit()
		await settle()
		hud._assign_button.pressed.emit()
		await settle()
		check(step_id().ends_with("_run"), "repair assigned for " + id)
		await set_speed(5)
		await tick_until(func(): return sim.get_snapshot().tasks[id].status == "completed", 400, "repair completes " + id)
		await set_speed(0)
	check(step_id() == "debrief", "all repairs lead to the debrief")
	for id in repairs:
		var target: String = sim.get_snapshot().tasks[id].target_id
		check(float(sim.get_snapshot().buildings[target].condition) >= 0.999, "repair restored " + target)
	await press("debrief")
	check(hud._tour_step.is_empty() and hud._tour.finished and not hud._tour_card.visible, "finishing leaves free play")

	main.free()
	for failure in failures:
		print("TUTORIAL_FAIL ", failure)
	print("TUTORIAL_RESULT checks=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("TUTORIAL_PASS")
	quit(0 if failures.is_empty() else 1)
