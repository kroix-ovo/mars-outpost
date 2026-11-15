class_name WorldService
extends RefCounted
## Headless placement and route service (SHARED_SIMULATION_SPEC.md section 10).
##
## Uses immutable map data plus a caller-supplied snapshot. No scene, physics, or navigation
## bake is involved, so the same answers are produced in headless tests, the editor, and
## exported builds. This service never spends resources: Task 01 calls it again at command
## resolution and alone commits the placement.
##
## The BFS, rotation, reason strings, and route_id hash port
## tests/simulation/tools/reference_model.py (rot, in_bounds, bfs, validate_placement,
## query_route) exactly, so the stub expectations in
## tests/simulation/fixtures/stubs/stub_world_fixture_flat_16.json replay unchanged.

const MapData := preload("res://scripts/world/map_data.gd")
const Definitions := preload("res://scripts/world/building_definitions.gd")
const NEIGHBOR_ORDER := [[1, 0], [0, 1], [-1, 0], [0, -1]]  # +X, +Z, -X, -Z
const ACTIVE_EXPEDITION_STATUSES := ["outbound", "working", "returning", "stranded"]

var map: MapData
var definitions: Definitions
var _injected_blocked: Dictionary = {}  # harness-only blocked cells, key -> [x, z]


func setup(map_data: MapData, building_definitions: Definitions) -> Dictionary:
    if map_data == null or building_definitions == null:
        return {"ok": false, "code": "invalid_value", "reason": "Map and building definitions are required."}
    map = map_data
    definitions = building_definitions
    return {"ok": true, "code": "ok", "reason": ""}


static func from_files(map_path: String, definition_paths: Array) -> Dictionary:
    ## Convenience loader. Returns {ok, code, reason, service: WorldService?}.
    var loaded_map := MapData.load_file(map_path)
    if not loaded_map.ok:
        return {"ok": false, "code": loaded_map.code, "reason": loaded_map.reason, "service": null}
    var defs := Definitions.new()
    var loaded_defs := defs.load_paths(definition_paths)
    if not loaded_defs.ok:
        return {"ok": false, "code": loaded_defs.code, "reason": loaded_defs.reason, "service": null}
    var script: GDScript = load("res://scripts/world/world_service.gd")
    var service: RefCounted = script.new()
    service.setup(loaded_map.map, defs)
    return {"ok": true, "code": "ok", "reason": "", "service": service}


func is_ready() -> bool:
    return map != null and definitions != null


func set_injected_blocked_cells(cells: Array) -> void:
    ## Harness-only (contract section 10): lets tests exercise unreachable/stranded behaviour.
    ## Never a player command and never used by production placement.
    _injected_blocked.clear()
    for cell in cells:
        if MapData.is_cell(cell):
            var normalized := [int(cell[0]), int(cell[1])]
            _injected_blocked[MapData.cell_key(normalized)] = normalized


# ---------------------------------------------------------------- placement

