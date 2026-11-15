extends SceneTree
## Real main scene + HUD + production simulation. No injected progress or resource changes.
var main: Node
var hud: Control
var sim: RefCounted
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func flush() -> void:
	sim.process_pending_commands()

func select_option(widget: OptionButton, id: String) -> void:
	for i in widget.item_count:
		if widget.get_item_metadata(i) == id:
			widget.select(i)
			widget.item_selected.emit(i)
			return

func wait_trip() -> void:
	for i in 150:
		var result: Dictionary = sim.step(1.0)
		check(result.ok, "EVA tick succeeds")
		var active := false
		for trip in sim.get_snapshot().expeditions.values():
			if trip.status not in ["completed", "failed"]: active = true
		if not active: return
	check(false, "EVA completes within 150 ticks")

func _run() -> void:
	main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	main.bridge.auto_advance = false
	hud = main._hud
	sim = main.bridge._backend
	check(hud._mission.completed_count() == 0, "new shift has no completed objectives")
	check(hud._tabs.get_tab_title(hud._tabs.current_tab) == "Guide", "first boot opens instructions")
	hud._mission_next()
	check(hud._tabs.get_tab_title(hud._tabs.current_tab) == "EVA", "mission action opens the next task")
	hud._crew.select(0, false)
	hud._crew.select(1, false)
	hud._refresh_selection()
	hud._launch.pressed.emit()
	flush()
	check(not sim.get_snapshot().expeditions.is_empty(), "HUD launches expedition")
	check(not hud._mission.done.has("salvage"), "launch alone does not earn salvage completion")
	hud._recall.pressed.emit()
	flush()
	wait_trip()
	check(not hud._mission.done.has("salvage"), "empty recalled expedition does not earn salvage completion")
	hud._launch.pressed.emit()
	flush()
	wait_trip()
	check(hud._mission.done.has("salvage"), "working and returning earns salvage objective")
	var before_capacity: float = sim.get_snapshot().resources.oxygen_kg.capacity
	hud._mission_next()
	select_option(hud._catalog_menu, "fixture_storage_module")
	hud.set_placement_cell(Vector2i(7, 5))
	hud._place.pressed.emit()
	flush()
	check(hud._mission.done.has("place"), "HUD placement earns place objective")
	check(not hud._mission.done.has("commission"), "placement alone does not earn commissioning")
	var task_id := ""
	for task in sim.get_snapshot().tasks.values():
		if task.kind == "construct": task_id = task.id
	if task_id.is_empty():
		print("FIRST_SHIFT_DEBUG ", hud._status.text, " preview ", hud._build_preview.text, " resources ", sim.get_snapshot().resources.alloy.amount)
		quit(1)
		return
	select_option(hud._tasks, task_id)
	hud._mission_next()
	hud._suggest()
	hud._assign()
	flush()
	check(hud._mission.done.has("assign"), "real crew assignment earns staffing objective")
	for i in 100:
		check(sim.step(1.0).ok, "construction tick succeeds")
		if sim.get_snapshot().tasks[task_id].status == "completed": break
	check(hud._mission.completed_count() == 4, "complete training loop earns all four objectives")
	check(sim.get_snapshot().resources.oxygen_kg.capacity > before_capacity, "commissioning increases actual storage")
	check(hud._mission_action.text == "Start colony repairs", "training offers next mission")
	hud._mission_next()
	main.bridge.auto_advance = false
	sim = main.bridge._backend
	check(main.world_index == 1 and not hud._mission.training, "next mission switches to reference colony")
	check(hud._mission.completed_count() == 0, "world switch clears previous mission progress")
	hud._mission_next()
	check(hud._mission.done.has("systems"), "opening Systems completes inspection objective")
	check(not hud._mission.done.has("repair"), "inspection does not complete repairs")
	var task_ids: Array = sim.get_snapshot().tasks.keys()
	check(not task_ids.is_empty(), "reference colony has repair work")
	for id in task_ids:
		select_option(hud._tasks, id)
		hud._suggest()
		hud._assign()
		flush()
		for i in 200:
			check(sim.step(1.0).ok, "repair tick succeeds")
			if sim.get_snapshot().tasks[id].status == "completed": break
	check(hud._mission.completed_count() == 2, "all authored repairs complete second mission")
	main.load_world(0)
	main.bridge.auto_advance = false
	check(hud._mission.completed_count() == 0, "restarting training clears achievements")
	main.free()
	for failure in failures: print("FIRST_SHIFT_FAIL ", failure)
	print("FIRST_SHIFT_RESULT checks=", checks, " failures=", failures.size())
	if failures.is_empty(): print("FIRST_SHIFT_PASS")
	quit(0 if failures.is_empty() else 1)
