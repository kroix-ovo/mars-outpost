class_name OutpostSimulation
extends RefCounted
## A1-A3 headless runtime: atomic power, life support and crew-demand accounting.
## Missing gameplay handlers fail explicitly; this is not a playable colony yet.

const Schema = preload("res://scripts/simulation/command_schemas.gd")
const State = preload("res://scripts/simulation/game_state.gd")
const Definitions = preload("res://scripts/simulation/definitions.gd")
const Ledger = preload("res://scripts/simulation/resource_ledger.gd")
const Power = preload("res://scripts/systems/power_system.gd")
const LifeSupport = preload("res://scripts/systems/life_support_system.gd")
const CrewDemand = preload("res://scripts/systems/crew_demand_system.gd")
const CONTROLS = ["set_time_scale", "set_building_enabled"]
const MAX_TICKS_PER_ADVANCE = 120

signal state_changed(snapshot: Dictionary)
signal command_resolved(command_id: String, success: bool, reason: String)
signal game_event(event: Dictionary)

var _state: RefCounted
var _content: Dictionary = {}
var _config: Dictionary = {}
var _world_service: RefCounted
var _crew_adapter: RefCounted
var _busy: bool = false
# Queue/journal metadata is outside gameplay transactions. Handlers cannot mutate
# it through a candidate state; resolve only the current entry after commit/failure.
# Keep every entry for campaign deduplication without copying history per tick.
var _journal: Dictionary = {}
var _pending: Array[String] = []
var _next_receive_sequence: int = 1
# Immutable campaign receipts are never included in gameplay clones. A5 will
# serialize these in core.committed_effects, without changing the save envelope.
var _committed_effects: Dictionary = {}

func initialize(config: Dictionary, world_service: RefCounted, crew_adapter: RefCounted) -> Dictionary:
    if _busy or _state != null:
        return _fail("invalid_state", "Initialize a fresh simulation instance.")
    var loader = Definitions.new()
    var content = loader.load_config(config)
    if not content.ok:
        return _fail(content.code, content.reason)
    var candidate = State.new()
    candidate.populate(config, content)
    _content = content.duplicate(true)
    _config = config.duplicate(true)
    _world_service = world_service
    _crew_adapter = crew_adapter
    _state = candidate
    return _ok()

func get_snapshot() -> Dictionary:
    if _state == null:
        return _fail("not_initialized", "Initialize the simulation first.")
    return _state.snapshot()

func submit_command(command: Dictionary) -> Dictionary:
    var id: Variant = command.get("command_id")
    if _state == null:
        return _rejected(id, "not_initialized", "Initialize the simulation first.")
    var checked = Schema.validate(command)
    if not checked.ok:
        return _rejected(id, checked.code, checked.reason)
    var normalized: Dictionary = checked.command
    if _journal.has(id):
        var prior: Dictionary = _journal[id]
        if Schema.canonical(prior.normalized) != Schema.canonical(normalized):
            return _rejected(id, "command_id_conflict", "command_id reused with different content")
        return _accepted(id, prior, true)
    if normalized.type not in CONTROLS:
        return _rejected(id, "module_unavailable", "This gameplay handler is not implemented in A3: " + normalized.type)
    if _next_receive_sequence >= Schema.MAX_EXACT_INTEGER or _state.counters.event + _pending.size() >= Schema.MAX_EXACT_INTEGER:
        return _rejected(id, "invalid_state", "Command sequence or event counter exhausted.")
    var entry = {"normalized": normalized.duplicate(true), "receive_sequence": _next_receive_sequence,
        "status": "queued", "result": null}
    _next_receive_sequence += 1
    _journal[id] = entry
    _pending.append(id)
    return _accepted(id, entry, false)

func process_pending_commands() -> void:
    # Callback submissions are allowed, recursive dispatch is not.
    if _state == null or _busy:
        return
    _busy = true
    var changed = _boundary()
    if changed:
        state_changed.emit(get_snapshot())
    _busy = false

