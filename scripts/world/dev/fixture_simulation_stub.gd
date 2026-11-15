class_name FixtureSimulationStub
extends RefCounted
## Task 02 development stand-in for Task 01's OutpostSimulation facade.
##
## Contract section 1 lets Tasks 02/03 develop against fixture snapshots and stub services until
## the real facade exists. This stub loads a fixture snapshot and lets the world scene exercise
## placement previews, the place_building command flow, and construction lifecycle visuals.
##
## Limits, by design:
## - It never changes resource balances. A stub placement spends nothing; the real facade spends
##   costs atomically at resolution. Nothing here is gameplay truth.
## - Only place_building, set_building_enabled and set_time_scale are handled. Every other
##   command is rejected explicitly with module_unavailable (no false success).
## - Construction progress advances as if one crew member worked full time; crew/EVA are Task 03.
##
## Signals mirror the facade so the integration node can swap in OutpostSimulation unchanged.

signal state_changed(snapshot: Dictionary)
signal command_resolved(command_id: String, success: bool, reason: String)
signal game_event(event: Dictionary)

const CONTRACT_VERSION := "2.0.0"
const SUPPORTED := ["place_building", "set_building_enabled", "set_time_scale"]
const TIME_SCALES := [0, 1, 5, 20]

var _snapshot: Dictionary = {}
var _world: RefCounted
var _journal: Dictionary = {}
var _accumulator: float = 0.0
var _counters: Dictionary = {"building": 0, "task": 0, "event": 0}
var _loaded: bool = false


func load_fixture(path: String, world_service: RefCounted) -> Dictionary:
    if world_service == null or not world_service.is_ready():
        return _fail("invalid_value", "A ready world service is required.")
    if not FileAccess.file_exists(path):
        return _fail("invalid_value", "Fixture snapshot not found: " + path)
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary or not parsed.has("buildings") or not parsed.has("map"):
        return _fail("invalid_schema", "Fixture snapshot is not a snapshot record: " + path)
    if parsed.map.get("id") != world_service.map.id:
        return _fail("invalid_state", "Snapshot map %s does not match world map %s." % [str(parsed.map.get("id")), world_service.map.id])
    _snapshot = parsed
    _world = world_service
    for id in _snapshot.buildings.keys():
        _counters.building = maxi(_counters.building, _suffix(id))
    for id in _snapshot.tasks.keys():
        _counters.task = maxi(_counters.task, _suffix(id))
    _loaded = true
    return _ok()


func is_loaded() -> bool:
    return _loaded


func get_snapshot() -> Dictionary:
    if not _loaded:
        return _fail("not_initialized", "Load a fixture first.")
    return _snapshot.duplicate(true)


func submit_command(command: Dictionary) -> Dictionary:
    var id: Variant = command.get("command_id")
    if not _loaded:
        return _rejected(id, "not_initialized", "Load a fixture first.")
    if not id is String or id.is_empty() or command.get("contract_version") != CONTRACT_VERSION:
        return _rejected(id, "invalid_schema", "Command needs a string command_id and contract_version 2.0.0.")
    var type: Variant = command.get("type")
    var payload: Variant = command.get("payload")
    if not type is String or not payload is Dictionary:
        return _rejected(id, "invalid_schema", "Command needs a type and a payload object.")
    if _journal.has(id):
        var prior: Dictionary = _journal[id]
        if prior.type != type or JSON.stringify(prior.payload) != JSON.stringify(payload):
            return _rejected(id, "command_id_conflict", "command_id reused with different content")
        return {"accepted": true, "command_id": id, "reason": "", "code": "ok", "receive_sequence": prior.sequence,
            "status": "completed", "duplicate": true, "result": prior.result.duplicate(true)}
    if type not in SUPPORTED:
        return _rejected(id, "module_unavailable", "The fixture stub does not handle " + type + "; Task 01's facade does.")
    var sequence := _journal.size() + 1
    var result: Dictionary
    match type:
        "place_building":
            result = _place_building(payload)
        "set_building_enabled":
            result = _set_building_enabled(payload)
        "set_time_scale":
            result = _set_time_scale(payload)
    _journal[id] = {"type": type, "payload": payload.duplicate(true), "sequence": sequence, "result": result}
    if result.success:
        _snapshot.revision = int(_snapshot.revision) + 1
    _emit_event("command_result", result.get("data", {}).values(), {"command_id": id, "success": result.success,
        "code": result.code, "reason": result.reason, "resolved_tick": result.resolved_tick, "data": result.data})
    command_resolved.emit(id, result.success, result.reason)
    if result.success:
        state_changed.emit(get_snapshot())
    return {"accepted": true, "command_id": id, "reason": "", "code": "ok", "receive_sequence": sequence,
        "status": "completed", "duplicate": false, "result": result.duplicate(true)}


