extends RefCounted
## I advance crew travel and labor against simulation time. I keep job progress here rather than in animation so changing the frame rate does not change the work done.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const LifeSupport = preload("res://scripts/systems/life_support_system.gd")
const Jobs = preload("res://scripts/tasks/crew_jobs.gd")
const Record = preload("res://scripts/crew/crew_save_record.gd")
const TERMINAL = ["completed", "failed", "cancelled"]
# Submission slice (game settings): a botanist's tending shift and the harvest it brings in.
const TEND_WORK_S := 300.0
const TEND_HARVEST_KCAL := 1500.0
var state: RefCounted
var content: Dictionary
var world: RefCounted
var adapter: RefCounted
var ledger: RefCounted
var events: Array = []

func _init(candidate: RefCounted, definitions: Dictionary, service: RefCounted, crew: RefCounted, accounts: RefCounted) -> void:
    state = candidate
    content = definitions
    world = service
    adapter = crew
    ledger = accounts

func initial_jobs() -> Dictionary:
    for id in Jobs.sorted_ids(state.records.buildings):
        var building: Dictionary = state.records.buildings[id]
        var work: float = adapter.repair_work_s(building.condition)
        if building.lifecycle != "commissioned" or work <= 0.0: continue
        var task: Dictionary = adapter.get_task_template("repair", work)
        var task_id: String = state.allocate("task")
        task.merge({"id": task_id, "target_id": id, "status": "queued", "assigned_crew_ids": [],
            "completed_work_s": 0.0, "blocked_code": null, "expedition_id": null})
        state.records.tasks[task_id] = task
    return validate()

func command(cmd: Dictionary) -> Dictionary:
    var before: Dictionary = state.records.duplicate(true)
    var replacements: Dictionary = {}
    if cmd.type == "place_building":
        var placement: Dictionary = world.validate_placement(cmd.payload, state.snapshot())
        if not placement.valid: return fail(placement.code, placement.reason)
        var d: Dictionary = content.buildings.get(cmd.payload.definition_id, {})
        if d.is_empty(): return fail("unknown_definition", "Unknown building definition.")
        if d.construction_work_s <= 0.0: return fail("module_unavailable", "Building construction requires a positive workload.")
        for tech in d.unlocks_required:
            if tech not in state.records.technology.unlocked_ids: return fail("invalid_state", "Required technology is locked: " + str(tech))
        if state.counters.building >= Schema.MAX_EXACT_INTEGER or state.counters.task >= Schema.MAX_EXACT_INTEGER: return fail("invalid_state", "Entity counter exhausted.")
        var supported: Dictionary = LifeSupport.validate_process(d)
        if not supported.ok: return fail("module_unavailable", "This module's production process is not implemented yet.")
        var b: String = state.allocate("building")
        var t: String = state.allocate("task")
        replacements = {"new_building": b, "new_task": t}
        state.records.buildings[b] = {"id": b, "definition_id": d.id, "cell": cmd.payload.cell.duplicate(),
            "rotation_quarters": cmd.payload.rotation_quarters, "lifecycle": "constructing", "enabled": true,
            "condition": 1.0, "construction_task_id": t, "construction_progress": 0.0,
            "power_requested_kw": 0.0, "power_served_kw": 0.0, "operating_fraction": 0.0, "blocking_codes": ["constructing"]}
        if d.storage_capacity.get("energy_kwh", 0.0) > 0: state.per_battery_energy[b] = 0.0
        var paid := material_effect("construction:" + t, t, d.build_cost, false)
        if not paid.ok: return paid
        state.prepaid_build_costs[t] = d.build_cost.duplicate(true)
    elif cmd.type == "start_eva":
        if state.counters.expedition >= Schema.MAX_EXACT_INTEGER or state.counters.task >= Schema.MAX_EXACT_INTEGER: return fail("invalid_state", "Entity counter exhausted.")
        replacements = {"new_task": state.allocate("task"), "new_expedition": state.allocate("expedition")}
    var proposal: Dictionary = adapter.apply_command(cmd, before.duplicate(true))
    if not proposal.get("ok", false): return proposal
    proposal = substitute(proposal, replacements)
    var result := apply(proposal, "command", cmd.type)
    if not result.ok: return result
    if cmd.type == "cancel_task" and state.prepaid_build_costs.has(cmd.payload.task_id):
        var t: String = cmd.payload.task_id
        result = material_effect("refund:" + t, t, state.prepaid_build_costs[t], true)
        if not result.ok: return result
        var b: String = state.records.tasks[t].target_id
        state.records.buildings.erase(b)
        state.per_battery_energy.erase(b)
        state.prepaid_build_costs.erase(t)
    result = validate()
    if not result.ok: return result
    return {"ok": true, "code": "ok", "reason": "", "data": proposal.get("result_data", {}),
        "mutates": Schema.canonical(before) != Schema.canonical(state.records), "events": events}

