extends PanelContainer
## Read-only snapshot view. Controls send v2 commands through the supplied facade.

const SaveSlot = preload("res://scripts/ui/outpost_save_slot.gd")
const TERMINAL := ["completed", "cancelled", "failed"]
signal crew_selected(crew_id: String)
signal placement_preview(request: Dictionary, result: Dictionary)

var _simulation: RefCounted
var _adapter: RefCounted
var _world: RefCounted
var _catalog: Dictionary = {}
var _save_path := "user://outpost_quick_save.json"
var _state: Dictionary = {}
var _session := ""
var _seq := 0
var _pending: Dictionary = {}
var _tutorial: Dictionary = {}
var _stale := false
var _alert_ids: Array = []
var _hud_title: Label
var _vitals: Label
var _alerts: Label
var _status: Label
var _tutorial_text: Label
var _crew: ItemList
var _crew_text: Label
var _tasks: OptionButton
var _task_text: Label
var _priority: SpinBox
var _resources: Label
var _oxygen_info: Label
var _buildings: OptionButton
var _building_text: Label
var _toggle_building: Button
var _catalog_menu: OptionButton
var _x: SpinBox
var _z: SpinBox
var _rotation: SpinBox
var _build_preview: Label
var _place: Button
var _sites: OptionButton
var _trips: OptionButton
var _work: SpinBox
var _oxygen: SpinBox
var _battery: SpinBox
var _eva_forecast: Label
var _trip_text: Label
var _launch: Button
var _recall: Button
var _audio: AudioStreamPlayer
var _mute: CheckButton
var _tabs: TabContainer
var _save_button: Button
var _load_button: Button

func _refresh_capabilities() -> void:
	var persistence := true
	if _simulation != null and _simulation.has_method("get_capabilities"):
		persistence = _simulation.get_capabilities().get("persistence", false)
	for button in [_save_button, _load_button]:
		if button != null:
			button.disabled = not persistence
			button.tooltip_text = "" if persistence else "Campaign saves will be available in the persistence phase."

func bind(simulation: RefCounted, crew_adapter: RefCounted, world_service: RefCounted,
		building_catalog: Dictionary = {}, save_path: String = "user://outpost_quick_save.json") -> void:
	if _simulation != null:
		_simulation.disconnect("state_changed", _on_snapshot)
		_simulation.disconnect("game_event", _on_event)
	_simulation = simulation
	_adapter = crew_adapter
	_world = world_service
	_catalog = building_catalog.duplicate(true)
	_save_path = save_path
	_state = {}
	_pending.clear()
	_tutorial.clear()
	_alert_ids.clear()
	_reset_session()
	if _simulation == null:
		return
	_simulation.connect("state_changed", _on_snapshot)
	_simulation.connect("game_event", _on_event)
	if is_node_ready():
		_on_snapshot(_simulation.get_snapshot())
		_refresh_capabilities()