func advance(real_delta_s: float) -> Dictionary:
    ## Fixed one-second steps scaled by time_scale, like the facade. Only construction progress and
    ## the clock move here; resources never change in the stub.
    if not _loaded:
        return _fail("not_initialized", "Load a fixture first.")
    if not is_finite(real_delta_s) or real_delta_s < 0.0:
        return _fail("invalid_timestep", "real_delta_s must be finite and non-negative.")
    var scale := int(_snapshot.clock.time_scale)
    if scale == 0:
        return _ok()
    _accumulator += real_delta_s * scale
    var changed := false
    var steps := 0
    while _accumulator >= 1.0 and steps < 120:
        _accumulator -= 1.0
        steps += 1
        changed = _tick() or changed
    if steps > 0:
        _snapshot.clock.tick_index = int(_snapshot.clock.tick_index) + steps
        _snapshot.clock.elapsed_s = float(_snapshot.clock.elapsed_s) + float(steps)
        _snapshot.revision = int(_snapshot.revision) + steps
        changed = true
    if changed:
        state_changed.emit(get_snapshot())
    return _ok()


func dev_patch_building(building_id: String, patch: Dictionary) -> Dictionary:
    ## Development-only: force visual states (blocking codes, condition, lifecycle) to test
    ## presentation. Not a contract command; the real facade has no such entry point.
    if not _loaded or not _snapshot.buildings.has(building_id):
        return _fail("unknown_entity", "Unknown building " + building_id)
    for key in patch:
        _snapshot.buildings[building_id][key] = patch[key]
    _snapshot.revision = int(_snapshot.revision) + 1
    state_changed.emit(get_snapshot())
    return _ok()


# ---------------------------------------------------------------- handlers

func _place_building(payload: Dictionary) -> Dictionary:
    var check: Dictionary = _world.validate_placement(payload, _snapshot)
    if not check.valid:
        return _result(false, check.code, check.reason, {})
    var definition: Dictionary = _world.definitions.get_definition(payload.definition_id)
    _counters.building += 1
    _counters.task += 1
    var building_id := "building_%06d" % _counters.building
    var task_id := "task_%06d" % _counters.task
    _snapshot.buildings[building_id] = {
        "id": building_id, "definition_id": payload.definition_id,
        "cell": [int(payload.cell[0]), int(payload.cell[1])], "rotation_quarters": int(payload.rotation_quarters),
        "lifecycle": "constructing", "enabled": true, "condition": 1.0,
        "construction_task_id": task_id, "construction_progress": 0.0,
        "power_requested_kw": 0.0, "power_served_kw": 0.0, "operating_fraction": 0.0,
        "blocking_codes": ["constructing"],
    }
    _snapshot.tasks[task_id] = {
        "id": task_id, "kind": "construct", "target_id": building_id, "status": "active",
        "priority": 50, "crew_required": 1, "assigned_crew_ids": [],
        "required_work_s": float(definition.construction_work_s), "completed_work_s": 0.0,
        "blocked_code": null, "expedition_id": null,
    }
    return _result(true, "ok", "", {"building_id": building_id, "task_id": task_id})


