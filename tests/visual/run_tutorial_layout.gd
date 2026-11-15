extends SceneTree
## Rendered tutorial walkthrough with layout assertions and PNG evidence. Plays the real tutorial
## through HUD handlers and the production simulation (time advanced with sim.step), and at each
## key step asserts that the card and every highlight are on screen, the highlight does not sit
## under the card, the card text is at least 13 physical pixels, and Launch is fully visible.
## Needs a window:
##   Godot --path . --resolution 1280x720 --audio-driver Dummy --script tests/visual/run_tutorial_layout.gd
##   Godot --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_tutorial_layout.gd
## Output: docs/evidence/tutorial/<window>/NN_*.png and TUTORIAL_LAYOUT_PASS.

var main: Node
var hud: Control
var sim: RefCounted
var failures: Array[String] = []
var checks := 0
var directory := ""


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message + " [step=" + str(hud._tour_step.get("id", "<none>")) + "]")


func settle(frames: int = 3) -> void:
	sim.process_pending_commands()
	for i in frames:
		await process_frame
	hud._tour_refresh()
	await process_frame
	await process_frame


func step_id() -> String:
	return str(hud._tour_step.get("id", "<none>"))


func capture(name: String, expect_highlight: bool) -> void:
	await settle(6)
	var bounds := root.get_visible_rect()
	var card: Rect2 = hud._tour_card.get_global_rect()
	if hud._tour_card.visible:
		check(bounds.encloses(card), name + ": card inside the viewport")
		var scale: float = DisplayServer.window_get_size().y / bounds.size.y
		check(hud._tour_body.get_theme_font_size("font_size") * scale >= 12.5, name + ": card text at least 13 physical px")
		var targets: Dictionary = hud._tour_overlay.current_targets()
		var count: int = targets.rects.size() + targets.points.size()
		if expect_highlight:
			check(count > 0, name + ": current target highlighted")
		for rect in targets.rects:
			check(bounds.grow(2).encloses(rect), name + ": highlighted control on screen")
			var own_button: bool = hud._tour_primary != null and rect == hud._tour_primary.get_global_rect()
			check(own_button or not card.intersects(rect), name + ": highlighted control not covered by the card")
		for point in targets.points:
			check(bounds.has_point(point.at), name + ": highlighted world target on screen")
			check(not card.has_point(point.at), name + ": world target not covered by the card")
	var path := directory + "/" + name + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, name + ": screenshot saved")
	print("TUTORIAL_CAPTURE ", ProjectSettings.globalize_path(path), " step=", step_id())


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


func ticks(predicate: Callable, limit: int) -> void:
	for i in limit:
		if predicate.call(): break
		sim.step(1.0)
		if i % 4 == 0: await process_frame
	await settle()


func newest_trip() -> Dictionary:
	var trips: Dictionary = sim.get_snapshot().expeditions
	var ids := trips.keys()
	ids.sort()
	return {} if ids.is_empty() else trips[ids[-1]]


func rebind() -> void:
	main.bridge.auto_advance = false
	sim = main.bridge._backend
	await settle()