func _ready() -> void:
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color.html("#151f2b")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		skin.set_content_margin(side, 16.0)
	add_theme_stylebox_override("panel", skin)
	var body := _column(self)
	_hud_title = _label(body, "MARS OUTPOST   /   MISSION CONTROL", 23)
	var top := _row(body)
	_button(top, "Pause", func(): _time(0))
	_button(top, "1×", func(): _time(1))
	_button(top, "5×", func(): _time(5))
	_button(top, "20×", func(): _time(20))
	_save_button = _button(top, "Quick save", func(): _save_load.call_deferred(false))
	_load_button = _button(top, "Load save", func(): _save_load.call_deferred(true))
	_mute = CheckButton.new()
	_mute.text = "Mute"
	top.add_child(_mute)
	_vitals = _label(body, "Waiting for colony state")
	_alerts = _label(body)
	_alerts.modulate = Color.html("#ffbd91")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)
	var command := _page("Crew & jobs")
	var split := _row(command)
	var roster := _column(split)
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(roster, "Select astronauts (Ctrl / Command or Shift for multiple)", 15)
	_crew = ItemList.new()
	_crew.select_mode = ItemList.SELECT_MULTI
	_crew.custom_minimum_size = Vector2(255, 212)
	roster.add_child(_crew)
	_crew.multi_selected.connect(func(index: int, selected: bool):
		if selected:
			crew_selected.emit(str(_crew.get_item_metadata(index)))
		_refresh_selection())
	_crew_text = _label(roster)
	var jobs := _column(split)
	jobs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(jobs, "Available and recent jobs", 18)
	_tasks = _option(jobs)
	_tasks.item_selected.connect(func(_i: int): _refresh_selection())
	_task_text = _label(jobs)
	_priority = _number(jobs, "Priority", 0, 100, 1, 50)
	_button(jobs, "Suggest available crew", _suggest)
	_button(jobs, "Assign selected crew", _assign)
	_button(jobs, "Cancel selected job", func():
		var id := _selected(_tasks)
		if not id.is_empty():
			_send("cancel_task", {"task_id": id}))
	var resources_page := _page("Life support")
	_resources = _label(resources_page)
	_oxygen_info = _label(resources_page)
	var build := _page("Build")
	_label(build, "Inspect modules", 18)
	_buildings = _option(build)
	_buildings.item_selected.connect(func(_i: int): _refresh_selection())
	_building_text = _label(build)
	_toggle_building = _button(build, "Toggle module", _toggle)
	_label(build, "Place a module", 18)
	_catalog_menu = _option(build)
	_catalog_menu.item_selected.connect(func(_i: int): _preview_build())
	var coords := _row(build)
	_x = _number(coords, "Cell X", 0, 100000, 1, 0)
	_z = _number(coords, "Cell Z", 0, 100000, 1, 0)
	_rotation = _number(coords, "Quarter turns", 0, 3, 1, 0)
	for field in [_x, _z, _rotation]:
		field.value_changed.connect(func(_v: float): _preview_build())
	_build_preview = _label(build)
	_place = _button(build, "Place module", func(): _send("place_building", _placement()))
	var eva := _page("EVA")
	_label(eva, "Plan a salvage trip using the selected astronauts", 18)
	_sites = _option(eva)
	_sites.item_selected.connect(func(_i: int): _preview_eva())
	var supplies := _row(eva)
	_work = _number(supplies, "Work (s)", 1, 100000, 1, 20)
	_oxygen = _number(supplies, "Oxygen / person (kg)", 0, 1000, 0.00001, 0.12)
	_battery = _number(supplies, "Battery / person (kWh)", 0, 1000, 0.00001, 0.006)
	for field in [_work, _oxygen, _battery]:
		field.value_changed.connect(func(_v: float): _preview_eva())
	_eva_forecast = _label(eva)
	_launch = _button(eva, "Launch expedition", func(): _send("start_eva", _eva_request()))
	_label(eva, "Expedition status", 18)
	_trips = _option(eva)
	_trips.item_selected.connect(func(_i: int): _refresh_selection())
	_trip_text = _label(eva)
	_recall = _button(eva, "Recall expedition", func():
		_send("recall_eva", {"expedition_id": _selected(_trips)}))
	var onboarding := _page("Field guide")
	_tutorial_text = _label(onboarding)
	_label(onboarding, "Pause to plan; commands also resolve while paused. Resume at 1×, 5× or 20×. F2 starts training with synthetic values; F3 starts the reference life-support scenario. F1 shows diagnostics. Campaign saves and agriculture are pending.")
	_status = _label(body, "Ready")
	_status.modulate = Color.html("#abd5fa")
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	if _simulation != null:
		_on_snapshot(_simulation.get_snapshot())
	else:
		_refresh_guide()
	_refresh_capabilities()

func select_crew(id: String) -> void:
	if _crew == null:
		return
	for index in range(_crew.item_count):
		if _crew.get_item_metadata(index) == id:
			_crew.select(index)
			_refresh_selection()
			return

