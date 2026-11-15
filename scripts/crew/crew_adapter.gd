extends RefCounted
## Contract v2. The dispatcher owns IDs, state, labor completion and ledger commits.

const Jobs = preload("res://scripts/tasks/crew_jobs.gd")
const Routes = preload("res://scripts/crew/crew_routes.gd")
const Eva = preload("res://scripts/tasks/eva_planner.gd")
const Record = preload("res://scripts/crew/crew_save_record.gd")
const VERSION := "2.0.0"

var _world: RefCounted
var _crew_defs: Dictionary = {}
var _building_defs: Dictionary = {}
var _templates: Dictionary = {}
var _hazard_rules: Dictionary = {}
var _eva_enabled := false
var _eva: RefCounted

func _init(world_service: RefCounted = null) -> void:
	_world = world_service

func initialize(config: Dictionary, snapshot: Dictionary) -> Dictionary:
	var manifest: Dictionary = config.get("definition_manifest", {})
	var scenario := _read(config.get("scenario_path", ""), manifest)
	var science := _read(config.get("science_config_path", ""), manifest)
	var map := _read(scenario.get("map_path", ""), manifest)
	var crew := _read(scenario.get("crew_definition_path", ""), manifest)
	var templates := _read(scenario.get("task_template_path", ""), manifest)
	if scenario.is_empty() or science.is_empty() or map.is_empty() or crew.is_empty() or templates.is_empty():
		return _result(false, "definition_mismatch", "Missing or changed scenario, map, crew, task or science definition.")
	var defs := {}
	for definition in crew.get("definitions", []):
		var id: String = definition.get("id", "")
		var caps: Dictionary = definition.get("suit_capacity", {})
		if id.is_empty() or defs.has(id) or not Record.number(definition.get("movement_speed_m_per_s"), 1e-9) \
				or not Record.number(caps.get("oxygen_kg"), 0.0) or not Record.number(caps.get("battery_kwh"), 0.0) \
				or not Record.whole(definition.get("carry_capacity_count"), 0):
			return _result(false, "invalid_schema", "Invalid crew capability definition: " + id)
		defs[id] = definition
	var ids: Array = config.get("initial_crew_definition_ids", [])
	if ids.size() < 5 or ids.size() > 9 or snapshot.get("crew", {}).size() != ids.size():
		return _result(false, "invalid_schema", "The initial roster must contain five to nine crew.")
	for id in ids:
		if not defs.has(id):
			return _result(false, "unknown_definition", "Unknown initial crew definition: " + id)
	for member in snapshot.crew.values():
		if not defs.has(member.get("definition_id")):
			return _result(false, "unknown_definition", "Roster references an unknown crew definition.")
	var buildings := {}
	for path in scenario.get("building_definition_paths", []):
		var definition := _read(path, manifest)
		if not definition.has("id"):
			return _result(false, "definition_mismatch", "Building definition could not be read: " + path)
		buildings[definition.id] = definition
	var policy: Dictionary = science.get("eva_policy", {})
	var rates: Dictionary = science.get("crew_metabolism", {}).get("eva_suit_rates_per_s", {})
	var airlock: Variant = map.get("base_airlock_cell")
	if not Record.number(policy.get("reserve_fraction"), 0.0, 1.0) or policy.reserve_fraction >= 1.0 \
			or not Record.number(rates.get("oxygen_kg"), 0.0) or not Record.number(rates.get("battery_kwh"), 0.0) \
			or not airlock is Array or airlock.size() != 2:
		return _result(false, "invalid_schema", "EVA policy, suit rates and airlock are required.")
	for phase in policy.get("phase_rates_per_s", {}):
		if phase not in ["outbound", "working", "returning", "stranded"]:
			return _result(false, "invalid_schema", "Unknown EVA workload phase.")
		for store in policy.phase_rates_per_s[phase]:
			if not rates.has(store) or not Record.number(policy.phase_rates_per_s[phase][store], 0.0):
				return _result(false, "invalid_schema", "Invalid suit workload rate.")
	var job_config: Dictionary = templates.get("templates", {})
	for kind in ["construct", "repair", "farm"]:
		var template: Dictionary = job_config.get(kind, {})
		if not Record.whole(template.get("crew_required", 1), 1, 9) \
				or not Record.whole(template.get("default_priority", 50), 0, 100) \
				or not Record.number(template.get("labor_rate_work_s_per_crew_s", 1.0), 0.0) \
				or not Record.number(template.get("skill_weight", 0.0), 0.0):
			return _result(false, "invalid_schema", "Invalid job template: " + kind)
	_crew_defs = defs
	_building_defs = buildings
	_templates = job_config
	_hazard_rules = science.get("crew_hazard_responses", {})
	_eva_enabled = science.crew_metabolism.get("eva_supported", true)
	_eva = Eva.new()
	_eva.world = _world
	_eva.airlock = airlock
	_eva.definitions = defs
	_eva.rates = rates
	_eva.policy = policy
	return _result(true)

