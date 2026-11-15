extends SceneTree

const Fixture = preload("res://tests/crew_ui/fixture_facade.gd")
const Routes = preload("res://scripts/crew/crew_routes.gd")
const Slot = preload("res://scripts/ui/outpost_save_slot.gd")
const HUD = preload("res://scenes/ui/outpost_hud.tscn")
const MissionControl = preload("res://scenes/ui/outpost_mission_control.tscn")
const CREW := "crew_000001"
const OTHER := "crew_000002"
const SITE := "site_cargo_a"
const JOB := "task_000001"
const TRIP := "expedition_000001"

var failures := 0
var checks := 0
var cmd_id := 0
var last_result: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func opened(size: int = 6, variant: String = "salvage_6crew") -> RefCounted:
	var f := Fixture.new()
	var result := f.open(size, variant)
	check(result.ok, result.reason)
	f.game_event.connect(func(e: Dictionary):
		if e.type == "command_result":
			last_result = e.data)
	return f

func send(f: RefCounted, type: String, payload: Dictionary) -> Dictionary:
	cmd_id += 1
	f.submit_command({"contract_version": "2.0.0", "command_id": "test:%06d" % cmd_id,
		"type": type, "payload": payload})
	f.process_pending_commands()
	return last_result

func launch(f: RefCounted, oxygen: float = 0.12) -> Dictionary:
	return send(f, "start_eva", {"site_id": SITE, "crew_ids": [OTHER, CREW],
		"work_duration_s": 20.0, "oxygen_kg_per_crew": oxygen, "battery_kwh_per_crew": 0.006})

func assign(f: RefCounted, id: String, crew: String) -> Dictionary:
	return send(f, "assign_task", {"task_id": id, "crew_ids": [crew], "priority": 66})

func place(f: RefCounted) -> Dictionary:
	return send(f, "place_building", {"definition_id": "fixture_electrolyzer",
		"cell": [4, 8], "rotation_quarters": 0})

func ticks(f: RefCounted, count: int) -> void:
	for i in range(count):
		f.step()