func validate_placement(request: Dictionary, snapshot: Dictionary) -> Dictionary:
    if not is_ready():
        return _placement_fail("not_initialized", "World service has no map or definitions.")
    if not request.has("definition_id") or not request.has("cell") or not request.has("rotation_quarters"):
        return _placement_fail("invalid_schema", "Placement request needs definition_id, cell, rotation_quarters.")
    if not request.definition_id is String:
        return _placement_fail("invalid_schema", "definition_id must be a string.")
    if not definitions.has(request.definition_id):
        return _placement_fail("unknown_definition", "Unknown building definition %s." % str(request.definition_id))
    if not MapData.is_cell(request.cell):
        return _placement_fail("invalid_value", "cell must be two integers.")
    if not _whole(request.rotation_quarters) or int(request.rotation_quarters) < 0 or int(request.rotation_quarters) > 3:
        return _placement_fail("invalid_value", "rotation_quarters must be an integer 0-3.")
    if not snapshot.has("buildings") or not snapshot.buildings is Dictionary:
        return _placement_fail("invalid_schema", "Snapshot has no buildings map.")
    var snapshot_check := _check_snapshot_map(snapshot)
    if not snapshot_check.ok:
        return _placement_fail(snapshot_check.code, snapshot_check.reason)

    var definition := definitions.get_definition(request.definition_id)
    var cell: Array = [int(request.cell[0]), int(request.cell[1])]
    var quarters := int(request.rotation_quarters)
    var occupied := Definitions.placed_cells(definition.footprint_cells, quarters, cell)
    var entrances := Definitions.placed_cells(definition.entrance_cells, quarters, cell)

    var blocked_result := _blocked_cells(snapshot)
    if not blocked_result.ok:
        return _placement_fail(blocked_result.code, blocked_result.reason)
    var blocked: Dictionary = blocked_result.cells

    # 1. Bounds (footprint and entrances), exactly as the reference model.
    for c in occupied + entrances:
        if not map.in_bounds(c):
            return _placement_fail("placement_blocked", "out of bounds")
    # 2. Terrain: footprint cells must be buildable.
    for c in occupied:
        if not map.is_buildable(c):
            return _placement_fail("placement_blocked", "cell %s is not buildable" % _cell_text(c))
    # 3. Occupancy by existing footprints (and harness-injected cells).
    for c in occupied:
        if blocked.has(MapData.cell_key(c)):
            return _placement_fail("placement_blocked", "cell %s is occupied" % _cell_text(c))
    # 4. Reserved cells: exploration sites keep their cell free.
    var reserved := _site_cells(snapshot)
    for c in occupied:
        var key := MapData.cell_key(c)
        if reserved.has(key):
            return _placement_fail("placement_blocked", "cell %s is reserved by %s" % [_cell_text(c), reserved[key]])

    var new_blocked := blocked.duplicate()
    for c in occupied:
        new_blocked[MapData.cell_key(c)] = c
    var airlock: Array = map.base_airlock_cell
    var reach_before := _flood(airlock, blocked)
    var reach_after := _flood(airlock, new_blocked)

    # 5. At least one entrance (outside the new footprint) reachable from the airlock afterwards.
    var entrance_reachable := false
    for e in entrances:
        var key := MapData.cell_key(e)
        if not new_blocked.has(key) and reach_after.has(key):
            entrance_reachable = true
            break
    if not entrance_reachable:
        return _placement_fail("placement_blocked", "no reachable entrance")

    # 6. Never cut off an existing building's only reachable entrance.
    var building_ids: Array = snapshot.buildings.keys()
    building_ids.sort()
    for building_id in building_ids:
        var building: Dictionary = snapshot.buildings[building_id]
        if building.get("lifecycle") == "destroyed":
            continue
        var other := definitions.get_definition(building.definition_id)
        var other_entrances := Definitions.placed_cells(other.entrance_cells, int(building.rotation_quarters), building.cell)
        if _any_reachable(other_entrances, blocked, reach_before) and not _any_reachable(other_entrances, new_blocked, reach_after):
            return _placement_fail("placement_blocked", "would block the only reachable entrance of %s" % building_id)

    # 7. Never cut an active crew return path (site cell and current route cell stay reachable).
    var expeditions: Dictionary = snapshot.get("expeditions", {})
    var expedition_ids: Array = expeditions.keys()
    expedition_ids.sort()
    for expedition_id in expedition_ids:
        var expedition: Dictionary = expeditions[expedition_id]
        if not ACTIVE_EXPEDITION_STATUSES.has(expedition.get("status")):
            continue
        for anchor in _expedition_anchor_cells(expedition, snapshot):
            var key := MapData.cell_key(anchor)
            if reach_before.has(key) and not reach_after.has(key):
                return _placement_fail("placement_blocked", "would block the return path of %s" % expedition_id)

    return {"valid": true, "code": "ok", "reason": "", "occupied_cells": occupied, "entrance_cells": entrances}


# ---------------------------------------------------------------- routing

func query_route(request: Dictionary, snapshot: Dictionary) -> Dictionary:
    if not is_ready():
        return _route_fail("not_initialized", "World service has no map or definitions.")
    if not request.has("from_cell") or not request.has("to_cell"):
        return _route_fail("invalid_schema", "Route request needs from_cell and to_cell.")
    if not MapData.is_cell(request.from_cell) or not MapData.is_cell(request.to_cell):
        return _route_fail("invalid_value", "from_cell and to_cell must be two integers each.")
    if not snapshot.has("buildings") or not snapshot.buildings is Dictionary:
        return _route_fail("invalid_schema", "Snapshot has no buildings map.")
    var snapshot_check := _check_snapshot_map(snapshot)
    if not snapshot_check.ok:
        return _route_fail(snapshot_check.code, snapshot_check.reason)
    var from_cell: Array = [int(request.from_cell[0]), int(request.from_cell[1])]
    var to_cell: Array = [int(request.to_cell[0]), int(request.to_cell[1])]
    var blocked_result := _blocked_cells(snapshot)
    if not blocked_result.ok:
        return _route_fail(blocked_result.code, blocked_result.reason)
    var blocked: Dictionary = blocked_result.cells
    var path := _bfs(from_cell, to_cell, blocked)
    if path.is_empty():
        return _route_fail("route_unreachable", "no route")
    var waypoints: Array = []
    for c in path:
        waypoints.append(map.cell_center_m(c))
    return {
        "reachable": true, "code": "ok", "reason": "",
        "route_id": route_id(blocked, from_cell, to_cell),
        "waypoints_m": waypoints,
        "distance_m": float(path.size() - 1),
    }