func advance(real_delta_s: float) -> Dictionary:
    var guard = _guard()
    if not guard.ok: return guard
    if not is_finite(real_delta_s) or real_delta_s < 0:
        return _fail("invalid_value", "real_delta_s must be finite and nonnegative.")
    # Reject unrepresentable time before changing even the command queue.
    if real_delta_s > float(Schema.MAX_EXACT_INTEGER) / 20.0 - _state.accumulator_s:
        return _fail("invalid_value", "Elapsed time exceeds the exact clock range.")
    _busy = true
    var changed = _boundary()
    _state.accumulator_s += real_delta_s * _state.records.clock.time_scale
    var count = 0
    while _state.records.clock.time_scale > 0 and _state.accumulator_s >= 1.0 and count < MAX_TICKS_PER_ADVANCE:
        if count > 0:
            changed = _boundary() or changed
            if _state.records.clock.time_scale == 0: break
        var result = _tick()
        if not result.ok:
            if changed: state_changed.emit(get_snapshot())
            _busy = false
            return result
        _state.accumulator_s -= 1.0
        count += 1
        changed = true
    if changed: state_changed.emit(get_snapshot())
    _busy = false
    return _ok()

func step(delta_sim_seconds: float) -> Dictionary:
    var guard = _guard()
    if not guard.ok: return guard
    if not is_finite(delta_sim_seconds) or delta_sim_seconds != 1.0:
        return _fail("invalid_timestep", "step requires exactly 1.0 simulated second.")
    _busy = true
    var changed = _boundary()
    var result = _ok()
    if _state.records.clock.time_scale > 0:
        result = _tick()
        changed = changed or result.ok
    if changed: state_changed.emit(get_snapshot())
    _busy = false
    return result

func export_save() -> Dictionary:
    var guard = _guard()
    if not guard.ok: return guard
    return _fail("module_unavailable", "Persistence is implemented in A5.")

func import_save(_save_record: Dictionary) -> Dictionary:
    var guard = _guard()
    if not guard.ok: return guard
    return _fail("module_unavailable", "Persistence is implemented in A5.")

func _boundary() -> bool:
    var captured: Array = _pending.duplicate()
    _pending.clear()
    var outbox: Array = []
    var changed = false
    for id in captured:
        var entry: Dictionary = _journal[id]
        var command: Dictionary = entry.normalized
        var candidate = _state.clone()
        var data: Dictionary = {}
        var success = true
        var code = "ok"
        var reason = ""
        var mutates = false
        if command.type == "set_time_scale":
            data = {"time_scale": command.payload.time_scale}
            mutates = candidate.records.clock.time_scale != command.payload.time_scale
            candidate.records.clock.time_scale = command.payload.time_scale
        else:
            var building_id: String = command.payload.building_id
            data = {"building_id": building_id}
            if not candidate.records.buildings.has(building_id):
                success = false
                code = "unknown_entity"
                reason = "unknown building"
            else:
                mutates = candidate.records.buildings[building_id].enabled != command.payload.enabled
                candidate.records.buildings[building_id].enabled = command.payload.enabled
        if mutates and candidate.records.revision >= Schema.MAX_EXACT_INTEGER:
            success = false
            code = "invalid_state"
            reason = "Revision counter exhausted."
        if success:
            if mutates: candidate.records.revision += 1
            _state = candidate
            changed = changed or mutates
        var result = {"success": success, "code": code, "reason": reason,
            "resolved_tick": _state.records.clock.tick_index, "data": data}
        # This single-entry metadata update happens only after the gameplay
        # candidate was committed or discarded. No journal rollback/copy needed.
        entry.status = "resolved"
        entry.result = result
        var entities: Array = [data.building_id] if data.has("building_id") else []
        outbox.append({"id": _state.allocate("event"), "type": "command_result",
            "tick_index": _state.records.clock.tick_index, "entity_ids": entities,
            "data": dict_with_command_id(result, id)})
    # All captured commands resolve before callbacks run. New commands wait.
    for event in outbox:
        command_resolved.emit(event.data.command_id, event.data.success, event.data.reason)
        game_event.emit(event.duplicate(true))
    return changed

