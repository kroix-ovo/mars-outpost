class_name OutpostCommandSchemas
extends RefCounted
## Pure public-envelope validation. Normalization makes 5 and JSON's 5.0 identical.

const VERSION = "2.0.0"
const MAX_EXACT_INTEGER = 9007199254740991
const PAYLOADS = {
    "place_building": {"definition_id": "id", "cell": "cell", "rotation_quarters": "rotation"},
    "set_building_enabled": {"building_id": "id", "enabled": "bool"},
    "assign_task": {"task_id": "id", "crew_ids": "ids", "priority": "priority"},
    "cancel_task": {"task_id": "id"},
    "start_eva": {"site_id": "id", "crew_ids": "ids", "work_duration_s": "quantity",
        "oxygen_kg_per_crew": "quantity", "battery_kwh_per_crew": "quantity"},
    "recall_eva": {"expedition_id": "id"},
    "set_time_scale": {"time_scale": "scale"},
    # Submission slice: simulation-owned corrective repair challenges.
    "trigger_fault_drill": {"building_id": "id"},
    "start_repair_challenge": {"building_id": "id", "crew_id": "id"},
    "repair_input": {"session_id": "id", "action": "repair_action", "value": "quantity"},
    # Submission slice: opt-in dust storm response.
    "set_storm_response": {"response": "storm_response"},
    "start_storm_practice": {},
    "set_radiation_shelter": {"enabled":"bool"},
}

static func number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func whole(value: Variant, minimum: int = 0, maximum: int = MAX_EXACT_INTEGER) -> bool:
    return number(value) and float(value) >= minimum and float(value) <= maximum and floor(float(value)) == float(value)

static func identifier(value: Variant) -> bool:
    return value is String and not value.strip_edges().is_empty()

static func cell(value: Variant) -> bool:
    return value is Array and value.size() == 2 and whole(value[0], -MAX_EXACT_INTEGER) and whole(value[1], -MAX_EXACT_INTEGER)

static func exact_keys(value: Dictionary, keys: Array) -> bool:
    if value.size() != keys.size():
        return false
    for key in keys:
        if not value.has(key):
            return false
    return true

static func validate(command: Dictionary) -> Dictionary:
    if not exact_keys(command, ["contract_version", "command_id", "type", "payload"]):
        return failure("invalid_schema", "Command envelope keys do not match the schema.")
    if not identifier(command.command_id) or not command.type is String or not command.contract_version is String or not command.payload is Dictionary:
        return failure("invalid_schema", "Invalid command envelope types.")
    if command.contract_version != VERSION:
        return failure("unsupported_contract", "contract_version must be 2.0.0")
    if not PAYLOADS.has(command.type):
        return failure("unsupported_command", "Unknown command type.")
    var schema: Dictionary = PAYLOADS[command.type]
    if not exact_keys(command.payload, schema.keys()):
        return failure("invalid_schema", "Payload keys do not match the command schema.")
    var normalized = command.duplicate(true)
    for key in schema:
        var value: Variant = command.payload[key]
        var valid = false
        match schema[key]:
            "id": valid = identifier(value)
            "bool": valid = value is bool
            "storm_response": valid = value is String and value in ["keep_farm", "save_power"]
            "repair_action": valid = value is String and value in ["connect", "tick", "lock", "abandon"]
            "cell":
                valid = cell(value)
                if valid: normalized.payload[key] = [int(value[0]), int(value[1])]
            "rotation", "priority", "scale":
                var limit = 3 if schema[key] == "rotation" else 100
                valid = whole(value, 0, limit)
                if schema[key] == "scale": valid = valid and int(value) in [0, 1, 5, 20]
                if valid: normalized.payload[key] = int(value)
            "quantity":
                valid = number(value) and value >= 0.0
                if valid: normalized.payload[key] = float(value)
            "ids":
                valid = value is Array and not value.is_empty()
                var seen = {}
                if valid:
                    for item in value:
                        if not identifier(item) or seen.has(item):
                            valid = false
                            break
                        seen[item] = true
        if not valid:
            return failure("invalid_value", "Invalid payload field: " + key)
    return {"ok": true, "code": "ok", "reason": "", "command": normalized}

static func failure(code: String, reason: String) -> Dictionary:
    return {"ok": false, "code": code, "reason": reason}

static func canonical(value: Dictionary) -> String:
    return JSON.stringify(value, "", true, true)
