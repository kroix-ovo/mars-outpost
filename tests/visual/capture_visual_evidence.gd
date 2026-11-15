extends SceneTree
## Rendered review evidence for the visual polish pass. Drives the real main scene (production
## simulation, crew adapter and HUD) through both worlds and saves PNG captures. Needs a window:
##   Godot --path . --resolution 1600x900 --script tests/visual/capture_visual_evidence.gd
##   Godot --path . --resolution 1280x720 --script tests/visual/capture_visual_evidence.gd
## Output: docs/evidence/visual_polish/<width>x<height>/*.png plus EVIDENCE lines on stdout.
## Commands go through the HUD's own buttons/handlers or the bridge exactly as player input does.

const OUT_ROOT := "res://docs/evidence/visual_polish"

var _main: Node3D
var _hud: Control
var _bridge: Node
var _frame := 0
var _step := 0
var _out := ""
var _placed := false


func _initialize() -> void:
	_main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _out.is_empty():
		var size := root.get_visible_rect().size
		var window := DisplayServer.window_get_size()
		_out = "%s/%dx%d" % [OUT_ROOT, window.x, window.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
		_hud = _main.get("_hud")
		# These scripts exercise free play; the interactive tutorial has its own checks.
		_hud.tutorial_press("skip")
		_bridge = _main.get_node("Integration")
		print("EVIDENCE window ", window, " logical viewport ", size, " backend ", _bridge.backend_kind)
	match _step:
		0:
			if _frame >= 60:
				_capture("01_training_overview")
				_hud._time(0)
				var cell: Array = _bridge.get_snapshot().buildings[_first_building()].cell
				_main.call("_on_hover_cell", cell)
				_main.call("_select_at", cell)
				_next()
		1:
			if _frame >= 20:
				_capture("02_training_module_selected")
				_select_crew(_idle_crew().slice(0, 2))
				_hud._open_tab("EVA")
				_hud._preview_eva()
				print("EVIDENCE eva forecast: ", _hud._eva_forecast.text.get_slice("
", 0), " launch_disabled=", _hud._launch.disabled)
				_next()
		2:
			if _frame >= 20:
				_capture("03_training_eva_plan")
				_hud._launch.pressed.emit()
				print("EVIDENCE launch 1: ", _hud._status.text, " ", _summaries("expeditions"))
				_hud._time(5)
				_next()
		3:
			if _frame >= 100:
				_hud._time(0)
				_hud._refresh_selection()
				print("EVIDENCE trip 1 before recall ", _summaries("expeditions"))
				_capture("04_training_eva_active")
				_hud._recall.pressed.emit()
				print("EVIDENCE recall: ", _hud._status.text, " ", _summaries("expeditions"))
				_hud._time(20)
				_next()
		4:
			if _expedition_done("expedition_000001") or _frame >= 1500:
				_hud._time(0)
				_hud._refresh_selection()
				print("EVIDENCE trip 1 after recall ", _summaries("expeditions"), " cargo ", _bridge.get_snapshot().expeditions.get("expedition_000001", {}).get("cargo"))
				_capture("05_training_eva_recalled_home")
				_select_crew(_idle_crew().slice(2, 4))
				_hud._preview_eva()
				_hud._launch.pressed.emit()
				print("EVIDENCE launch 2: ", _hud._status.text, " ", _summaries("expeditions"))
				_hud._time(20)
				_next()
		5:
			if _expedition_done("expedition_000002") or _frame >= 2400:
				_hud._time(0)
				print("EVIDENCE trip 2 ", _summaries("expeditions"), " stock ", _stock())
				_hud._open_tab("Build")
				_select_option(_hud._catalog_menu, "fixture_storage_module")
				_hud._place_on_map.pressed.emit()
				var placement: Node3D = _main.get_node("Placement")
				var cell := _free_cell()
				placement.hover_cell = cell
				placement.hover_cell_changed.emit(cell)
				placement.call("_refresh")
				print("EVIDENCE placement preview ", cell, " ", placement.last_result)
				_next()
		6:
			if _frame >= 20:
				_capture("06_training_placement_preview")
				var placement: Node3D = _main.get_node("Placement")
				# Same submission the world click performs (main_world._on_placement_submitted).
				placement.placement_submitted.emit({"definition_id": placement.definition_id, "cell": placement.hover_cell.duplicate(), "rotation_quarters": placement.rotation_quarters})
				print("EVIDENCE placement result: ", _main.get("_last_message"), " ", _summaries("buildings"))
				placement.cancel_placement()
				_hud._open_tab("Jobs")
				_select_job_kind("construct")
				_hud._suggest()
				print("EVIDENCE suggested crew ", _hud._selected_crew())
				_next()
		7:
			if _frame >= 20:
				_capture("07_training_crew_jobs")
				_hud._assign()
				print("EVIDENCE construction assign: ", _hud._status.text)
				_hud._time(20)
				_next()
		8:
			if _all_commissioned() or _frame >= 2400:
				_hud._time(0)
				print("EVIDENCE construction ", _summaries("buildings"), " tasks ", _summaries("tasks"), " stock ", _stock())
				var newest := _last_building()
				_main.call("_select_at", _bridge.get_snapshot().buildings[newest].cell)
				_next()
		9:
			# A capture reads the last rendered frame, so let the selection render first.
			if _frame >= 10:
				_capture("08_training_module_commissioned")
				_main.load_world(1)
				_next()
		10:
			if _frame >= 60:
				_capture("09_reference_overview")
				_hud._time(0)
				_hud._open_tab("Jobs")
				_select_job_kind("repair")
				_hud._suggest()
				_hud._assign()
				print("EVIDENCE repair assign: ", _hud._status.text, " crew ", _hud._selected_crew(), " tasks ", _summaries("tasks"))
				_hud._time(5)
				_next()
		11:
			if _frame >= 150:
				_hud._time(0)
				_hud._refresh_selection()
				print("EVIDENCE repair progress ", _summaries("tasks"), " crew ", _summaries("crew"))
				_capture("10_reference_repair_in_progress")
				_hud._time(20)
				_next()
		12:
			if _task_status_done("repair") or _frame >= 2400:
				_hud._time(0)
				print("EVIDENCE repair after ", _summaries("tasks"), " conditions ", _conditions())
				_hud._open_tab("EVA")
				_hud._preview_eva()
				print("EVIDENCE reference EVA forecast: ", _hud._eva_forecast.text.get_slice("
", 0))
				_next()
		13:
			if _frame >= 20:
				_capture("11_reference_eva_unavailable")
				_hud._toggle_drawer()
				_next()
		14:
			if _frame >= 20:
				_capture("12_reference_drawer_collapsed")
				_hud._toggle_drawer()
				_hud._open_tab("Systems")
				_hud._detail_toggle.pressed.emit()
				_next()
		15:
			if _frame >= 20:
				_capture("13_reference_systems_diagnostics")
				print("EVIDENCE_DONE")
				quit(0)
	return false


func _next() -> void:
	_step += 1
	_frame = 0


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out + "/" + name + ".png")
	print("EVIDENCE captured ", path, " err=", image.save_png(path))


func _first_building() -> String:
	var ids: Array = _bridge.get_snapshot().buildings.keys()
	ids.sort()
	return ids[0]


func _free_cell() -> Array:
	var snapshot: Dictionary = _bridge.get_snapshot()
	var airlock: Array = _bridge.map_data.base_airlock_cell
	# Search toward +X, away from the lander model that sits on the airlock's -X side.
	for radius in range(2, 8):
		for dz in range(-radius, radius + 1):
			for dx in range(2, radius + 3):
				var cell := [int(airlock[0]) + dx, int(airlock[1]) + dz]
				var result: Dictionary = _bridge.world_service.validate_placement({"definition_id": "fixture_storage_module", "cell": cell, "rotation_quarters": 0}, snapshot)
				if result.valid:
					return cell
	return [int(airlock[0]) + 3, int(airlock[1])]


func _select_option(widget: OptionButton, id: String) -> void:
	for i in widget.item_count:
		if widget.get_item_metadata(i) == id:
			widget.select(i)
			widget.item_selected.emit(i)
			return


func _select_crew(ids: Array) -> void:
	_hud._crew.deselect_all()
	for id in ids:
		for idx in _hud._crew.item_count:
			if _hud._crew.get_item_metadata(idx) == id:
				_hud._crew.select(idx, false)
	_hud._refresh_selection()


func _expedition_done(id: String) -> bool:
	return str(_bridge.get_snapshot().expeditions.get(id, {}).get("status", "")) in ["completed", "failed"]


func _task_status_done(kind: String) -> bool:
	for task in _bridge.get_snapshot().tasks.values():
		if task.kind == kind and task.status not in ["completed", "cancelled", "failed"]:
			return false
	return true


func _all_commissioned() -> bool:
	for building in _bridge.get_snapshot().buildings.values():
		if building.lifecycle == "constructing":
			return false
	return _bridge.get_snapshot().buildings.size() > 5


func _last_building() -> String:
	var ids: Array = _bridge.get_snapshot().buildings.keys()
	ids.sort()
	return ids[-1]


func _stock() -> String:
	var r: Dictionary = _bridge.get_snapshot().resources
	return "alloy %s electronics %s oxygen capacity %s" % [r.alloy.amount, r.electronics.amount, r.oxygen_kg.capacity]


func _conditions() -> Array:
	var result: Array = []
	var b: Dictionary = _bridge.get_snapshot().buildings
	for id in b:
		result.append("%s:%.2f" % [id, b[id].condition])
	return result


func _select_job_kind(prefix: String) -> void:
	var tasks: Dictionary = _bridge.get_snapshot().tasks
	for i in _hud._tasks.item_count:
		var task: Dictionary = tasks.get(_hud._tasks.get_item_metadata(i), {})
		if str(task.get("kind", "")).begins_with(prefix) and task.get("status") not in ["completed", "cancelled", "failed"]:
			_hud._tasks.select(i)
			_hud._refresh_selection()
			return


func _idle_crew() -> Array:
	var result: Array = []
	var crew: Dictionary = _bridge.get_snapshot().crew
	var ids := crew.keys()
	ids.sort()
	for id in ids:
		if crew[id].status == "idle":
			result.append(id)
	return result


func _summaries(collection: String) -> Array:
	var result: Array = []
	var records: Dictionary = _bridge.get_snapshot().get(collection, {})
	var ids := records.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = records[id]
		result.append("%s:%s" % [id, r.get("status", r.get("lifecycle", "?"))])
	return result