func _run() -> void:
	var window := DisplayServer.window_get_size()
	directory = "res://docs/evidence/tutorial/%dx%d" % [window.x, window.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	hud = main._hud
	await rebind()
	check(step_id() == "welcome" and int(sim.get_snapshot().clock.time_scale) == 0, "paused welcome")
	await capture("01_welcome", false)
	hud.tutorial_press("welcome")
	await capture("02_habitat_and_supplies", true)
	hud.tutorial_press("orient")
	await settle()
	await capture("03_select_astronaut", true)
	var idle: Array = []
	for id in sim.get_snapshot().crew:
		idle.append(id)
	idle.sort()
	await select_crew([idle[0]])
	await capture("04_add_second_astronaut", true)
	hud.tutorial_press(str(hud._tour_step.buttons[0].id))
	await settle()
	await capture("05_open_eva_tab", true)
	await open_tab("EVA")
	await capture("06_safety_forecast", true)
	if step_id() == "forecast":
		hud.tutorial_press("forecast")
	await settle()
	check(step_id() == "launch", "launch step reached")
	var bounds := root.get_visible_rect()
	check(hud._launch.is_visible_in_tree() and bounds.encloses(hud._launch.get_global_rect()) and hud._drawer.get_global_rect().encloses(hud._launch.get_global_rect()), "Launch fully visible")
	await capture("07_launch_visible", true)
	hud._launch.pressed.emit()
	await settle()
	hud._speed_buttons[5].pressed.emit()
	await settle()
	await ticks(func(): return newest_trip().get("status") == "working", 120)
	await capture("08_watch_spacewalk", true)
	await ticks(func(): return newest_trip().get("status") in ["completed", "failed"], 300)
	check(step_id() == "home", "salvage home")
	await capture("09_crew_home", true)
	hud.tutorial_press("home")
	hud._speed_buttons[0].pressed.emit()
	await settle()
	await open_tab("Build")
	await select_option(hud._catalog_menu, "fixture_storage_module")
	hud._place_on_map.pressed.emit()
	await settle()
	var placement: Node3D = main.get_node("Placement")
	var cell: Array = hud._recommended_storage_cell()
	placement.hover_cell = cell.duplicate()
	placement.call("_refresh")
	await settle()
	check(step_id() == "place", "place step reached")
	await capture("10_place_on_map", true)
	placement.placement_submitted.emit({"definition_id": "fixture_storage_module", "cell": cell.duplicate(), "rotation_quarters": 0})
	await settle()
	await open_tab("Jobs")
	var task_id := ""
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "construct" and task.status not in ["completed", "cancelled", "failed"]: task_id = task.id
	await select_option(hud._tasks, task_id)
	await select_crew([])
	hud._suggest_button.pressed.emit()
	await settle()
	await capture("11_assign_builder", true)
	hud._assign_button.pressed.emit()
	await settle()
	hud._speed_buttons[5].pressed.emit()
	await settle()
	await ticks(func(): return float(sim.get_snapshot().tasks[task_id].completed_work_s) > 5.0, 200)
	await capture("12_construction", true)
	await ticks(func(): return sim.get_snapshot().tasks[task_id].status == "completed", 300)
	check(step_id() == "built", "storage commissioned")
	await capture("13_storage_online", true)
	hud.tutorial_press("built")
	await capture("14_training_complete", false)
	hud.tutorial_press("go_reference")
	await rebind()
	await capture("15_reference_welcome", false)
	hud.tutorial_press("ref_welcome")
	await open_tab("Systems")
	await capture("16_reference_systems", true)
	hud.tutorial_press("ref_read")
	await settle()
	var repairs: Array = []
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "repair" and task.status != "completed": repairs.append(task.id)
	repairs.sort()
	var first := true
	for id in repairs:
		await open_tab("Jobs")
		await select_option(hud._tasks, id)
		await select_crew([])
		hud._suggest_button.pressed.emit()
		await settle()
		hud._assign_button.pressed.emit()
		await settle()
		hud._speed_buttons[5].pressed.emit()
		await settle()
		if first:
			await ticks(func(): return sim.get_snapshot().crew[sim.get_snapshot().tasks[id].assigned_crew_ids[0]].status == "working", 200)
			await capture("17_reference_repair", true)
			first = false
		await ticks(func(): return sim.get_snapshot().tasks[id].status == "completed", 400)
	hud._speed_buttons[0].pressed.emit()
	await settle()
	check(step_id() == "debrief", "debrief reached")
	await capture("18_debrief", false)
	hud.tutorial_press("debrief")
	await capture("19_independent_shift", false)
	check(hud._tour_card.visible and step_id() == "shift_running", "next objective remains visible after training")
	# Detached presentation snapshots test result layouts without a six-hour run.
	var result_snapshot: Dictionary = sim.get_snapshot().duplicate(true)
	result_snapshot.clock.elapsed_s += hud._tour.SHIFT_SECONDS
	hud._on_snapshot(result_snapshot)
	await capture("20_shift_complete", false)
	check(step_id() == "shift_complete" and hud._tour_primary.text == "Continue free play", "success offers a clear next action")
	hud._tour._shift_result = ""
	result_snapshot.crew[result_snapshot.crew.keys()[0]].health = 0.0
	hud._on_snapshot(result_snapshot)
	await capture("21_shift_failed", false)
	check(step_id() == "shift_failed", "failure offers a restart")
	for failure in failures:
		print("TUTORIAL_LAYOUT_FAIL ", failure)
	print("TUTORIAL_LAYOUT_RESULT checks=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("TUTORIAL_LAYOUT_PASS")
	quit(0 if failures.is_empty() else 1)