func set_placement_cell(cell: Vector2i) -> void:
	if _x != null:
		_x.set_value_no_signal(cell.x)
		_z.set_value_no_signal(cell.y)
		_preview_build()

func _on_snapshot(snapshot: Dictionary) -> void:
	if not is_node_ready() or not snapshot.has("campaign_id"):
		return
	var tick: int = snapshot.clock.tick_index
	if _state.is_empty() or snapshot.campaign_id != _state.campaign_id or snapshot.revision < _state.revision:
		_stale = false
		if not _state.is_empty():
			_pending.clear()
			_tutorial.clear()
			_reset_session()
	elif tick != int(_state.clock.tick_index):
		_stale = false
	elif snapshot.buildings != _state.buildings or snapshot.expeditions != _state.expeditions \
			or snapshot.tasks != _state.tasks:
		_stale = true
	_state = snapshot
	if _simulation != null and _simulation.has_method("get_capabilities"):
		_hud_title.text = "MARS OUTPOST  /  " + ("TRAINING · SYNTHETIC VALUES" if snapshot.campaign_id.begins_with("fixture_") else "REFERENCE LIFE SUPPORT")
	_vitals.text = "SOL CLOCK   %ds   ·   %s     |     %s     |     %s" % [tick,
		"Paused" if snapshot.clock.time_scale == 0 else "%d×" % snapshot.clock.time_scale,
		_quick_resource("oxygen_kg", "O₂"), _quick_resource("food_kcal", "Food")]
	_refresh_roster()
	_fill_options(_tasks, _task_options())
	_fill_options(_buildings, _building_options(snapshot.buildings))
	_fill_options(_catalog_menu, _building_options(_catalog, true))
	_fill_options(_sites, _labels(snapshot.sites))
	_fill_options(_trips, _labels(snapshot.expeditions))
	_refresh_life_support()
	_refresh_selection()
	_refresh_guide()
	_preview_build()

func _quick_resource(id: String, title: String) -> String:
	var resource: Dictionary = _state.resources.get(id, {})
	return "%s %.2f %s" % [title, resource.amount, resource.unit] if not resource.is_empty() else title + " —"

func _refresh_roster() -> void:
	var selected := _selected_crew()
	var ids := _keys(_state.crew)
	if _crew.item_count != ids.size():
		_crew.clear()
		for id in ids:
			var i := _crew.add_item("")
			_crew.set_item_metadata(i, id)
	for i in range(ids.size()):
		var id: String = ids[i]
		var member: Dictionary = _state.crew[id]
		_crew.set_item_metadata(i, id)
		_crew.set_item_text(i, "%s  ·  %s" % [member.display_name, member.status.capitalize()])
		if id in selected:
			_crew.select(i, false)
		else:
			_crew.deselect(i)