func _set_building_enabled(payload: Dictionary) -> Dictionary:
    var building_id: Variant = payload.get("building_id")
    if not building_id is String or not _snapshot.buildings.has(building_id):
        return _result(false, "unknown_entity", "Unknown building.", {})
    if not payload.get("enabled") is bool:
        return _result(false, "invalid_value", "enabled must be a bool.", {})
    var building: Dictionary = _snapshot.buildings[building_id]
    building.enabled = payload.enabled
    _refresh_blocking(building)
    return _result(true, "ok", "", {"building_id": building_id})


func _set_time_scale(payload: Dictionary) -> Dictionary:
    var scale: Variant = payload.get("time_scale")
    if not (scale is int or scale is float) or int(scale) != scale or int(scale) not in TIME_SCALES:
        return _result(false, "invalid_value", "time_scale must be 0, 1, 5 or 20.", {})
    _snapshot.clock.time_scale = int(scale)
    return _result(true, "ok", "", {"time_scale": int(scale)})


func _tick() -> bool:
    var changed := false
    var ids: Array = _snapshot.buildings.keys()
    ids.sort()
    for building_id in ids:
        var building: Dictionary = _snapshot.buildings[building_id]
        if building.lifecycle != "constructing":
            continue
        var definition: Dictionary = _world.definitions.get_definition(building.definition_id)
        var work := maxf(float(definition.construction_work_s), 1.0)
        building.construction_progress = minf(1.0, float(building.construction_progress) + 1.0 / work)
        var task_id: Variant = building.construction_task_id
        if task_id != null and _snapshot.tasks.has(task_id):
            _snapshot.tasks[task_id].completed_work_s = float(building.construction_progress) * work
        changed = true
        if building.construction_progress >= 1.0:
            building.lifecycle = "commissioned"
            building.construction_task_id = null
            if task_id != null and _snapshot.tasks.has(task_id):
                _snapshot.tasks[task_id].status = "completed"
            _refresh_blocking(building)
            _emit_event("building_commissioned", [building_id], {"building_id": building_id})
    return changed


func _refresh_blocking(building: Dictionary) -> void:
    var codes: Array = []
    if building.lifecycle == "constructing":
        codes.append("constructing")
    elif building.lifecycle == "destroyed":
        codes.append("destroyed")
    elif not building.enabled:
        codes.append("disabled")
    building.blocking_codes = codes


# ---------------------------------------------------------------- plumbing

func _emit_event(type: String, entity_ids: Array, data: Dictionary) -> void:
    _counters.event += 1
    var ids: Array = []
    for value in entity_ids:
        if value is String and not ids.has(value):
            ids.append(value)
    ids.sort()
    game_event.emit({"id": "event_%06d" % _counters.event, "type": type,
        "tick_index": int(_snapshot.clock.tick_index), "entity_ids": ids, "data": data.duplicate(true)})


static func _suffix(id: String) -> int:
    var parts := id.split("_")
    return int(parts[parts.size() - 1]) if parts.size() > 1 and parts[parts.size() - 1].is_valid_int() else 0


func _result(success: bool, code: String, reason: String, data: Dictionary) -> Dictionary:
    return {"success": success, "code": code, "reason": reason, "resolved_tick": int(_snapshot.clock.tick_index), "data": data}


static func _rejected(id: Variant, code: String, reason: String) -> Dictionary:
    return {"accepted": false, "command_id": id, "reason": reason, "code": code,
        "receive_sequence": null, "status": "rejected", "duplicate": false, "result": null}


static func _ok() -> Dictionary:
    return {"ok": true, "code": "ok", "reason": ""}


static func _fail(code: String, reason: String) -> Dictionary:
    return {"ok": false, "code": code, "reason": reason}