func phase(name: String) -> Dictionary:
    var labor_inputs: Dictionary = state.records.crew.duplicate(true)
    var context := {"phase": name, "tick_index": state.records.clock.tick_index,
        "unmet_needs": state.crew_demand.unmet_needs if name == "progress" else {}}
    var proposal: Dictionary = adapter.plan_tick(state.snapshot(), 1.0 if name == "progress" else 0.0, context)
    var result := apply(proposal, name)
    if not result.ok: return result
    if name == "progress":
        result = labor(proposal.labor, labor_inputs)
        if not result.ok: return result
        result = drain_caches()
        if not result.ok: return result
    return validate()

func apply(p: Dictionary, phase_name: String, command_type: String = "") -> Dictionary:
    for key in ["crew_updates", "task_updates", "expedition_updates"]:
        if not p.get(key) is Dictionary: return fail("invalid_state", "Malformed crew proposal.")
    for key in ["labor", "resource_requests", "events"]:
        if not p.get(key) is Array: return fail("invalid_state", "Malformed crew proposal.")
    for event in p.events:
        if not event is Dictionary or not Schema.exact_keys(event, ["type", "entity_ids", "data"]) or not Schema.identifier(event.type) or not event.entity_ids is Array or not event.data is Dictionary:
            return fail("invalid_state", "Malformed crew event.")
        for id in event.entity_ids:
            if not Schema.identifier(id): return fail("invalid_state", "Malformed event entity.")
    for request in p.resource_requests:
        if not request is Dictionary or not Schema.exact_keys(request, ["effect_id", "kind", "owner_id", "debits", "credits"]) or not request.debits is Dictionary or not request.credits is Dictionary:
            return fail("invalid_state", "Malformed transfer proposal.")
    if phase_name != "progress" and not p.labor.is_empty(): return fail("invalid_state", "Labor outside progress phase.")
    if phase_name == "intent" and not p.resource_requests.is_empty(): return fail("invalid_state", "Transfers outside progress phase.")
    var prior: Dictionary = state.records.expeditions.duplicate(true)
    for id in p.crew_updates:
        if not Record.fields(p.crew_updates[id], Record.CREW_FIELDS): return fail("invalid_state", "Malformed crew record.")
        if not state.records.crew.has(id): return fail("unknown_entity", "Unknown crew in proposal.")
        var old: Dictionary = state.records.crew[id]
        var member: Dictionary = p.crew_updates[id]
        for field in ["id", "definition_id", "display_name", "skills", "health", "stress", "radiation_dose_msv"]:
            if member.get(field) != old[field]: return fail("invalid_state", "Crew proposal changed immutable or medical fields.")
    for id in p.task_updates:
        if not Record.fields(p.task_updates[id], Record.TASK_FIELDS): return fail("invalid_state", "Malformed task record.")
        var task: Dictionary = p.task_updates[id]
        if state.records.tasks.has(id):
            var old: Dictionary = state.records.tasks[id]
            for field in ["kind", "target_id", "crew_required", "required_work_s", "expedition_id", "completed_work_s"]:
                if task.get(field) != old[field]: return fail("invalid_state", "Adapter changed core-owned task fields.")
        elif phase_name != "command" or command_type not in ["place_building", "start_eva"]:
            return fail("invalid_state", "Unallocated task in proposal.")
    for id in p.expedition_updates:
        if not Record.fields(p.expedition_updates[id], Record.EVA_FIELDS) or not p.expedition_updates[id].cargo is Dictionary or not p.expedition_updates[id].suit_stores is Dictionary:
            return fail("invalid_state", "Malformed expedition record.")
        var trip: Dictionary = p.expedition_updates[id]
        if prior.has(id):
            var old: Dictionary = prior[id]
            for field in ["id", "site_id", "task_id", "crew_ids", "work_required_s", "suit_stores", "cargo"]:
                if trip.get(field) != old[field]: return fail("invalid_state", "Adapter changed expedition ownership or ledger balances.")
            var allowed := {"outbound": ["outbound", "working", "returning", "stranded", "failed"],
                "working": ["working", "returning", "stranded", "failed"], "returning": ["returning", "completed", "stranded", "failed"],
                "stranded": ["stranded", "returning", "failed"], "completed": ["completed"], "failed": ["failed"]}
            if trip.get("status") not in allowed[old.status]: return fail("invalid_state", "Invalid expedition transition.")
            if not Schema.number(trip.get("work_completed_s")) or trip.work_completed_s < old.work_completed_s or trip.work_completed_s > old.work_completed_s + (1.0 if phase_name == "progress" and old.status == "working" else 0.0):
                return fail("invalid_state", "Invalid EVA work increment.")
        elif phase_name != "command" or command_type != "start_eva":
            return fail("invalid_state", "Unallocated expedition in proposal.")
        else:
            if trip.status != "outbound" or not trip.cargo.is_empty(): return fail("invalid_state", "Invalid launch records.")
            for suit in trip.suit_stores.values():
                if suit != {"oxygen_kg": 0.0, "battery_kwh": 0.0}: return fail("invalid_state", "Launch must begin with empty accounts.")
    state.records.crew.merge(p.crew_updates.duplicate(true), true)
    state.records.tasks.merge(p.task_updates.duplicate(true), true)
    state.records.expeditions.merge(p.expedition_updates.duplicate(true), true)
    for id in p.expedition_updates:
        var trip: Dictionary = state.records.expeditions[id]
        state.records.tasks[trip.task_id].completed_work_s = trip.work_completed_s
        if trip.status not in TERMINAL: state.records.sites[trip.site_id].reserved_by_expedition_id = id
    for request in p.resource_requests:
        var e: Dictionary = state.records.expeditions.get(request.get("owner_id"), {})
        if e.is_empty(): return fail("invalid_state", "Transfer has no expedition owner.")
        var old: Dictionary = prior.get(e.id, {})
        var permitted: bool = (request.kind == "eva_load" and command_type == "start_eva" and old.is_empty()) or (phase_name == "progress" and ((request.kind == "salvage_collect" and old.get("status") == "working" and e.status == "returning" and e.work_completed_s >= e.work_required_s) or (request.kind in ["eva_return", "cargo_return"] and old.get("status") == "returning" and e.status == "completed")))
        if not permitted: return fail("invalid_state", "Transfer does not match the expedition transition.")
        # Create empty destination accounts only. Actual quantities belong to Ledger.
        for path in request.credits:
            var parts: PackedStringArray = path.split("/")
            if parts[0] == "cargo" and parts.size() == 3:
                if not e.cargo.has(parts[2]): e.cargo[parts[2]] = 0.0
            elif parts[0] == "return_cache" and parts.size() == 3:
                if not state.return_caches.has(e.id): state.return_caches[e.id] = {}
                if not state.return_caches[e.id].has(parts[2]): state.return_caches[e.id][parts[2]] = 0.0
        var effect: Dictionary = request.duplicate(true)
        effect.scope = "one_time"
        var transferred: Dictionary = ledger.apply_transfer(effect)
        if not transferred.ok: return transferred
    ledger.prune_empty_remote_accounts()
    for id in p.expedition_updates:
        var trip: Dictionary = state.records.expeditions[id]
        if trip.status in TERMINAL: state.records.sites[trip.site_id].reserved_by_expedition_id = null
    events.append_array(p.events.duplicate(true))
    return ok()

