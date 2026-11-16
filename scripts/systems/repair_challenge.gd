extends RefCounted
## Simulation-owned corrective repair challenges. The UI only sends inputs; every
## puzzle is generated from the simulation RNG and judged here. A failed attempt sets
## the component to zero condition and locks its corrective repair for one mission day.
## Game mechanic, not an engineering model.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const COMMANDS = ["trigger_fault_drill", "start_repair_challenge", "repair_input"]
const LOCKOUT_S := 86400
const DRILL_CONDITION := 0.35
const TIME_LIMIT_S := 75.0
const MAX_INPUT_DT := 0.1
const SYMBOLS = ["A", "B", "C", "D", "E"]

static func initial() -> Dictionary:
	return {"faults": {}, "session": null, "next_session": 1, "injuries": {}}

static func recover(state: RefCounted) -> void:
	## Runs inside each detailed tick: an injured astronaut returns to duty when the
	## episode's seeded duration has passed.
	var tick: int = state.records.clock.tick_index
	for crew_id in state.repairs.injuries.keys():
		if tick < int(state.repairs.injuries[crew_id].recover_tick): continue
		var member: Dictionary = state.records.crew[crew_id]
		if member.status == "incapacitated":
			member.status = "idle"
			member.health = 1.0
		state.repairs.injuries.erase(crew_id)

static func active(state: RefCounted) -> bool:
	return state.repairs.session != null

static func public_state(state: RefCounted) -> Dictionary:
	var result: Dictionary = state.repairs.duplicate(true)
	result.tick_index = int(state.records.clock.tick_index)
	return result

static func kind_for(definition: Dictionary) -> String:
	# Solar equipment is calibrated; everything else electrical is rewired.
	return "alignment" if float(definition.get("power_generation_kw", 0.0)) > 0.0 else "circuit"

static func command(state: RefCounted, content: Dictionary, cmd: Dictionary) -> Dictionary:
	match cmd.type:
		"trigger_fault_drill": return _trigger(state, content, cmd.payload)
		"start_repair_challenge": return _start(state, content, cmd.payload)
		"repair_input": return _input(state, cmd.payload)
	return _result(false, "unsupported_command", "Unknown repair command.", {})

static func _trigger(state: RefCounted, content: Dictionary, payload: Dictionary) -> Dictionary:
	var id: String = payload.building_id
	var data := {"building_id": id}
	var building: Dictionary = state.records.buildings.get(id, {})
	if building.is_empty(): return _result(false, "unknown_entity", "Unknown building.", data)
	if building.lifecycle != "commissioned": return _result(false, "invalid_state", "Only commissioned equipment can develop a fault.", data)
	if active(state): return _result(false, "invalid_state", "Finish the open repair first.", data)
	for fault in state.repairs.faults.values():
		if fault.status != "resolved": return _result(false, "invalid_state", "Another fault is still unresolved.", data)
	building.condition = minf(float(building.condition), DRILL_CONDITION)
	var kind := kind_for(content.buildings[building.definition_id])
	state.repairs.faults[id] = {"building_id": id, "kind": kind, "status": "open", "locked_until_tick": null,
		"attempts": 0, "last_result": null}
	data.kind = kind
	return _result(true, "ok", "", data, [{"type": "fault_started", "entity_ids": [id], "data": {"building_id": id, "kind": kind}}])

static func _start(state: RefCounted, _content: Dictionary, payload: Dictionary) -> Dictionary:
	var id: String = payload.building_id
	var crew_id: String = payload.crew_id
	var data := {"building_id": id, "crew_id": crew_id}
	var fault: Dictionary = state.repairs.faults.get(id, {})
	if fault.is_empty() or fault.status == "resolved": return _result(false, "invalid_state", "This equipment has no fault to repair.", data)
	if active(state): return _result(false, "invalid_state", "A repair challenge is already open.", data)
	var tick: int = state.records.clock.tick_index
	if fault.status == "locked":
		if tick < int(fault.locked_until_tick):
			data.retry_tick = int(fault.locked_until_tick)
			# The lock belongs to the component: another astronaut cannot bypass it.
			return _result(false, "repair_locked", "The failed repair locked this component. Retry when the lockout ends.", data)
		fault.status = "open"
		fault.locked_until_tick = null
	var member: Dictionary = state.records.crew.get(crew_id, {})
	if member.is_empty(): return _result(false, "unknown_entity", "Unknown astronaut.", data)
	if member.status != "idle" or member.location_kind != "base" or float(member.health) <= 0.0:
		return _result(false, "crew_unavailable", "Choose an idle astronaut at the base.", data)
	var skill := clampf(float(member.skills.get("engineering", 0.0)), 0.0, 1.0)
	var rng: RandomNumberGenerator = state.rng
	var session := {"id": "repair_%06d" % int(state.repairs.next_session), "building_id": id, "crew_id": crew_id,
		"kind": fault.kind, "skill": skill, "sequence": 0, "elapsed_s": 0.0, "time_limit_s": TIME_LIMIT_S,
		"mistakes": 0, "mistakes_allowed": 2 if skill >= 0.6 else 1, "stage": 0, "started_tick": tick}
	if fault.kind == "circuit":
		# Higher engineering skill means fewer leads to trace.
		var count := 3 if skill >= 0.6 else (4 if skill >= 0.3 else 5)
		var order: Array = range(count)
		for index in range(count - 1, 0, -1):
			var swap := rng.randi_range(0, index)
			var held: int = order[index]
			order[index] = order[swap]
			order[swap] = held
		session.merge({"stages": count, "symbols": SYMBOLS.slice(0, count), "right_order": order, "connected": []})
	else:
		# Higher engineering skill means fewer calibration passes and a wider window.
		var stages := 2 if skill >= 0.6 else 3
		var targets: Array = []
		var speeds: Array = []
		for index in stages:
			targets.append(snappedf(rng.randf_range(0.15, 0.85), 0.01))
			speeds.append(snappedf(rng.randf_range(0.45, 0.8), 0.01))
		session.merge({"stages": stages, "targets": targets, "speeds": speeds, "tolerance": 0.05 + 0.07 * skill, "phase": 0.0})
	state.repairs.next_session = int(state.repairs.next_session) + 1
	state.repairs.session = session
	fault.attempts = int(fault.attempts) + 1
	data.session_id = session.id
	return _result(true, "ok", "", data, [{"type": "repair_started", "entity_ids": [id, crew_id], "data": data.duplicate()}])