func route_id(blocked: Dictionary, from_cell: Array, to_cell: Array) -> String:
    ## "route_" + first 16 hex digits of SHA-256 over a canonical JSON document, identical to
    ## Python json.dumps(obj, sort_keys=True, separators=(",", ":")) in the reference model.
    var sorted_blocked: Array = blocked.values().duplicate()
    sorted_blocked.sort_custom(MapData.compare_cells)
    var key := canonical_json({
        "map_id": map.id, "map_revision": map.revision,
        "blocked_cells": sorted_blocked, "from_cell": from_cell, "to_cell": to_cell,
    })
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(key.to_utf8_buffer())
    return "route_" + context.finish().hex_encode().substr(0, 16)


func blocked_cells(snapshot: Dictionary) -> Array:
    ## Sorted blocked cells for the snapshot (footprints of non-destroyed buildings plus
    ## harness-injected cells). Exposed for rendering and tests.
    var result := _blocked_cells(snapshot)
    if not result.ok:
        return []
    var cells: Array = result.cells.values().duplicate()
    cells.sort_custom(MapData.compare_cells)
    return cells


func building_cells(building: Dictionary) -> Dictionary:
    ## {occupied_cells, entrance_cells} for a snapshot building record, or empty arrays if the
    ## definition is unknown. Used by presentation to draw footprints and entrances.
    if not definitions.has(str(building.get("definition_id", ""))):
        return {"occupied_cells": [], "entrance_cells": []}
    var definition := definitions.get_definition(building.definition_id)
    var quarters := int(building.get("rotation_quarters", 0))
    return {
        "occupied_cells": Definitions.placed_cells(definition.footprint_cells, quarters, building.cell),
        "entrance_cells": Definitions.placed_cells(definition.entrance_cells, quarters, building.cell),
    }


static func canonical_json(value: Variant) -> String:
    ## Compact JSON with sorted keys; whole numbers print as integers (Godot parses every JSON
    ## number as a float, so 1.0 must print as 1 to match the Python oracle).
    if value == null:
        return "null"
    if value is bool:
        return "true" if value else "false"
    if value is int:
        return str(value)
    if value is float:
        if value == floor(value) and abs(value) < 9.0e15:
            return str(int(value))
        return JSON.stringify(value)
    if value is String:
        return JSON.stringify(value)
    if value is Array:
        var parts: PackedStringArray = []
        for item in value:
            parts.append(canonical_json(item))
        return "[" + ",".join(parts) + "]"
    if value is Dictionary:
        var keys: Array = value.keys()
        keys.sort()
        var parts: PackedStringArray = []
        for key in keys:
            parts.append(JSON.stringify(str(key)) + ":" + canonical_json(value[key]))
        return "{" + ",".join(parts) + "}"
    return JSON.stringify(value)


# ---------------------------------------------------------------- internals

func _check_snapshot_map(snapshot: Dictionary) -> Dictionary:
    var snapshot_map: Variant = snapshot.get("map")
    if snapshot_map is Dictionary and snapshot_map.has("id"):
        if snapshot_map.id != map.id or (snapshot_map.has("revision") and int(snapshot_map.revision) != map.revision):
            return {"ok": false, "code": "invalid_state",
                "reason": "Snapshot map %s/%s does not match loaded map %s/%d." % [str(snapshot_map.id), str(snapshot_map.get("revision")), map.id, map.revision]}
    return {"ok": true, "code": "ok", "reason": ""}


func _blocked_cells(snapshot: Dictionary) -> Dictionary:
    var cells: Dictionary = _injected_blocked.duplicate()
    var building_ids: Array = snapshot.buildings.keys()
    building_ids.sort()
    for building_id in building_ids:
        var building: Variant = snapshot.buildings[building_id]
        if not building is Dictionary:
            return {"ok": false, "code": "invalid_schema", "reason": "Building record %s is not an object." % str(building_id)}
        if building.get("lifecycle") == "destroyed":
            continue
        if not definitions.has(str(building.get("definition_id"))):
            return {"ok": false, "code": "unknown_definition",
                "reason": "Snapshot building %s uses unknown definition %s." % [str(building_id), str(building.get("definition_id"))]}
        if not MapData.is_cell(building.get("cell")):
            return {"ok": false, "code": "invalid_schema", "reason": "Building %s has an invalid cell." % str(building_id)}
        var definition := definitions.get_definition(building.definition_id)
        for c in Definitions.placed_cells(definition.footprint_cells, int(building.get("rotation_quarters", 0)), building.cell):
            cells[MapData.cell_key(c)] = c
    return {"ok": true, "code": "ok", "reason": "", "cells": cells}


