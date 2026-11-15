extends RefCounted
## Disposable, deterministic harness. No production code depends on this facade.
## Drives just enough of the contract to exercise player controls and adapter proposals.

const FixtureWorld = preload("res://tests/crew_ui/fixture_world.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const FILES := "res://tests/simulation/fixtures/"
const TERMINAL := ["completed", "failed", "cancelled"]

signal state_changed(snapshot: Dictionary)
signal game_event(event: Dictionary)
signal command_resolved(command_id: String, success: bool, reason: String)

var world := FixtureWorld.new()
var adapter := Adapter.new(world)
var state: Dictionary
var config: Dictionary
var catalog: Dictionary
var journal: Dictionary = {}
var queue: Array = []
var effects: Dictionary = {}
var prepaid: Dictionary = {}
var caches: Dictionary = {}
var counters := {"task": 0, "expedition": 0, "building": 5, "event": 0}
var accumulator := 0.0
var _scalars: Dictionary

func open(size: int = 6, variant: String = "salvage_6crew") -> Dictionary:
	config = read("init/" + variant + ".json")
	state = read("snapshots/" + variant + "_tick0.json")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.scenario_path))
	catalog = {}
	for path in scenario.building_definition_paths:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		catalog[d.id] = d
	world.catalog = catalog
	_scalars = JSON.parse_string(FileAccess.get_file_as_string(config.science_config_path))
	while state.crew.size() > size:
		state.crew.erase(state.crew.keys().back())
		config.initial_crew_definition_ids.pop_back()
	while state.crew.size() < size:
		var n: int = state.crew.size()
		var member: Dictionary = state.crew.values()[0].duplicate(true)
		member.id = "crew_%06d" % (n + 1)
		member.definition_id = "fixture_crew_" + String.chr(97 + n)
		member.display_name = "Fixture Crew " + String.chr(65 + n)
		state.crew[member.id] = member
		config.initial_crew_definition_ids.append(member.definition_id)
	return adapter.initialize(config, state)

func read(relative: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FILES + relative))

func get_snapshot() -> Dictionary:
	return state.duplicate(true)

func submit_command(command: Dictionary) -> Dictionary:
	var id: String = command.command_id
	if journal.has(id):
		return {"accepted": false, "reason": "Fixture command ID already used."}
	if command.contract_version != "2.0.0" or command.type not in ["assign_task", "cancel_task",
			"place_building", "set_building_enabled", "start_eva", "recall_eva", "set_time_scale"]:
		return {"accepted": false, "reason": "Unsupported fixture command."}
	journal[id] = command.duplicate(true)
	queue.append(id)
	return {"accepted": true, "reason": ""}

func advance(delta: float) -> void:
	if not queue.is_empty():
		process_pending_commands()
	accumulator += delta * state.clock.time_scale
	for i in range(mini(120, floori(accumulator))):
		if state.clock.time_scale == 0:
			break
		step()
		accumulator -= 1.0

func process_pending_commands() -> void:
	var commands := queue.duplicate()
	queue.clear()
	for id in commands:
		var command: Dictionary = journal[id]
		var result := _resolve(command)
		var data: Dictionary = result.get("result_data", {}).duplicate()
		data.merge({"command_id": id, "success": result.ok, "reason": result.reason, "code": result.code})
		_emit("command_result", data)
		command_resolved.emit(id, result.ok, result.reason)
		if result.ok:
			state.revision += 1
			for event in result.get("events", []):
				_emit(event.type, event.data, event.entity_ids)
	if not commands.is_empty():
		state_changed.emit(get_snapshot())