func _read(path: String, manifest: Dictionary) -> Dictionary:
	if not path.begins_with("res://") or not manifest.has(path) \
			or FileAccess.get_sha256(path) != manifest[path]:
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary and data.get("schema_version") == 1 else {}

func get_task_template(kind: String, work_s: float) -> Dictionary:
	return Jobs.template(_templates, kind, work_s)

func recommended_crew(task: Dictionary, snapshot: Dictionary) -> Array:
	var ids: Array = []
	for id in Jobs.sorted_ids(snapshot.crew):
		if Jobs.idle(snapshot.crew[id]) and _can_reach(snapshot, snapshot.crew[id], task):
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var first := Jobs.productivity(snapshot.crew[a], task.kind, _templates)
		var second := Jobs.productivity(snapshot.crew[b], task.kind, _templates)
		return a < b if first == second else first > second)
	return ids

func plan_tick(snapshot: Dictionary, dt_s: float, context: Dictionary) -> Dictionary:
	var p := _proposal()
	if _eva == null:
		return p
	Jobs.plan(snapshot, p, dt_s, context, _world, _building_defs, _crew_defs, _templates)
	if context.phase == "progress":
		_eva.plan(snapshot, p, dt_s, context)
	return p

func evaluate_hazards(snapshot: Dictionary, hazards: Array) -> Dictionary:
	var p := _proposal()
	for hazard in hazards:
		var id: String = hazard.crew_id
		if not snapshot.crew.has(id):
			continue
		var member: Dictionary = p.crew_updates.get(id, snapshot.crew[id]).duplicate(true)
		if member.status == "dead":
			continue
		var rule: Dictionary = _hazard_rules.get(hazard.code, {})
		member.radiation_dose_msv += maxf(0.0, hazard.dose_msv)
		member.health = clampf(member.health - float(rule.get("health_loss_per_s", 0.0)) * hazard.exposure_s, 0.0, 1.0)
		member.stress = clampf(member.stress + float(rule.get("stress_gain_per_s", 0.0)) * hazard.exposure_s, 0.0, 1.0)
		if member.health <= 0.0:
			member.status = "dead" if rule.get("fatal_at_zero", false) else "incapacitated"
			if member.expedition_id != null and snapshot.expeditions.has(member.expedition_id):
				var trip: Dictionary = snapshot.expeditions[member.expedition_id].duplicate(true)
				if trip.status not in Eva.TERMINAL:
					_eva.fail(trip, snapshot, p, "crew_unavailable")
					p.expedition_updates[trip.id] = trip
		if member != snapshot.crew[id]:
			p.crew_updates[id] = member
	return p

func estimate_eva(payload: Dictionary, snapshot: Dictionary) -> Dictionary:
	if _eva == null or not _eva_enabled:
		return _result(false, "module_unavailable", "EVA supplies and workload are not configured for this scenario.")
	if not _valid_crew_ids(payload.get("crew_ids")) or not payload.get("site_id") is String \
			or not Record.number(payload.get("work_duration_s"), 0.0) or payload.work_duration_s <= 0.0 \
			or not Record.number(payload.get("oxygen_kg_per_crew"), 0.0) \
			or not Record.number(payload.get("battery_kwh_per_crew"), 0.0):
		return _result(false, "invalid_value", "Choose a site, crew, positive work duration, and valid suit loads.")
	return _eva.forecast(payload, snapshot)

func apply_command(command: Dictionary, snapshot: Dictionary) -> Dictionary:
	var p := _proposal(true)
	if _eva == null:
		return _reject(p, "module_unavailable", "The crew adapter is not initialized.")
	var payload: Dictionary = command.payload
	match command.type:
		"place_building":
			var building: Dictionary = _building_defs.get(payload.definition_id, {})
			if building.is_empty():
				return _reject(p, "unknown_definition", "Building definition not found.")
			var template := get_task_template("construct", building.construction_work_s)
			p.task_updates["new_task"] = {"id": "new_task", "kind": "construct", "target_id": "new_building",
				"status": "queued", "priority": template.priority, "crew_required": template.crew_required,
				"assigned_crew_ids": [], "required_work_s": template.required_work_s,
				"completed_work_s": 0.0, "blocked_code": null, "expedition_id": null}
			p.result_data = {"building_id": "new_building", "task_id": "new_task"}
		"assign_task", "cancel_task":
			return _job_command(command.type, payload, snapshot, p)
		"start_eva":
			var estimate := estimate_eva(payload, snapshot)
			p.result_data = {"site_id": payload.get("site_id", "")}
			if not estimate.ok:
				return _reject(p, estimate.code, estimate.reason)
			return _eva.start(payload, snapshot, p)
		"recall_eva":
			return _eva.recall(payload.expedition_id, snapshot, p)
		_:
			return _reject(p, "unsupported_command", "The crew adapter does not own this command.")
	return p