func _refresh_selection() -> void:
	if _state.is_empty():
		return
	var details: Array[String] = []
	for id in _selected_crew():
		var c: Dictionary = _state.crew[id]
		var skills: Array[String] = []
		for skill in _keys(c.skills):
			skills.append("%s %d%%" % [skill.capitalize(), roundi(c.skills[skill] * 100)])
		details.append("%s: health %d%% · fatigue %d%% · stress %d%%\n%s" %
			[c.display_name, roundi(c.health * 100), roundi(c.fatigue * 100), roundi(c.stress * 100),
				"  /  ".join(skills)])
	_crew_text.text = "Select an astronaut to inspect their skills." if details.is_empty() else "\n".join(details)
	var task: Dictionary = _state.tasks.get(_selected(_tasks), {})
	_task_text.text = "No jobs available." if task.is_empty() else "%s · %.1f / %.1f work s\n%d / %d crew assigned · priority %d%s" % [
		task.status.capitalize(), task.completed_work_s, task.required_work_s, task.assigned_crew_ids.size(),
		task.crew_required, task.priority, "" if task.blocked_code == null else "\nBlocked: " + _explain(task.blocked_code)]
	var building: Dictionary = _state.buildings.get(_selected(_buildings), {})
	_toggle_building.disabled = building.is_empty() or building.get("lifecycle") == "destroyed"
	_toggle_building.text = "Disable module" if building.get("enabled", false) else "Enable module"
	_building_text.text = "No modules to inspect." if building.is_empty() else "%s · condition %d%% · construction %d%%\n%.2f / %.2f kW served%s" % [
		building.lifecycle.capitalize(), roundi(building.condition * 100), roundi(building.construction_progress * 100),
		building.power_served_kw, building.power_requested_kw, _blockers(building)]
	var trip: Dictionary = _state.expeditions.get(_selected(_trips), {})
	var expedition_job: Dictionary = _state.tasks.get(trip.get("task_id"), {})
	_recall.disabled = trip.is_empty() or trip.get("status") in ["returning", "completed", "failed"]
	var suit_lines: Array[String] = []
	for id in _keys(trip.get("suit_stores", {})):
		var suit: Dictionary = trip.suit_stores[id]
		suit_lines.append("%s: %.5f kg O₂ · %.5f kWh" % [_state.crew[id].display_name, suit.oxygen_kg, suit.battery_kwh])
	_trip_text.text = "No expeditions yet." if trip.is_empty() else "%s · %.1f / %.1f m · work %.1f / %.1f s\nReturn margin: %s · Cargo: %s%s" % [
		trip.status.capitalize(), trip.route_progress_m, trip.route_distance_m, trip.work_completed_s,
		trip.work_required_s, "unavailable" if trip.return_margin_s == null else "%.1f s" % trip.return_margin_s,
		_amounts(trip.cargo), "" if suit_lines.is_empty() else "\n" + "\n".join(suit_lines)]
	if trip.get("status") == "stranded":
		_trip_text.text += "\nReturn route unavailable. Retry recall when the path opens."
	if trip.get("status") == "failed" and expedition_job.get("blocked_code") != null:
		_trip_text.text += "\nFailed: " + _explain(expedition_job.blocked_code)
	_preview_eva()

func _refresh_life_support() -> void:
	var lines: Array[String] = ["Resource rates: " + ("waiting for next tick (stale)" if _stale else "last completed tick")]
	for id in _keys(_state.resources):
		var r: Dictionary = _state.resources[id]
		var rate := 0.0 if absf(r.net_rate_per_s) < 1e-12 else float(r.net_rate_per_s)
		var stock := "%.3f %s available" % [r.amount - r.reserved, r.unit]
		if r.capacity != null:
			stock += " / %.3f total capacity" % r.capacity
		lines.append("%s: %s · %+.6f %s/s%s" % [_resource_name(id), stock, rate, r.unit,
			"" if r.forecast_empty_s == null or id == "co2_kg" else " · %.1f s to empty at this rate" % r.forecast_empty_s])
	var power: Dictionary = _state.power
	lines.append("Power: %.2f kW generated · %.2f / %.2f kW served" %
		[power.generated_kw, power.served_kw, power.requested_kw])
	_resources.text = "\n".join(lines)
	var oxygen: Array[String] = [
		"How oxygen reaches the crew",
		"Power and potable water feed electrolysis. Recycling can replenish potable water; hydrogen needs storage. Crew consume oxygen. CO₂ is a separate hazard and needs scrubbing."
	]
	for id in _keys(_state.buildings):
		var b: Dictionary = _state.buildings[id]
		var d: Dictionary = _catalog.get(b.definition_id, {})
		var outputs: Dictionary = d.get("process", {}).get("outputs_per_s", {})
		var inputs: Dictionary = d.get("process", {}).get("inputs_per_s", {})
		if outputs.has("oxygen_kg") or outputs.has("potable_water_kg") or inputs.has("co2_kg") \
				or d.get("power_generation_kw", 0.0) > 0:
			oxygen.append("%s · %.0f%% operating%s" %
				[d.get("display_name", b.definition_id), b.operating_fraction * 100, _blockers(b)])
	_oxygen_info.text = "\n".join(oxygen)
	var alerts: Array[String] = []
	var ids: Array = []
	var new_warning := false
	for alert in _state.alerts:
		alerts.append("%s: %s" % [alert.severity.capitalize(), alert.message])
		ids.append(alert.id)
		new_warning = new_warning or (alert.id not in _alert_ids and alert.severity != "info")
	_alert_ids = ids
	_alerts.text = "No active alerts" if alerts.is_empty() else "\n".join(alerts.slice(0, 3))
	_alerts.tooltip_text = "\n".join(alerts)
	if new_warning:
		_play("warning")