func _resolve(command: Dictionary) -> Dictionary:
	var p: Dictionary
	match command.type:
		"set_time_scale":
			if command.payload.time_scale not in [0, 1, 5, 20]:
				return result(false, "invalid_value", "Invalid time scale.")
			state.clock.time_scale = command.payload.time_scale
			return result()
		"set_building_enabled":
			var b: Dictionary = state.buildings.get(command.payload.building_id, {})
			if b.is_empty():
				return result(false, "unknown_entity", "Module not found.")
			b.enabled = command.payload.enabled
			return result()
		"place_building":
			var placement := world.validate_placement(command.payload, state)
			if not placement.valid:
				return result(false, placement.code, placement.reason)
			p = adapter.apply_command(command, state)
			if not p.ok:
				return p
			var d: Dictionary = catalog[command.payload.definition_id]
			for id in d.build_cost:
				if state.resources[id].amount < d.build_cost[id]:
					return result(false, "insufficient_resources", "Not enough materials.")
			var building := _allocate("building")
			var task := _allocate("task")
			p = _substitute(p, {"new_building": building, "new_task": task})
			state.buildings[building] = {"id": building, "definition_id": d.id, "cell": command.payload.cell,
				"rotation_quarters": command.payload.rotation_quarters, "lifecycle": "constructing",
				"enabled": true, "condition": 1.0, "construction_task_id": task, "construction_progress": 0.0,
				"power_requested_kw": 0.0, "power_served_kw": 0.0, "operating_fraction": 0.0,
				"blocking_codes": ["constructing"]}
			for id in d.build_cost:
				state.resources[id].amount -= d.build_cost[id]
			prepaid[task] = d.build_cost.duplicate(true)
		_:
			p = adapter.apply_command(command, state)
			if not p.ok:
				return p
			if command.type == "start_eva":
				p = _substitute(p, {"new_task": _allocate("task"), "new_expedition": _allocate("expedition")})
			if command.type == "cancel_task" and prepaid.has(command.payload.task_id):
				var task_id: String = command.payload.task_id
				for id in prepaid[task_id]:
					var r: Dictionary = state.resources[id]
					if r.capacity != null and r.amount + prepaid[task_id][id] > r.capacity:
						return result(false, "capacity_exceeded", "Make space for the material refund.")
				for id in prepaid[task_id]:
					state.resources[id].amount += prepaid[task_id][id]
				prepaid.erase(task_id)
				state.buildings.erase(state.tasks[task_id].target_id)
	_commit(p)
	return p

func step() -> void:
	process_pending_commands()
	if state.clock.time_scale == 0:
		return
	var before: Dictionary = state.resources.duplicate(true)
	# A working proxy farm is powered in the fixture. Real dispatch is Task 01.
	for b in state.buildings.values():
		b.operating_fraction = 1.0 if b.enabled and b.lifecycle == "commissioned" else 0.0
	var ctx := {"phase": "intent", "tick_index": int(state.clock.tick_index), "unmet_needs": {}}
	_commit(adapter.plan_tick(state, 0.0, ctx))
	ctx.phase = "progress"
	var rates: Dictionary = _scalars.crew_metabolism.eva_suit_rates_per_s
	for trip in state.expeditions.values():
		if trip.status in TERMINAL:
			continue
		for id in trip.crew_ids:
			for key in rates:
				if trip.suit_stores[id][key] + 1e-10 < rates[key]:
					if not ctx.unmet_needs.has(id):
						ctx.unmet_needs[id] = []
					ctx.unmet_needs[id].append("oxygen" if key == "oxygen_kg" else "suit_energy")
				trip.suit_stores[id][key] = maxf(0.0, trip.suit_stores[id][key] - rates[key])
	var p: Dictionary = adapter.plan_tick(state, 1.0, ctx)
	_commit(p)
	for item in p.labor:
		_apply_labor(item)
	for event in p.events:
		_emit(event.type, event.data, event.entity_ids)
	state.clock.tick_index += 1
	state.clock.elapsed_s += 1.0
	state.revision += 1
	for id in before:
		var r: Dictionary = state.resources[id]
		r.net_rate_per_s = float(r.amount) - float(before[id].amount)
		r.forecast_empty_s = r.amount / -r.net_rate_per_s if r.net_rate_per_s < -1e-12 else null
	state_changed.emit(get_snapshot())

func add_job(kind: String, building_id: String, work: float) -> String:
	var t: Dictionary = adapter.get_task_template(kind, work)
	var id := _allocate("task")
	t.merge({"id": id, "target_id": building_id, "status": "queued", "assigned_crew_ids": [],
		"completed_work_s": 0.0, "blocked_code": null, "expedition_id": null})
	state.tasks[id] = t
	return id