func labor(items: Array, inputs: Dictionary) -> Dictionary:
    var seen := {}
    for item in items:
        if not item is Dictionary or not item.has_all(["task_id", "crew_id", "work_s"]): return fail("invalid_state", "Malformed labor.")
        var task: Dictionary = state.records.tasks.get(item.task_id, {})
        var crew: Dictionary = state.records.crew.get(item.crew_id, {})
        var pair: String = str(item.task_id) + "/" + str(item.crew_id)
        if task.is_empty() or crew.is_empty() or seen.has(pair) or task.kind == "eva" or task.status in TERMINAL or item.crew_id not in task.assigned_crew_ids or crew.task_id != task.id or crew.status != "working" or not state.crew_demand.unmet_needs.get(crew.id, []).is_empty() or not Schema.number(item.work_s) or item.work_s < 0:
            return fail("invalid_state", "Invalid labor ownership or amount.")
        seen[pair] = true
        var maximum: float = adapter.labor_capacity(inputs[crew.id], task.kind)
        if item.work_s > maximum + 1e-9: return fail("invalid_state", "Labor exceeds configured productivity.")
        # The adapter's validated template sets productivity; the core caps all
        # increments at remaining work and completes each task exactly once.
        task.completed_work_s = minf(task.required_work_s, task.completed_work_s + item.work_s)
        if task.kind == "construct": state.records.buildings[task.target_id].construction_progress = task.completed_work_s / task.required_work_s
    for id in Jobs.sorted_ids(state.records.tasks):
        var task: Dictionary = state.records.tasks[id]
        if task.kind == "eva" or task.status in TERMINAL or task.completed_work_s < task.required_work_s: continue
        if task.kind not in ["construct", "repair", "farm"]: return fail("module_unavailable", "Agriculture completion requires A4 production rules.")
        task.status = "completed"
        var building: Dictionary = state.records.buildings[task.target_id]
        if task.kind == "farm":
            # Tending done: the harvest enters shared food stock once, through the ledger.
            var food: Dictionary = state.records.resources.food_kcal
            var harvest := minf(TEND_HARVEST_KCAL, float(food.capacity) - float(food.amount))
            var paid: Dictionary = ledger.apply_system({"effect_id": "harvest:" + id, "scope": "one_time", "owner_id": id, "kind": "production",
                "debits": {"source/production/food_kcal": harvest}, "credits": {"base/food_kcal": harvest}})
            if not paid.ok: return paid
            for cid in task.assigned_crew_ids: state.records.crew[cid] = Jobs.release(state.records.crew[cid])
            events.append({"type": "farm_tended", "entity_ids": [id, building.id], "data": {"task_id": id, "building_id": building.id, "harvest_kcal": harvest}})
            events.append({"type": "task_completed", "entity_ids": [id], "data": {"task_id": id}})
            var again := tending_job(building.id)
            if not again.ok: return again
            continue
        if task.kind == "construct":
            building.lifecycle = "commissioned"
            building.construction_progress = 1.0
            building.construction_task_id = null
            building.blocking_codes = []
            state.prepaid_build_costs.erase(id)
            events.append({"type": "building_commissioned", "entity_ids": [building.id], "data": {"building_id": building.id}})
            if LifeSupport.validate_process(content.buildings[building.definition_id]).get("kind") == "farming":
                var tending := tending_job(building.id)
                if not tending.ok: return tending
        else: building.condition = 1.0
        for cid in task.assigned_crew_ids: state.records.crew[cid] = Jobs.release(state.records.crew[cid])
        events.append({"type": "task_completed", "entity_ids": [id], "data": {"task_id": id}})
    ledger.refresh_storage_capacity()
    return ok()