func _tick() -> Dictionary:
    if _state.records.clock.tick_index >= Schema.MAX_EXACT_INTEGER or _state.records.revision >= Schema.MAX_EXACT_INTEGER:
        return _fail("invalid_state", "Clock or revision counter exhausted.")
    var candidate = _state.clone()
    var ledger = Ledger.new(candidate, _content, _committed_effects, candidate.records.clock.tick_index)
    var valid = ledger.validate()
    if not valid.ok: return _fail("internal_error", valid.reason)
    # Phases 1/2: environment generation and crew intent await A3-A5.
    # Phase 3: electrical dispatch. All balance writes go through the ledger.
    var power = _dispatch_power(candidate, ledger)
    if not power.ok: return _fail("internal_error", power.reason)
    # Phase 4: one common fraction for each life-support process.
    var processes = _run_life_support(candidate, ledger)
    if not processes.ok: return _fail("internal_error", processes.reason)
    # Phase 5: Task 01 alone deducts base/suit crew demand.
    var demand = _run_crew_demand(candidate, ledger)
    if not demand.ok: return _fail("internal_error", demand.reason)
    # Phases 6/7: labor/EVA/medical outcomes and environmental hazards await peers/A5.
    # Phase 8: finalize actual committed rates, diagnostics and invariants.
    for rid in candidate.records.resources:
        var balance: Dictionary = candidate.records.resources[rid]
        balance.net_rate_per_s = balance.amount - _state.records.resources[rid].amount
        balance.forecast_empty_s = (balance.amount - balance.reserved) / -balance.net_rate_per_s if balance.net_rate_per_s < 0 else null
        if not Schema.number(balance.net_rate_per_s) or (balance.forecast_empty_s != null and not Schema.number(balance.forecast_empty_s)):
            return _fail("internal_error", "Resource diagnostic overflow: " + rid)
    _finalize_power_alerts(candidate)
    _finalize_life_support_alerts(candidate)
    valid = ledger.validate()
    if not valid.ok: return _fail("internal_error", valid.reason)
    var events: Array = []
    var crew_ids = candidate.crew_demand.unmet_needs.keys()
    crew_ids.sort()
    for id in crew_ids:
        var entered: Array = []
        for code in candidate.crew_demand.unmet_needs[id]:
            if code not in _state.crew_demand.unmet_needs.get(id, []): entered.append(code)
        if entered.is_empty(): continue
        if candidate.counters.event >= Schema.MAX_EXACT_INTEGER: return _fail("internal_error", "Event counter exhausted.")
        events.append({"id": candidate.allocate("event"), "type": "resource_shortage", "tick_index": candidate.records.clock.tick_index,
            "entity_ids": [id], "data": {"unmet_needs": entered}})
    candidate.records.clock.tick_index += 1
    candidate.records.clock.elapsed_s = float(candidate.records.clock.tick_index)
    candidate.records.revision += 1
    _state = candidate
    _committed_effects.merge(ledger.staged)
    for event in events: game_event.emit(event.duplicate(true))
    return _ok()

func _dispatch_power(candidate: RefCounted, ledger: RefCounted) -> Dictionary:
    return Power.new().dispatch(candidate, _content, ledger)

func _run_life_support(candidate: RefCounted, ledger: RefCounted) -> Dictionary:
    return LifeSupport.new().run(candidate, _content, ledger)

func _run_crew_demand(candidate: RefCounted, ledger: RefCounted) -> Dictionary:
    return CrewDemand.new().run(candidate, _content, ledger)

