class_name BuildingDefinitions
extends RefCounted
## Loads and validates building definition JSON (SHARED_SIMULATION_SPEC.md section 7).
## Task 02 authors these files under data/buildings/; Task 01 validates them again at
## campaign initialization. Definitions are immutable once loaded.

const MapData := preload("res://scripts/world/map_data.gd")
const SCHEMA_VERSION := 1
const REQUIRED_KEYS := [
    "schema_version", "id", "display_name", "scene_path", "footprint_cells", "entrance_cells",
    "build_cost", "construction_work_s", "power_generation_kw", "power_demand_kw", "power_priority",
    "process_priority", "process", "storage_capacity", "battery_charge_limit_kw",
    "battery_discharge_limit_kw", "battery_charge_efficiency", "battery_discharge_efficiency",
    "maintenance_work_s_per_s", "unlocks_required", "metadata",
]

var _definitions: Dictionary = {}  # id -> definition Dictionary (deep copies handed out)


func load_directory(path: String) -> Dictionary:
    ## Loads every *.json file in a directory (sorted by name). Returns {ok, code, reason, loaded}.
    var dir := DirAccess.open(path)
    if dir == null:
        return _fail("invalid_value", "Cannot open building definition directory: " + path)
    var paths: Array = []
    dir.list_dir_begin()
    var name := dir.get_next()
    while name != "":
        if not dir.current_is_dir() and name.to_lower().ends_with(".json"):
            paths.append(path.path_join(name))
        name = dir.get_next()
    dir.list_dir_end()
    paths.sort()
    return load_paths(paths)


func load_paths(paths: Array) -> Dictionary:
    var loaded: Array = []
    for path in paths:
        if not FileAccess.file_exists(path):
            return _fail("invalid_value", "Building definition not found: " + str(path), loaded)
        var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
        if not parsed is Dictionary:
            return _fail("invalid_schema", "Building definition is not a JSON object: " + str(path), loaded)
        var added := add(parsed)
        if not added.ok:
            return _fail(added.code, str(path) + ": " + added.reason, loaded)
        loaded.append(parsed.id)
    return {"ok": true, "code": "ok", "reason": "", "loaded": loaded}


func add(definition: Dictionary) -> Dictionary:
    var checked := validate(definition)
    if not checked.ok:
        return checked
    if _definitions.has(definition.id):
        return _fail("invalid_value", "Duplicate building definition id %s." % definition.id)
    _definitions[definition.id] = definition.duplicate(true)
    return {"ok": true, "code": "ok", "reason": ""}


func has(id: String) -> bool:
    return _definitions.has(id)


func get_definition(id: String) -> Dictionary:
    ## Deep copy; callers cannot mutate the registry.
    if not _definitions.has(id):
        return {}
    return _definitions[id].duplicate(true)


func ids() -> Array:
    var result: Array = _definitions.keys()
    result.sort()
    return result


func size() -> int:
    return _definitions.size()