static func indicator(session: Dictionary) -> float:
	## Triangle sweep between 0 and 1.
	var wrapped := fposmod(float(session.phase), 2.0)
	return wrapped if wrapped <= 1.0 else 2.0 - wrapped

static func _input(state: RefCounted, payload: Dictionary) -> Dictionary:
	var session: Variant = state.repairs.session
	var data := {"session_id": payload.session_id, "action": payload.action}
	if session == null or session.id != payload.session_id: return _result(false, "invalid_state", "That repair session is not open.", data)
	var action: String = payload.action
	var value: float = payload.value
	session.sequence = int(session.sequence) + 1
	data.sequence = session.sequence
	if action == "abandon": return _finish(state, session, false, "abandoned", data)
	if action == "tick":
		# Only bounded, active challenge time is accepted from the wrapper.
		var dt := clampf(value, 0.0, MAX_INPUT_DT)
		session.elapsed_s = float(session.elapsed_s) + dt
		if session.kind == "alignment": session.phase = float(session.phase) + dt * float(session.speeds[int(session.stage)])
		if float(session.elapsed_s) >= float(session.time_limit_s): return _finish(state, session, false, "timeout", data)
		return _result(true, "ok", "", data)
	if session.kind == "circuit" and action == "connect":
		var left := int(value) / 10
		var slot := int(value) % 10
		var count := int(session.stages)
		if value != floorf(value) or left < 0 or left >= count or slot < 0 or slot >= count: return _result(false, "invalid_value", "Unknown terminal.", data)
		for pair in session.connected:
			if pair[0] == left or pair[1] == slot: return _result(false, "invalid_value", "That terminal is already connected.", data)
		if int(session.right_order[slot]) == left:
			session.connected.append([left, slot])
			session.stage = session.connected.size()
			data.correct = true
			if session.connected.size() == count: return _finish(state, session, true, "repaired", data)
			return _result(true, "ok", "", data)
		return _mistake(state, session, data)
	if session.kind == "alignment" and action == "lock":
		var error := absf(indicator(session) - float(session.targets[int(session.stage)]))
		if error <= float(session.tolerance):
			session.stage = int(session.stage) + 1
			session.phase = 0.0
			data.correct = true
			if int(session.stage) >= int(session.stages): return _finish(state, session, true, "repaired", data)
			return _result(true, "ok", "", data)
		return _mistake(state, session, data)
	return _result(false, "invalid_value", "That input does not belong to this challenge.", data)

static func _mistake(state: RefCounted, session: Dictionary, data: Dictionary) -> Dictionary:
	session.mistakes = int(session.mistakes) + 1
	data.correct = false
	if int(session.mistakes) > int(session.mistakes_allowed): return _finish(state, session, false, "too_many_mistakes", data)
	return _result(true, "ok", "", data)

static func _finish(state: RefCounted, session: Dictionary, success: bool, detail: String, data: Dictionary) -> Dictionary:
	var id: String = session.building_id
	var fault: Dictionary = state.repairs.faults[id]
	var building: Dictionary = state.records.buildings[id]
	var tick: int = state.records.clock.tick_index
	state.repairs.session = null
	data.merge({"finished": true, "success": success, "detail": detail, "building_id": id})
	if success:
		building.condition = 1.0
		fault.status = "resolved"
		fault.last_result = "repaired"
		return _result(true, "ok", "", data, [{"type": "repair_succeeded", "entity_ids": [id, session.crew_id], "data": {"building_id": id, "session_id": session.id}}])
	building.condition = 0.0
	var events: Array = []
	if detail == "too_many_mistakes" and session.kind == "circuit":
		# A botched live rewiring injures the operator: one real episode, one to seven
		# mission days from the seeded RNG. They cannot work until they recover.
		var days: int = state.rng.randi_range(1, 7)
		var member: Dictionary = state.records.crew[session.crew_id]
		member.status = "incapacitated"
		member.health = 0.5
		state.repairs.injuries[session.crew_id] = {"crew_id": session.crew_id, "cause": "electrical_shock",
			"started_tick": tick, "recover_tick": tick + days * 86400, "days": days}
		data.injured_crew_id = session.crew_id
		data.injury_days = days
		events.append({"type": "crew_injured", "entity_ids": [session.crew_id], "data": {"crew_id": session.crew_id, "days": days, "cause": "electrical_shock"}})
	fault.status = "locked"
	fault.locked_until_tick = tick + LOCKOUT_S
	fault.last_result = "failed"
	data.retry_tick = fault.locked_until_tick
	events.push_front({"type": "repair_failed", "entity_ids": [id, session.crew_id],
		"data": {"building_id": id, "session_id": session.id, "detail": detail, "retry_tick": fault.locked_until_tick}})
	return _result(true, "ok", "", data, events)

static func _result(success: bool, code: String, reason: String, data: Dictionary, events: Array = []) -> Dictionary:
	return {"success": success, "code": code, "reason": reason, "data": data, "mutates": success, "events": events}
