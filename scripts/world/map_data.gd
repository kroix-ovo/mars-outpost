class_name WorldMapData
extends RefCounted
## Immutable logical map data (SHARED_SIMULATION_SPEC.md section 10).
## Loaded once from JSON; never mutated afterwards. One cell is one meter, anchored at the world
## origin; cells are integer [x, z] and world coordinates are [x, y, z] metres with Y up.

const SCHEMA_VERSION := 1

var id: String = ""
var revision: int = 0
var width: int = 0
var height: int = 0
var base_airlock_cell: Array = [0, 0]
var default_passable: bool = true
var default_buildable: bool = true
var default_height_m: float = 0.0
var metadata: Dictionary = {}
var _overrides: Dictionary = {}  # "x,z" -> {passable: bool, buildable: bool, height_m: float}


static func load_file(path: String) -> Dictionary:
    ## Returns {ok, code, reason, map: WorldMapData?}.
    if not FileAccess.file_exists(path):
        return _fail("invalid_value", "Map file not found: " + path)
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        return _fail("invalid_schema", "Map file is not a JSON object: " + path)
    return from_dictionary(parsed)


static func from_dictionary(data: Dictionary) -> Dictionary:
    ## Validates the map schema (fixture_flat_16.json shape) and builds an immutable map.
    var map: RefCounted = load("res://scripts/world/map_data.gd").new()
    for key in ["schema_version", "id", "revision", "size_cells", "default_cell", "cell_overrides", "base_airlock_cell"]:
        if not data.has(key):
            return _fail("invalid_schema", "Map is missing required key %s." % key)
    if not _whole(data.schema_version) or int(data.schema_version) != SCHEMA_VERSION:
        return _fail("unsupported_contract", "Unsupported map schema_version.")
    if not data.id is String or data.id.is_empty():
        return _fail("invalid_value", "Map id must be a non-empty string.")
    if not _whole(data.revision) or int(data.revision) < 0:
        return _fail("invalid_value", "Map revision must be a non-negative integer.")
    if not is_cell(data.size_cells) or int(data.size_cells[0]) <= 0 or int(data.size_cells[1]) <= 0:
        return _fail("invalid_value", "Map size_cells must be two positive integers.")
    if not data.default_cell is Dictionary:
        return _fail("invalid_schema", "Map default_cell must be an object.")
    map.id = data.id
    map.revision = int(data.revision)
    map.width = int(data.size_cells[0])
    map.height = int(data.size_cells[1])
    map.default_passable = bool(data.default_cell.get("passable", true))
    map.default_buildable = bool(data.default_cell.get("buildable", true))
    var default_height: Variant = data.default_cell.get("height_m", 0.0)
    if not _number(default_height):
        return _fail("invalid_value", "default_cell.height_m must be a finite number.")
    map.default_height_m = float(default_height)
    if not data.cell_overrides is Array:
        return _fail("invalid_schema", "Map cell_overrides must be an array.")
    for override in data.cell_overrides:
        if not override is Dictionary or not is_cell(override.get("cell")):
            return _fail("invalid_schema", "Each cell override needs an integer cell.")
        var cell: Array = [int(override.cell[0]), int(override.cell[1])]
        if not map.in_bounds(cell):
            return _fail("invalid_value", "Cell override %s is outside the map." % str(cell))
        var key := cell_key(cell)
        if map._overrides.has(key):
            return _fail("invalid_value", "Duplicate cell override for %s." % str(cell))
        var height_value: Variant = override.get("height_m", map.default_height_m)
        if not _number(height_value):
            return _fail("invalid_value", "Cell override height_m must be a finite number.")
        map._overrides[key] = {
            "passable": bool(override.get("passable", map.default_passable)),
            "buildable": bool(override.get("buildable", map.default_buildable)),
            "height_m": float(height_value),
        }
    if not is_cell(data.base_airlock_cell):
        return _fail("invalid_value", "base_airlock_cell must be an integer cell.")
    map.base_airlock_cell = [int(data.base_airlock_cell[0]), int(data.base_airlock_cell[1])]
    if not map.in_bounds(map.base_airlock_cell):
        return _fail("invalid_value", "base_airlock_cell is outside the map.")
    if not map.is_passable(map.base_airlock_cell):
        return _fail("invalid_value", "base_airlock_cell must be passable.")
    var meta: Variant = data.get("metadata", {})
    map.metadata = meta.duplicate(true) if meta is Dictionary else {}
    return {"ok": true, "code": "ok", "reason": "", "map": map}


func in_bounds(cell: Array) -> bool:
    return int(cell[0]) >= 0 and int(cell[0]) < width and int(cell[1]) >= 0 and int(cell[1]) < height


func is_passable(cell: Array) -> bool:
    if not in_bounds(cell):
        return false
    var override: Variant = _overrides.get(cell_key(cell))
    return override.passable if override != null else default_passable


func is_buildable(cell: Array) -> bool:
    if not in_bounds(cell):
        return false
    var override: Variant = _overrides.get(cell_key(cell))
    return override.buildable if override != null else default_buildable


func height_at(cell: Array) -> float:
    var override: Variant = _overrides.get(cell_key(cell))
    return override.height_m if override != null else default_height_m


func cell_center_m(cell: Array) -> Array:
    ## Logical cell centre as a plain [x, y, z] record (no Vector3 inside records).
    return [float(int(cell[0])) + 0.5, height_at(cell), float(int(cell[1])) + 0.5]


func size_cells() -> Array:
    return [width, height]


func override_cells() -> Array:
    ## Sorted list of cells with explicit overrides (for terrain rendering).
    var cells: Array = []
    for key in _overrides:
        var parts: PackedStringArray = key.split(",")
        cells.append([int(parts[0]), int(parts[1])])
    cells.sort_custom(compare_cells)
    return cells


static func cell_key(cell: Array) -> String:
    return "%d,%d" % [int(cell[0]), int(cell[1])]


static func is_cell(value: Variant) -> bool:
    return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1])


static func compare_cells(a: Array, b: Array) -> bool:
    ## Lexicographic [x, z] order, matching Python sorted() on int lists.
    if int(a[0]) != int(b[0]):
        return int(a[0]) < int(b[0])
    return int(a[1]) < int(b[1])


static func _whole(value: Variant) -> bool:
    if value is int:
        return true
    return value is float and is_finite(value) and value == floor(value)


static func _number(value: Variant) -> bool:
    return (value is int) or (value is float and is_finite(value))


static func _fail(code: String, reason: String) -> Dictionary:
    return {"ok": false, "code": code, "reason": reason, "map": null}