static func validate(definition: Dictionary) -> Dictionary:
    for key in REQUIRED_KEYS:
        if not definition.has(key):
            return _fail("invalid_schema", "Missing required key %s." % key)
    if not _whole(definition.schema_version) or int(definition.schema_version) != SCHEMA_VERSION:
        return _fail("unsupported_contract", "Unsupported building schema_version.")
    if not definition.id is String or definition.id.is_empty():
        return _fail("invalid_value", "id must be a non-empty string.")
    if not definition.display_name is String:
        return _fail("invalid_value", "display_name must be a string.")
    if definition.scene_path != null and not definition.scene_path is String:
        return _fail("invalid_value", "scene_path must be a string or null.")
    var footprint := _cell_list(definition.footprint_cells)
    if footprint.is_empty():
        return _fail("invalid_value", "footprint_cells must be a non-empty list of integer offsets.")
    var entrances := _cell_list(definition.entrance_cells)
    if entrances.is_empty():
        return _fail("invalid_value", "entrance_cells must be a non-empty list of integer offsets.")
    var seen: Dictionary = {}
    for cell in footprint:
        var key := MapData.cell_key(cell)
        if seen.has(key):
            return _fail("invalid_value", "footprint_cells contains duplicate offset %s." % str(cell))
        seen[key] = true
    var seen_entrances: Dictionary = {}
    for cell in entrances:
        var key := MapData.cell_key(cell)
        if seen.has(key):
            return _fail("invalid_value", "entrance %s lies inside the footprint." % str(cell))
        if seen_entrances.has(key):
            return _fail("invalid_value", "entrance_cells contains duplicate offset %s." % str(cell))
        seen_entrances[key] = true
    if not _quantities(definition.build_cost) or not _quantities(definition.storage_capacity):
        return _fail("invalid_value", "build_cost and storage_capacity must map resource ids to non-negative numbers.")
    for key in ["construction_work_s", "power_generation_kw", "power_demand_kw", "battery_charge_limit_kw",
            "battery_discharge_limit_kw", "maintenance_work_s_per_s"]:
        if not _nonnegative(definition[key]):
            return _fail("invalid_value", "%s must be a finite non-negative number." % key)
    for key in ["power_priority", "process_priority"]:
        if not _whole(definition[key]):
            return _fail("invalid_value", "%s must be an integer." % key)
    for key in ["battery_charge_efficiency", "battery_discharge_efficiency"]:
        var value: Variant = definition[key]
        if not _nonnegative(value) or float(value) <= 0.0 or float(value) > 1.0:
            return _fail("invalid_value", "%s must be in (0, 1]." % key)
    var process: Variant = definition.process
    if not process is Dictionary or not process.has("inputs_per_s") or not process.has("outputs_per_s"):
        return _fail("invalid_schema", "process must contain inputs_per_s and outputs_per_s.")
    if not _quantities(process.inputs_per_s) or not _quantities(process.outputs_per_s):
        return _fail("invalid_value", "process rates must be non-negative numbers.")
    if not definition.unlocks_required is Array:
        return _fail("invalid_value", "unlocks_required must be an array.")
    for unlock in definition.unlocks_required:
        if not unlock is String:
            return _fail("invalid_value", "unlocks_required entries must be strings.")
    if not definition.metadata is Dictionary:
        return _fail("invalid_value", "metadata must be an object.")
    return {"ok": true, "code": "ok", "reason": ""}


static func rotate_offset(offset: Array, quarters: int) -> Array:
    ## Contract rule: (x, z) -> (-z, x) per positive quarter turn.
    var x := int(offset[0])
    var z := int(offset[1])
    for _i in posmod(quarters, 4):
        var next_x := -z
        z = x
        x = next_x
    return [x, z]


static func placed_cells(offsets: Array, quarters: int, anchor: Array) -> Array:
    ## Rotates each offset and translates it to the anchor cell. Order is preserved.
    var cells: Array = []
    for offset in offsets:
        var rotated := rotate_offset(offset, quarters)
        cells.append([int(anchor[0]) + rotated[0], int(anchor[1]) + rotated[1]])
    return cells


static func _cell_list(value: Variant) -> Array:
    if not value is Array:
        return []
    var cells: Array = []
    for item in value:
        if not MapData.is_cell(item):
            return []
        cells.append([int(item[0]), int(item[1])])
    return cells


static func _quantities(value: Variant) -> bool:
    if not value is Dictionary:
        return false
    for key in value:
        if not key is String or not _nonnegative(value[key]):
            return false
    return true


static func _nonnegative(value: Variant) -> bool:
    if value is int:
        return value >= 0
    return value is float and is_finite(value) and value >= 0.0


static func _whole(value: Variant) -> bool:
    if value is int:
        return true
    return value is float and is_finite(value) and value == floor(value)


static func _fail(code: String, reason: String, loaded: Array = []) -> Dictionary:
    return {"ok": false, "code": code, "reason": reason, "loaded": loaded}