func _job_command(type: String, payload: Dictionary, snapshot: Dictionary, p: Dictionary) -> Dictionary:
	var id: String = payload.task_id
	p.result_data = {"task_id": id}
	if not snapshot.tasks.has(id):
		return _reject(p, "unknown_entity", "Task not found.")
	var job: Dictionary = snapshot.tasks[id].duplicate(true)
	if job.kind == "eva" or job.status in Jobs.TERMINAL:
		return _reject(p, "not_cancellable" if type == "cancel_task" else "invalid_state",
			"Recall expedition jobs; finished tasks cannot be changed.")
	if type == "cancel_task":
		for cid in job.assigned_crew_ids:
			if snapshot.crew[cid].task_id == id:
				p.crew_updates[cid] = Jobs.release(snapshot.crew[cid])
		job.assigned_crew_ids.clear()
		job.status = "cancelled"
		job.blocked_code = null
	else:
		var ids: Array = payload.crew_ids.duplicate()
		if not _valid_crew_ids(ids) or not Record.whole(payload.priority, 0, 100):
			return _reject(p, "invalid_value", "Choose unique astronauts and a priority from 0 to 100.")
		var problem := Jobs.assignment_problem(snapshot, job)
		if not problem.is_empty():
			return _reject(p, problem, "The target building cannot accept this job.")
		if ids.size() + job.assigned_crew_ids.size() > int(job.crew_required):
			return _reject(p, "crew_unavailable", "The job has fewer open slots than selected crew.")
		ids.sort()
		for cid in ids:
			if not snapshot.crew.has(cid):
				return _reject(p, "unknown_entity", "Astronaut not found: " + cid)
			if not Jobs.idle(snapshot.crew[cid]):
				return _reject(p, "crew_unavailable", snapshot.crew[cid].display_name + " is not available.")
			if not _can_reach(snapshot, snapshot.crew[cid], job):
				return _reject(p, "route_unreachable", "No route to a job entrance for " + snapshot.crew[cid].display_name + ".")
		for cid in ids:
			var member: Dictionary = snapshot.crew[cid].duplicate(true)
			member.task_id = id
			member.status = "travelling"
			p.crew_updates[cid] = member
		job.assigned_crew_ids.append_array(ids)
		job.assigned_crew_ids.sort()
		job.priority = int(payload.priority)
		p.result_data.crew_ids = ids
	p.task_updates[id] = job
	return p

func _can_reach(snapshot: Dictionary, member: Dictionary, job: Dictionary) -> bool:
	if not Jobs.assignment_problem(snapshot, job).is_empty():
		return false
	var building: Dictionary = snapshot.buildings[job.target_id]
	return Routes.to_building(_world, snapshot, member.position_m, building,
		_building_defs.get(building.definition_id, {})).get("reachable", false)

func _valid_crew_ids(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 9:
		return false
	var seen := {}
	for id in value:
		if not id is String or id.is_empty() or seen.has(id):
			return false
		seen[id] = true
	return true

func _proposal(command: bool = false) -> Dictionary:
	var p := {"crew_updates": {}, "task_updates": {}, "expedition_updates": {},
		"labor": [], "resource_requests": [], "events": [],
		"private_record_replacements": {"completion_markers": {}, "private_counters": {}}}
	if command:
		p.merge(_result(true))
		p.result_data = {}
	return p

func _reject(proposal: Dictionary, code: String, reason: String) -> Dictionary:
	proposal.merge(_result(false, code, reason), true)
	return proposal

func _result(ok: bool, code: String = "ok", reason: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "reason": reason}

func export_state(crew_tasks_state: Dictionary) -> Dictionary:
	return {"schema_version": 1, "state": crew_tasks_state.duplicate(true)}

func validate_state(record: Dictionary, candidate_core_state: Dictionary) -> Dictionary:
	return Record.validate(record, candidate_core_state, _crew_defs)

func restore_state(_record: Dictionary) -> void:
	pass # No derived state from the authoritative partition is cached.