func _site_cells(snapshot: Dictionary) -> Dictionary:
    var reserved: Dictionary = {}
    var sites: Variant = snapshot.get("sites", {})
    if not sites is Dictionary:
        return reserved
    var site_ids: Array = sites.keys()
    site_ids.sort()
    for site_id in site_ids:
        var site: Variant = sites[site_id]
        if site is Dictionary and MapData.is_cell(site.get("cell")):
            reserved[MapData.cell_key(site.cell)] = str(site_id)
    return reserved


func _expedition_anchor_cells(expedition: Dictionary, snapshot: Dictionary) -> Array:
    var anchors: Array = []
    var sites: Variant = snapshot.get("sites", {})
    if sites is Dictionary and sites.has(expedition.get("site_id", "")):
        var site: Variant = sites[expedition.site_id]
        if site is Dictionary and MapData.is_cell(site.get("cell")):
            anchors.append([int(site.cell[0]), int(site.cell[1])])
    var waypoints: Variant = expedition.get("route_waypoints_m", [])
    if waypoints is Array and not waypoints.is_empty():
        var progress := float(expedition.get("route_progress_m", 0.0))
        var index := clampi(int(floor(progress)), 0, waypoints.size() - 1)
        var point: Variant = waypoints[index]
        if point is Array and point.size() == 3:
            anchors.append([int(floor(float(point[0]))), int(floor(float(point[2])))])
    return anchors


func _any_reachable(cells: Array, blocked: Dictionary, reach: Dictionary) -> bool:
    for c in cells:
        var key := MapData.cell_key(c)
        if not blocked.has(key) and reach.has(key):
            return true
    return false


func _passable(cell: Array, blocked: Dictionary) -> bool:
    return map.in_bounds(cell) and map.is_passable(cell) and not blocked.has(MapData.cell_key(cell))


func _flood(start: Array, blocked: Dictionary) -> Dictionary:
    ## All cells reachable from start (inclusive). Empty when start itself is blocked.
    var reached: Dictionary = {}
    if not _passable(start, blocked):
        return reached
    var start_cell := [int(start[0]), int(start[1])]
    reached[MapData.cell_key(start_cell)] = start_cell
    var queue: Array = [start_cell]
    var head := 0
    while head < queue.size():
        var c: Array = queue[head]
        head += 1
        for step in NEIGHBOR_ORDER:
            var n := [c[0] + step[0], c[1] + step[1]]
            var key := MapData.cell_key(n)
            if not reached.has(key) and _passable(n, blocked):
                reached[key] = n
                queue.append(n)
    return reached


func _bfs(a: Array, b: Array, blocked: Dictionary) -> Array:
    ## Four-neighbour BFS in +X, +Z, -X, -Z order; returns the cell path or [] when unreachable.
    if not _passable(a, blocked) or not _passable(b, blocked):
        return []
    var start := [int(a[0]), int(a[1])]
    var goal := [int(b[0]), int(b[1])]
    var goal_key := MapData.cell_key(goal)
    var prev: Dictionary = {MapData.cell_key(start): null}
    var cells: Dictionary = {MapData.cell_key(start): start}
    var queue: Array = [start]
    var head := 0
    while head < queue.size():
        var c: Array = queue[head]
        head += 1
        if MapData.cell_key(c) == goal_key:
            break
        for step in NEIGHBOR_ORDER:
            var n := [c[0] + step[0], c[1] + step[1]]
            var key := MapData.cell_key(n)
            if not prev.has(key) and _passable(n, blocked):
                prev[key] = MapData.cell_key(c)
                cells[key] = n
                queue.append(n)
    if not prev.has(goal_key):
        return []
    var path: Array = []
    var key: Variant = goal_key
    while key != null:
        path.append(cells[key])
        key = prev[key]
    path.reverse()
    return path


static func _cell_text(cell: Array) -> String:
    ## Python list formatting: "[7, 3]".
    return "[%d, %d]" % [int(cell[0]), int(cell[1])]


static func _whole(value: Variant) -> bool:
    if value is int:
        return true
    return value is float and is_finite(value) and value == floor(value)


static func _placement_fail(code: String, reason: String) -> Dictionary:
    return {"valid": false, "code": code, "reason": reason, "occupied_cells": [], "entrance_cells": []}


static func _route_fail(code: String, reason: String) -> Dictionary:
    return {"reachable": false, "code": code, "reason": reason, "route_id": null, "waypoints_m": [], "distance_m": 0.0}