func _blockers(building: Dictionary) -> String:
	var reasons: Array[String] = []
	for code in building.blocking_codes:
		reasons.append(_explain(code))
	return "" if reasons.is_empty() else "\nReasons: " + ", ".join(reasons)

func _explain(code: String) -> String:
	var arg := code.get_slice(":", 1)
	match code.get_slice(":", 0):
		"no_power": return "No power reaching this module"
		"partial_power": return "Only part of the requested power is available"
		"input_limited": return "Needs more " + _resource_name(arg)
		"output_full": return "Storage full for " + _resource_name(arg)
		"event_modifier": return "Affected by " + arg
		"unmet_needs": return "Crew needs were not met"
		"reserve_insufficient": return "Suit reserves exhausted or insufficient"
		"route_unreachable": return "No route to destination"
	return code.replace("_", " ").capitalize()

func _resource_name(id: String) -> String:
	return str({"oxygen_kg": "Oxygen", "co2_kg": "Carbon dioxide", "food_kcal": "Food",
		"energy_kwh": "Battery energy", "potable_water_kg": "Potable water",
		"wastewater_kg": "Wastewater", "raw_water_kg": "Raw water", "hydrogen_kg": "Hydrogen"}.get(id, id.capitalize()))

func _amounts(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for id in _keys(amounts):
		parts.append("%s %s" % [str(amounts[id]), _resource_name(id)])
	return "none" if parts.is_empty() else ", ".join(parts)

func _preview_build() -> void:
	var request := _placement()
	var definition: Dictionary = _catalog.get(request.definition_id, {})
	var result := {"valid": false, "reason": "Placement preview is unavailable."}
	if _world != null and _world.has_method("validate_placement") and not definition.is_empty() and not _state.is_empty():
		result = _world.validate_placement(request, _state)
	if result.valid:
		if _simulation != null and _simulation.has_method("supports_building") and not _simulation.supports_building(request.definition_id):
			result = {"valid": false, "reason": "This module's production rules are not available yet."}
		for id in _keys(definition.get("build_cost", {})):
			var account: Dictionary = _state.resources.get(id, {})
			if account.is_empty() or float(account.amount) - float(account.reserved) < float(definition.build_cost[id]):
				result = result.duplicate()
				result.valid = false
				result.reason = "Not enough " + _resource_name(id) + "."
				break
	_build_preview.text = ("Ready to place. " if result.valid else result.reason + " ") + "Cost: " + _amounts(definition.get("build_cost", {}))
	_place.disabled = not result.valid
	placement_preview.emit(request, result)

func _placement() -> Dictionary:
	return {"definition_id": _selected(_catalog_menu), "cell": [int(_x.value), int(_z.value)],
		"rotation_quarters": int(_rotation.value)}

func _eva_request() -> Dictionary:
	return {"site_id": _selected(_sites), "crew_ids": _selected_crew(), "work_duration_s": _work.value,
		"oxygen_kg_per_crew": _oxygen.value, "battery_kwh_per_crew": _battery.value}

func _preview_eva() -> void:
	var r := {"ok": false, "reason": "Select available crew and a salvage site."}
	if _adapter != null and not _state.is_empty() and not _selected_crew().is_empty() and not _selected(_sites).is_empty():
		r = _adapter.estimate_eva(_eva_request(), _state)
	var lines: Array[String] = ["Ready to launch" if r.ok else r.reason]
	if r.has("seconds"):
		lines.append("Per astronaut · emergency reserve %.0f%% of loaded supplies" % (r.reserve_fraction * 100))
		for phase in ["outbound", "working", "returning"]:
			var planned: Dictionary = r.phase_use[phase]
			lines.append("%s: %.0f s · %.5f kg O₂ · %.5f kWh" %
				[phase.capitalize(), r.seconds[phase], planned.oxygen_kg, planned.battery_kwh])
		lines.append("Expected at return: %.5f kg O₂ · %.5f kWh   |   Minimum load: %.5f kg O₂ · %.5f kWh" %
			[r.remaining.oxygen_kg, r.remaining.battery_kwh, r.minimum.oxygen_kg, r.minimum.battery_kwh])
	_eva_forecast.text = "\n".join(lines)
	_launch.disabled = not r.ok

func _assign() -> void:
	var id := _selected(_tasks)
	if id.is_empty() or _selected_crew().is_empty():
		_status.text = "Select a job and the astronauts who should work it."
		return
	_send("assign_task", {"task_id": id, "crew_ids": _selected_crew(), "priority": int(_priority.value)})

func _suggest() -> void:
	var id := _selected(_tasks)
	if id.is_empty() or _adapter == null:
		return
	var task: Dictionary = _state.tasks[id]
	var candidates: Array = _adapter.recommended_crew(task, _state)
	_crew.deselect_all()
	for i in range(mini(candidates.size(), int(task.crew_required) - task.assigned_crew_ids.size())):
		for idx in range(_crew.item_count):
			if _crew.get_item_metadata(idx) == candidates[i]:
				_crew.select(idx, false)
	_refresh_selection()

func _toggle() -> void:
	var id := _selected(_buildings)
	_send("set_building_enabled", {"building_id": id, "enabled": not _state.buildings[id].enabled})

func _time(scale_value: int) -> void:
	_send("set_time_scale", {"time_scale": scale_value})

func _send(type: String, payload: Dictionary) -> void:
	if _simulation == null:
		_status.text = "The colony controls are not connected."
		return
	_seq += 1
	var id := "%s:%06d" % [_session, _seq]
	var result: Dictionary = _simulation.submit_command({"contract_version": "2.0.0",
		"command_id": id, "type": type, "payload": payload})
	if result.accepted:
		_pending[id] = type
		_status.text = "Queued: " + _explain(type)
	else:
		_status.text = result.reason
		_play("warning")

func _on_event(event: Dictionary) -> void:
	if event.type == "command_result" and _pending.has(event.data.command_id):
		var type: String = _pending[event.data.command_id]
		_pending.erase(event.data.command_id)
		_status.text = _explain(type) + " accepted." if event.data.success else event.data.reason
		if event.data.success:
			_tutorial[type] = true
			_refresh_guide()
		_play("confirm" if event.data.success else "warning")
	elif event.type in ["building_commissioned", "eva_returned", "task_completed"]:
		_status.text = _explain(event.type)
		_play("confirm")

func _save_load(load_game: bool) -> void:
	if _simulation == null:
		return
	var result := SaveSlot.load_slot(_simulation, _save_path) if load_game else SaveSlot.save(_simulation, _save_path)
	_status.text = ("Save loaded." if load_game else "Colony saved.") if result.ok else result.reason
	if result.ok and load_game:
		_pending.clear()
		_tutorial.clear()
		_reset_session()
		_stale = false
		_on_snapshot(_simulation.get_snapshot())
	_play("confirm" if result.ok else "warning")

func _play(id: String) -> void:
	if _mute.button_pressed or DisplayServer.get_name() == "headless":
		return
	_audio.stream = load("res://assets/audio/outpost_" + id + ".wav")
	if _audio.stream != null:
		_audio.play()

func _reset_session() -> void:
	_session = "hud_" + Crypto.new().generate_random_bytes(12).hex_encode()
	_seq = 0

func _refresh_guide() -> void:
	_tutorial_text.text = "FIRST SHIFT\n\n%s\n\n%s\n\n%s\n\n%s" % [
		_guide("start_eva", "Training: select two idle astronauts in Crew & jobs, open EVA, check supplies and launch. Salvage brings the materials needed to build."),
		_guide("place_building", "Build: pick a module and open cell. Place it, then assign crew to the construction job."),
		_guide("assign_task", "Crew & jobs: choose the construction job, suggest available crew, then assign. Watch work finish and the module come online."),
		_guide("recall_eva", "EVA: pick the active expedition and recall it. Watch for return route warnings.")]

func _guide(key: String, detail: String) -> String:
	return ("✓  " if _tutorial.has(key) else "○  ") + detail

func _task_options() -> Dictionary:
	var keys := _keys(_state.tasks)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var first: Dictionary = _state.tasks[a]
		var second: Dictionary = _state.tasks[b]
		if (first.status in TERMINAL) != (second.status in TERMINAL):
			return first.status not in TERMINAL
		return a < b if first.priority == second.priority else first.priority > second.priority)
	var result := {}
	for id in keys:
		var t: Dictionary = _state.tasks[id]
		var b: Dictionary = _state.buildings.get(t.target_id, {})
		var target: String = _catalog.get(b.get("definition_id"), {}).get("display_name", t.target_id)
		result[id] = "%s · %s · %s" % [t.kind.capitalize(), target, t.status.capitalize()]
	return result