func tending_job(building_id: String) -> Dictionary:
    ## A farm always has one open tending job for a botanist; it needs travel and real labor.
    var template: Dictionary = adapter.get_task_template("farm", TEND_WORK_S)
    if template.is_empty(): return ok()
    if state.counters.task >= Schema.MAX_EXACT_INTEGER: return fail("invalid_state", "Entity counter exhausted.")
    var task_id: String = state.allocate("task")
    template.merge({"id": task_id, "target_id": building_id, "status": "queued", "assigned_crew_ids": [],
        "completed_work_s": 0.0, "blocked_code": null, "expedition_id": null})
    state.records.tasks[task_id] = template
    return ok()

func drain_caches() -> Dictionary:
    for id in Jobs.sorted_ids(state.return_caches):
        var debits := {}
        var credits := {}
        for rid in Jobs.sorted_ids(state.return_caches[id]):
            var resource: Dictionary = state.records.resources[rid]
            var available: float = state.return_caches[id][rid]
            var quantity: float = available if resource.capacity == null else minf(available, resource.capacity - resource.amount)
            if resource.unit == "count": quantity = floorf(quantity)
            if quantity > 0:
                debits["return_cache/%s/%s" % [id, rid]] = quantity
                credits["base/" + rid] = quantity
        if not debits.is_empty():
            var result: Dictionary = ledger.apply_transfer({"effect_id": "tick:%d:cache:%s" % [ledger.tick, id], "scope": "tick", "kind": "cache_return", "owner_id": id, "debits": debits, "credits": credits})
            if not result.ok: return result
    ledger.prune_empty_remote_accounts()
    return ok()

func material_effect(id: String, owner: String, amounts: Dictionary, refund: bool) -> Dictionary:
    var debits := {}
    var credits := {}
    for rid in amounts:
        debits[("source/construction_refund/" if refund else "base/") + rid] = float(amounts[rid])
        credits[("base/" if refund else "sink/construction/") + rid] = float(amounts[rid])
    return ledger.apply_system({"effect_id": id, "scope": "one_time", "owner_id": owner,
        "kind": "external_source" if refund else "external_sink", "debits": debits, "credits": credits})

func validate() -> Dictionary:
    var partition := {"crew": state.records.crew, "tasks": state.records.tasks, "expeditions": state.records.expeditions,
        "return_caches": state.return_caches, "completion_markers": {}, "private_counters": {}}
    var result: Dictionary = adapter.validate_state(adapter.export_state(partition), state.snapshot())
    if not result.ok: return result
    return ledger.validate()

static func substitute(value: Variant, replacements: Dictionary) -> Variant:
    if value is Dictionary:
        var out := {}
        for key in value: out[substitute(key, replacements)] = substitute(value[key], replacements)
        return out
    if value is Array:
        return value.map(func(item: Variant): return substitute(item, replacements))
    if value is String:
        for alias in replacements: value = value.replace(alias, replacements[alias])
    return value

static func ok() -> Dictionary:
    return {"ok": true, "code": "ok", "reason": ""}

static func fail(code: String, reason: String) -> Dictionary:
    return {"ok": false, "code": code, "reason": reason}