func _run() -> void:
	_jobs()
	_eva()
	_saves()
	_edge_cases()
	_ui()
	_first_shift()
	print("Task 03: %d/%d checks passed." % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func _jobs() -> void:
	for size in [5, 6, 9]:
		var f := opened(size, "habitat_%dcrew" % size)
		check(f.state.crew.size() == size, "Roster size")
		f.state.buildings.building_000003.condition = 0.5
		var repair: String = f.add_job("repair", "building_000003", 3.0)
		check(assign(f, repair, CREW).success, "Assign in %d-person colony" % size)
		var farm: String = f.add_job("farm", "building_000004", 4.0)
		var collision := assign(f, farm, CREW)
		check(not collision.success and collision.code == "crew_unavailable", "Incompatible jobs reject")
		check(send(f, "cancel_task", {"task_id": repair}).success, "Cancel releases crew")
		check(assign(f, farm, CREW).success, "Reassign after cancel")
		var food: float = f.state.resources.food_kcal.amount
		ticks(f, 35)
		check(f.state.tasks[farm].status == "completed" and f.state.resources.food_kcal.amount == food + 100.0,
			"Farm completion granted once")
		var second: String = f.add_job("repair", "building_000003", 3.0)
		check(assign(f, second, OTHER).success, "Assign to repair")
		ticks(f, 35)
		check(f.state.buildings.building_000003.condition == 1.0 and f.state.tasks[second].status == "completed",
			"Repair restores condition")
	var f := opened()
	var alloy: float = f.state.resources.alloy.amount
	check(place(f).success, "Place construction module")
	check(assign(f, JOB, CREW).success, "Assign construction crew")
	ticks(f, 25)
	check(f.state.tasks[JOB].status == "completed" and f.state.buildings.building_000006.lifecycle == "commissioned"
		and f.state.resources.alloy.amount == alloy - 2, "Commission once without another debit")

func _eva() -> void:
	var f := opened()
	var oxygen: float = f.state.resources.oxygen_kg.amount
	var deny := launch(f, 0.01)
	check(deny.code == "reserve_insufficient" and f.state.expeditions.is_empty()
		and f.state.resources.oxygen_kg.amount == oxygen, "Unsafe plan rejected atomically")
	check(launch(f).success and is_equal_approx(f.state.resources.oxygen_kg.amount, oxygen - 0.24), "Load EVA suits once")
	ticks(f, 3)
	check(f.state.expeditions[TRIP].status == "outbound" and f.state.expeditions[TRIP].route_progress_m == 3.0, "Travel on ticks")
	send(f, "set_time_scale", {"time_scale": 0})
	ticks(f, 2)
	check(f.state.expeditions[TRIP].route_progress_m == 3.0, "Paused flight remains fixed")
	check(send(f, "recall_eva", {"expedition_id": TRIP}).success, "Recall works while paused")
	send(f, "set_time_scale", {"time_scale": 1})
	ticks(f, 3)
	check(f.state.expeditions[TRIP].status == "completed" and f.state.tasks[JOB].status == "cancelled"
		and f.state.sites[SITE].remaining_cargo.alloy == 4, "Outbound recall gives no reward and returns crew")

	var g := opened()
	check(launch(g).success, "Launch working recall scenario")
	ticks(g, 15)
	check(g.state.expeditions[TRIP].status == "working", "Arrive and start work")
	g.world.blocked.append(Vector2i(2, 8))
	check(send(g, "recall_eva", {"expedition_id": TRIP}).success and g.state.expeditions[TRIP].status == "stranded",
		"Blocked recall creates stranded state")
	check(send(g, "recall_eva", {"expedition_id": TRIP}).code == "route_unreachable", "Stranded retry gives reason")
	g.world.blocked.clear()
	check(send(g, "recall_eva", {"expedition_id": TRIP}).success, "Stranded team resumes on valid route")
	ticks(g, 10)
	check(g.state.crew[CREW].task_id == null and g.state.tasks[JOB].status == "cancelled",
		"Working recall frees crew and cancels task")
	var route: Dictionary = g.world.query_route({"from_cell": [2, 8], "to_cell": [12, 8]}, g.state)
	var back := Routes.from_progress(g.world, g.state, route.waypoints_m, 2.25, [2, 8])
	check(is_equal_approx(back.distance_m, 2.25) and is_equal_approx(back.waypoints_m[0][0], 4.75),
		"Recall charges backtracking from partial segment")

	var full := opened(6, "salvage_full_store_6crew")
	var old_alloy: float = full.state.resources.alloy.amount
	check(launch(full).success, "Launch full-store scenario")
	ticks(full, 40)
	check(full.state.expeditions[TRIP].status == "completed" and full.state.tasks[JOB].status == "completed",
		"Salvage follows outbound/work/return phases")
	check(full.state.resources.alloy.amount == old_alloy + 2 and full.caches[TRIP].alloy == 2
		and full.state.sites[SITE].remaining_cargo.get("alloy", 0) == 0, "Cargo conserved across full store and return cache")
	check(send(full, "recall_eva", {"expedition_id": TRIP}).code == "invalid_state", "Terminal expedition cannot reactivate")

func _saves() -> void:
	var f := opened()
	check(launch(f).success, "Launch save scenario")
	ticks(f, 19)
	var path := "user://crew_ui_test_%d.json" % OS.get_process_id()
	check(Slot.save(f, path).ok, "Write mid-EVA save through the UI slot")
	check(Slot.save(f, path).ok, "Replace save atomically")
	ticks(f, 21)
	var expected: Dictionary = f.get_snapshot()
	check(Slot.load_slot(f, path).ok, "Reload mid-EVA checkpoint")
	ticks(f, 21)
	check(equivalent(f.state, expected), "Resumed EVA matches uninterrupted stock and progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var job := opened()
	check(place(job).success and assign(job, JOB, CREW).success, "Build save scenario")
	ticks(job, 6)
	var checkpoint: Dictionary = job.export_save()
	ticks(job, 16)
	var built: Dictionary = job.get_snapshot()
	check(job.import_save(checkpoint).ok, "Restore mid-construction job")
	ticks(job, 16)
	check(job.get_snapshot() == built, "Resumed construction agrees with uninterrupted completion")
	var invalid: Dictionary = checkpoint.duplicate(true)
	invalid.crew_record.state.crew[CREW].task_id = "missing_task"
	check(not job.import_save(invalid).ok and job.get_snapshot() == built, "Invalid crew save leaves state unchanged")
	for file in ["placement_mid_job_tick6", "eva_full_store_cache_tick40", "eva_full_store_drained_tick41", "alt_campaign_rev5"]:
		var sample: Dictionary = f.read("saves/" + file + ".json")
		check(f.adapter.validate_state(sample.subsystems.crew_tasks, sample.core).ok, "Validate shared save: " + file)


func _edge_cases() -> void:
	var f := opened()
	var supply: float = f.state.resources.alloy.amount
	check(place(f).success and assign(f, JOB, CREW).success, "Schedule cancellable construction")
	ticks(f, 6)
	check(f.state.tasks[JOB].completed_work_s > 0.0, "Construction labor recorded before refund")
	check(send(f, "cancel_task", {"task_id": JOB}).success and f.state.crew[CREW].task_id == null
		and not f.state.buildings.has("building_000006") and f.state.resources.alloy.amount == supply,
		"Construction cancellation atomically releases crew and refunds prepaid materials")
	check(send(f, "cancel_task", {"task_id": JOB}).code == "not_cancellable"
		and f.state.resources.alloy.amount == supply, "Cancelled construction cannot refund twice")

	var g := opened()
	var denied := launch(g, 0.25)
	check(denied.code == "capacity_exceeded" and g.state.expeditions.is_empty(), "Suit maximum rejects oversupply")
	g.world.blocked.append(Vector2i(2, 8))
	check(launch(g, 0.01).code == "route_unreachable", "Route failure takes precedence over reserve failure")
	g.world.blocked.clear()
	check(launch(g).success, "Launch depletion scenario")
	g.adapter._eva.policy.fail_on_suit_exhaustion = true
	g.state.expeditions[TRIP].suit_stores[CREW].oxygen_kg = 0.0
	var base_oxygen: float = g.state.resources.oxygen_kg.amount
	ticks(g, 1)
	check(g.state.expeditions[TRIP].status == "failed" and g.state.tasks[JOB].blocked_code == "reserve_insufficient"
		and g.state.crew[CREW].location_kind == "eva" and g.state.resources.oxygen_kg.amount == base_oxygen,
		"Configured exhaustion fails explicitly without return credit")

	var h := opened()
	var snapshot: Dictionary = h.get_snapshot()
	var proposal: Dictionary = h.adapter.evaluate_hazards(snapshot,
		[{"crew_id": CREW, "code": "fixture_radiation", "dose_msv": 0.125, "exposure_s": 1.0}])
	check(proposal.crew_updates[CREW].radiation_dose_msv == 0.125
		and snapshot.crew[CREW].radiation_dose_msv == 0.0 and proposal.resource_requests.is_empty(),
		"Hazard evaluation is a detached proposal with no extra metabolism")

	var building: Dictionary = snapshot.buildings.building_000004
	var route := Routes.to_building(h.world, snapshot, [2.75, 0.0, 8.5], building,
		h.catalog[building.definition_id])
	var follow := Routes.position(route.waypoints_m, 0.25)
	check(is_equal_approx(follow[0], 3.0), "Sub-meter crew travel continues instead of oscillating at the cell center")

func _ui() -> void:
	var f := opened()
	var hud := HUD.instantiate()
	hud.bind(f, f.adapter, f.world, f.catalog)
	root.add_child(hud)
	check("O₂ 120.00 kg" in hud._vitals.text and hud._crew.item_count == 6, "HUD renders authoritative stock and roster")
	hud.select_crew(CREW)
	check("Fixture Crew A" in hud._crew_text.text and "Engineering 80%" in hud._crew_text.text, "HUD inspects selected astronaut")
	check("Outbound: 10 s" in hud._eva_forecast.text and not hud._launch.disabled, "HUD displays live accepted forecast")
	hud._launch.pressed.emit()
	f.process_pending_commands()
	check(f.state.expeditions.has(TRIP) and "accepted" in hud._status.text, "HUD dispatches exact launch command")
	hud._recall.pressed.emit()
	f.process_pending_commands()
	check(f.state.expeditions[TRIP].status == "returning", "HUD recall targets current expedition")
	hud.queue_free()

func _first_shift() -> void:
	var f := opened()
	var crew_root := Node3D.new()
	root.add_child(crew_root)
	var control := MissionControl.instantiate()
	root.add_child(control)
	var save_path := "user://crew_ui_first_shift_%d.json" % OS.get_process_id()
	control.bind(crew_root, f, f.adapter, f.world, f.catalog, save_path)
	var hud: PanelContainer = control.hud
	var view: Node3D = crew_root.get_child(0)
	check(view.get_child_count() == 6, "Mission Control mounts one avatar per crew member")
	view.crew_selected.emit(CREW)
	check(hud._selected_crew() == [CREW] and view._selected_crew == [CREW],
		"World and HUD share crew selection")
	view.crew_selected.emit(OTHER)
	check(hud._selected_crew() == [OTHER], "Picking a second astronaut selects only that astronaut")
	control._toggle.pressed.emit()
	check(not hud.visible and control.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Collapsing Mission Control exposes the map")
	control._toggle.pressed.emit()

	check(hud._assign_button.disabled, "Assign is disabled until a job is selected")
	hud.select_building("building_000003")
	check(hud._selected(hud._buildings) == "building_000003" and hud._tabs.current_tab == hud.Tab.BUILD,
		"Map building selection opens its inspector")
	hud.set_placement_cell(Vector2i(4, 8))
	hud._select_option(hud._catalog_menu, "fixture_electrolyzer")
	hud._preview_build()
	check(not hud._place.disabled, "Valid, affordable placement is enabled")
	hud._place.pressed.emit()
	f.process_pending_commands()
	check(hud._selected(hud._tasks) == JOB and hud._tabs.current_tab == hud.Tab.CREW,
		"Successful placement opens the new construction job")
	hud._suggest_button.pressed.emit()
	check(hud._selected_crew().size() == 1 and not hud._assign_button.disabled,
		"Suggested crew can take the new job")
	hud._assign_button.pressed.emit()
	f.process_pending_commands()
	check(hud._assign_button.disabled and not hud._cancel_button.disabled,
		"Occupied job slot prevents accidental reassignment")
	ticks(f, 20)
	check(f.state.buildings.building_000006.lifecycle == "commissioned", "Build and assign through the mounted HUD")

	hud.select_crew(OTHER)
	hud.select_site(SITE)
	check(hud._selected(hud._sites) == SITE and hud._tabs.current_tab == hud.Tab.EVA
		and not hud._launch.disabled, "Map site selection opens a valid EVA plan")
	hud._oxygen.value = 0.01
	check(hud._launch.disabled and "Load at least" in hud._eva_forecast.text, "Unsafe suit load shows a reserve warning")
	hud._oxygen.value = 0.12
	hud._launch.pressed.emit()
	f.process_pending_commands()
	ticks(f, 2)
	hud._save_load(false)
	var astronaut: Node3D = view._avatars[OTHER]
	var saved_position: Vector3 = astronaut._target
	astronaut.position += Vector3(5.0, 0.0, 5.0)
	hud._save_load(true)
	check(astronaut.position.is_equal_approx(saved_position) and hud._selected_crew().is_empty(),
		"Loading the same checkpoint snaps avatars and clears the old selection")
	hud._recall.pressed.emit()
	f.process_pending_commands()
	check(f.state.expeditions[TRIP].status == "returning", "Recall works from the restored expedition")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	var next := opened(5)
	control.bind(crew_root, next, next.adapter, next.world, next.catalog)
	check(hud._crew.item_count == 5 and view._avatars.size() == 5 and crew_root.get_child_count() == 1,
		"Rebinding reuses the mount and shows the new roster")
	ticks(f, 1)
	check(hud._crew.item_count == 5, "Old simulation no longer updates Mission Control")
	control.free()
	crew_root.free()

# The shared contract allows float tolerance across JSON and engine boundaries.
func equivalent(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not equivalent(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 1e-8 + 1e-9 * absf(float(b))
	return a == b