func _apply_labor(item: Dictionary) -> void:
	var t: Dictionary = state.tasks[item.task_id]
	if t.status in TERMINAL:
		return
	t.completed_work_s = minf(t.required_work_s, t.completed_work_s + item.work_s)
	if t.completed_work_s < t.required_work_s:
		return
	t.status = "completed"
	var b: Dictionary = state.buildings[t.target_id]
	match t.kind:
		"construct":
			b.lifecycle = "commissioned"
			b.construction_progress = 1.0
			b.construction_task_id = null
			b.blocking_codes = []
			prepaid.erase(t.id)
			_emit("building_commissioned", {"building_id": b.id})
		"repair":
			b.condition = 1.0
		"farm":
			var food: Dictionary = state.resources.food_kcal
			food.amount = minf(food.capacity, food.amount + 100.0)
	_emit("task_completed", {"task_id": t.id})

func _commit(p: Dictionary) -> void:
	state.crew.merge(p.crew_updates.duplicate(true), true)
	state.tasks.merge(p.task_updates.duplicate(true), true)
	state.expeditions.merge(p.expedition_updates.duplicate(true), true)
	for id in p.expedition_updates:
		var t: Dictionary = state.expeditions[id]
		state.tasks[t.task_id].completed_work_s = t.work_completed_s
		state.sites[t.site_id].reserved_by_expedition_id = null if t.status in TERMINAL else id
	for req in p.resource_requests:
		if effects.has(req.effect_id):
			continue
		for path in req.debits:
			_move(path, -float(req.debits[path]))
		for path in req.credits:
			_move(path, req.credits[path])
		effects[req.effect_id] = true

func _move(path: String, delta: float) -> void:
	var parts := path.split("/")
	match parts[0]:
		"base": state.resources[parts[1]].amount += delta
		"suit": state.expeditions[parts[1]].suit_stores[parts[2]][parts[3]] += delta
		"site": _balance(state.sites[parts[1]].remaining_cargo, parts[2], delta)
		"cargo": _balance(state.expeditions[parts[1]].cargo, parts[2], delta)
		"return_cache":
			if not caches.has(parts[1]):
				caches[parts[1]] = {}
			_balance(caches[parts[1]], parts[2], delta)
		"loss": pass

func _balance(account: Dictionary, key: String, delta: float) -> void:
	account[key] = float(account.get(key, 0.0)) + delta
	if absf(account[key]) < 1e-10:
		account.erase(key)

func _allocate(kind: String) -> String:
	counters[kind] += 1
	return "%s_%06d" % [kind, counters[kind]]

func _substitute(value: Variant, replacements: Dictionary) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value:
			out[_substitute(key, replacements)] = _substitute(value[key], replacements)
		return out
	if value is Array:
		return value.map(func(item: Variant): return _substitute(item, replacements))
	if value is String or value is StringName:
		value = str(value)
		for alias in replacements:
			value = value.replace(alias, replacements[alias])
	return value

func _emit(type: String, data: Dictionary, ids: Array = []) -> void:
	game_event.emit({"id": _allocate("event"), "type": type, "tick_index": state.clock.tick_index,
		"entity_ids": ids, "data": data})

func result(ok: bool = true, code: String = "ok", reason: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "reason": reason}

func export_save() -> Dictionary:
	# Deliberately distinguish harness saves from actual game saves.
	return {"format": "crew-ui-test-save", "snapshot": get_snapshot(), "counters": counters.duplicate(),
		"accumulator": accumulator, "queue": queue.duplicate(), "journal": journal.duplicate(true),
		"effects": effects.duplicate(), "prepaid": prepaid.duplicate(true),
		"crew_record": adapter.export_state({"crew": state.crew, "tasks": state.tasks, "expeditions": state.expeditions,
			"return_caches": caches, "completion_markers": {}, "private_counters": {}})}

func import_save(save: Dictionary) -> Dictionary:
	if save.get("format") != "crew-ui-test-save":
		return result(false, "invalid_save", "This is not a crew harness save.")
	var r: Dictionary = adapter.validate_state(save.crew_record, save.snapshot)
	if not r.ok:
		return r
	state = save.snapshot.duplicate(true)
	for key in ["crew", "tasks", "expeditions"]:
		state[key] = save.crew_record.state[key].duplicate(true)
	caches = save.crew_record.state.return_caches.duplicate(true)
	counters = save.counters.duplicate()
	queue = save.queue.duplicate()
	journal = save.journal.duplicate(true)
	effects = save.effects.duplicate()
	prepaid = save.prepaid.duplicate(true)
	accumulator = save.accumulator
	adapter.restore_state(save.crew_record)
	state_changed.emit(get_snapshot())
	return result()