func _building_options(records: Dictionary, is_catalog: bool = false) -> Dictionary:
	var result := {}
	for id in _keys(records):
		var b: Dictionary = records[id]
		result[id] = b.get("display_name", id) if is_catalog else "%s · %s" % [
			_catalog.get(b.definition_id, {}).get("display_name", b.definition_id), id]
	return result

func _labels(records: Dictionary) -> Dictionary:
	var result := {}
	for id in _keys(records):
		result[id] = "%s · %s" % [id, records[id].status.capitalize()] if records[id].has("status") else id
	return result

func _fill_options(widget: OptionButton, items: Dictionary) -> void:
	var keep := _selected(widget)
	var keys := items.keys()
	var matches := widget.item_count == keys.size()
	if matches:
		for i in range(keys.size()):
			if widget.get_item_metadata(i) != keys[i]:
				matches = false
				break
	if not matches:
		widget.clear()
		for id in keys:
			widget.add_item(items[id])
			widget.set_item_metadata(widget.item_count - 1, id)
		if items.has(keep):
			widget.select(keys.find(keep))
		elif not keys.is_empty():
			widget.select(0)
	else:
		for i in range(keys.size()):
			widget.set_item_text(i, items[keys[i]])

func _selected(widget: OptionButton) -> String:
	return "" if widget.selected < 0 else str(widget.get_item_metadata(widget.selected))

func _selected_crew() -> Array:
	var ids: Array = []
	for i in _crew.get_selected_items():
		ids.append(_crew.get_item_metadata(i))
	return ids

func _keys(records: Dictionary) -> Array:
	var ids := records.keys()
	ids.sort()
	return ids

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	_tabs.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(pad)
	return _column(pad)

func _column(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	return box

func _row(parent: Node) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	return box

func _label(parent: Node, value: String = "", size_px: int = 15) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size_px)
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _option(parent: Node) -> OptionButton:
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	parent.add_child(option)
	return option

func _number(parent: Node, title: String, low: float, high: float, step: float, initial: float) -> SpinBox:
	var group := _column(parent)
	_label(group, title, 14)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = initial
	input.get_line_edit().custom_minimum_size.x = 100
	group.add_child(input)
	return input