func _finalize_life_support_alerts(candidate: RefCounted) -> void:
    var prior: Dictionary = {}
    var wanted: Dictionary = {}
    for alert in candidate.records.alerts:
        prior[alert.id] = alert
        if alert.code not in ["low_oxygen", "co2_high", "storage_full"]: wanted[alert.id] = alert
    var r: Dictionary = candidate.records.resources
    if r.oxygen_kg.amount - r.oxygen_kg.reserved <= 0 or (r.oxygen_kg.forecast_empty_s != null and r.oxygen_kg.forecast_empty_s <= _content.science.alerts.low_oxygen_forecast_s):
        wanted.low_oxygen = _power_alert("low_oxygen", "low_oxygen", "Accessible oxygen is depleted or forecast to run low.", [], candidate.records.clock.tick_index, prior)
    if r.co2_kg.amount >= _content.science.alerts.co2_high_kg:
        wanted.co2_high = _power_alert("co2_high", "co2_high", "Modeled cabin CO2 exceeds the configured engineering warning threshold.", [], candidate.records.clock.tick_index, prior)
    if candidate.crew_demand.wastewater_overflow_kg > 0:
        var key = "storage_full:wastewater_kg"
        wanted[key] = _power_alert(key, "storage_full", "Wastewater storage overflow caused explicit unrecoverable loss.", [], candidate.records.clock.tick_index, prior)
    candidate.records.alerts = []
    var ids = wanted.keys()
    ids.sort()
    for id in ids: candidate.records.alerts.append(wanted[id])

func _finalize_power_alerts(candidate: RefCounted) -> void:
    var prior: Dictionary = {}
    var wanted: Dictionary = {}
    for alert in candidate.records.alerts:
        prior[alert.id] = alert
        if alert.code not in ["power_shortfall", "battery_low"]: wanted[alert.id] = alert
    var ids = candidate.records.buildings.keys()
    ids.sort()
    for id in ids:
        var b: Dictionary = candidate.records.buildings[id]
        if b.power_served_kw < b.power_requested_kw:
            var key = "power_shortfall:" + id
            wanted[key] = _power_alert(key, "power_shortfall", "Equipment is not receiving full power.", [id], candidate.records.clock.tick_index, prior)
    var power: Dictionary = candidate.records.power
    if power.battery_capacity_kwh > 0 and power.battery_stored_kwh < _content.science.alerts.battery_low_fraction * power.battery_capacity_kwh:
        wanted.battery_low = _power_alert("battery_low", "battery_low", "Stored electrical energy is low.", [], candidate.records.clock.tick_index, prior)
    candidate.records.alerts = []
    ids = wanted.keys()
    ids.sort()
    for id in ids: candidate.records.alerts.append(wanted[id])

static func _power_alert(id: String, code: String, message: String, entities: Array, tick: int, prior: Dictionary) -> Dictionary:
    return {"id": id, "code": code, "message": message, "severity": "warning", "entity_ids": entities,
        "first_tick": prior[id].first_tick if prior.has(id) else tick}

func _guard() -> Dictionary:
    if _state == null: return _fail("not_initialized", "Initialize the simulation first.")
    if _busy: return _fail("invalid_state", "Cannot recursively update or replace simulation state.")
    return _ok()

static func dict_with_command_id(result: Dictionary, id: String) -> Dictionary:
    var data = result.duplicate(true)
    data.command_id = id
    return data

static func _accepted(id: String, entry: Dictionary, duplicate: bool) -> Dictionary:
    return {"accepted": true, "command_id": id, "reason": "", "code": "ok",
        "receive_sequence": entry.receive_sequence, "status": entry.status,
        "duplicate": duplicate, "result": entry.result.duplicate(true) if entry.result is Dictionary else null}

static func _rejected(id: Variant, code: String, reason: String) -> Dictionary:
    return {"accepted": false, "command_id": id if id is String else null, "reason": reason, "code": code,
        "receive_sequence": null, "status": "rejected", "duplicate": false, "result": null}

static func _ok() -> Dictionary:
    return {"ok": true, "code": "ok", "reason": ""}

static func _fail(code: String, reason: String) -> Dictionary:
    return Schema.failure(code, reason)
