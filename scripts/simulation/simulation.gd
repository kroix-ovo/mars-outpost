class_name OutpostSimulation
extends RefCounted
## A1 foundation. Running ticks advance the clock only until A2/A3 are integrated.
## Missing gameplay handlers fail explicitly; this is not a playable colony yet.

const Schema = preload("res://scripts/simulation/command_schemas.gd")
const State = preload("res://scripts/simulation/game_state.gd")
const Definitions = preload("res://scripts/simulation/definitions.gd")
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
    if _state.journal.has(id):
        var prior: Dictionary = _state.journal[id]
        if Schema.canonical(prior.normalized) != Schema.canonical(normalized):
            return _rejected(id, "command_id_conflict", "command_id reused with different content")
        return _accepted(id, prior, true)
    if normalized.type not in CONTROLS:
        return _rejected(id, "module_unavailable", "This gameplay handler is not implemented in A1: " + normalized.type)
    if _state.next_receive_sequence >= Schema.MAX_EXACT_INTEGER or _state.counters.event + _state.pending.size() >= Schema.MAX_EXACT_INTEGER:
        return _rejected(id, "invalid_state", "Command sequence or event counter exhausted.")
    var entry = {"normalized": normalized.duplicate(true), "receive_sequence": _state.next_receive_sequence,
        "status": "queued", "result": null}
    _state.next_receive_sequence += 1
    _state.journal[id] = entry
    _state.pending.append(id)
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
    var captured: Array = _state.pending.duplicate()
    _state.pending.clear()
    var outbox: Array = []
    var changed = false
    for id in captured:
        var entry: Dictionary = _state.journal[id]
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
        _state.journal[id].status = "resolved"
        _state.journal[id].result = result
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
    candidate.records.clock.tick_index += 1
    candidate.records.clock.elapsed_s = float(candidate.records.clock.tick_index)
    candidate.records.revision += 1
    _state = candidate
    return _ok()

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
