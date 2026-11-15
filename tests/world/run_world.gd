extends SceneTree
## Headless world-service checks.
## Run with: Godot --headless --path . --script tests/world/run_world.gd
## Exit code 0 and the marker WORLD_PASS mean success; any other outcome is a failure.
const MapData := preload("res://scripts/world/map_data.gd")
const Definitions := preload("res://scripts/world/building_definitions.gd")
const Service := preload("res://scripts/world/world_service.gd")
const FIXTURES := "res://tests/simulation/fixtures/"
const MAP_PATH := FIXTURES + "definitions/map/fixture_flat_16.json"
const DEFINITION_DIR := FIXTURES + "definitions/buildings"
const STUB_PATH := FIXTURES + "stubs/stub_world_fixture_flat_16.json"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
    _stub_replay()
    _rotation()
    _terrain_and_reserved()
    _entrance_protection()
    _return_path_protection()
    _injected_blocked()
    _request_validation()
    _definition_validation()
    _authored_content()
    _bridge_flow()
    _landing_plain_demo()
    if failures.is_empty():
        print("WORLD_PASS checks=", checks)
        quit(0)
    else:
        for failure in failures:
            print("WORLD_FAIL ", failure)
        quit(1)


# ---------------------------------------------------------------- helpers

func _read(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


func _snapshot(name: String) -> Dictionary:
    return _read(FIXTURES + "snapshots/" + name + ".json")


func _service(map_data: Variant = null) -> RefCounted:
    var defs: RefCounted = Definitions.new()
    var loaded: Dictionary = defs.load_directory(DEFINITION_DIR)
    _check(loaded.ok, "load fixture definitions: " + loaded.reason)
    var map_result: Dictionary = MapData.load_file(MAP_PATH) if map_data == null else MapData.from_dictionary(map_data)
    _check(map_result.ok, "load map: " + map_result.reason)
    var service: RefCounted = Service.new()
    service.setup(map_result.map, defs)
    return service


func _check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures.append(label)


func _equal(actual: Variant, expected: Variant, path: String) -> void:
    if _number(actual) and _number(expected):
        _check(abs(float(actual) - float(expected)) <= 1e-8 + 1e-9 * abs(float(expected)), path + ": " + str(actual) + " != " + str(expected))
    elif actual is Dictionary and expected is Dictionary:
        _check(actual.size() == expected.size(), path + " keys " + str(actual.keys()) + " vs " + str(expected.keys()))
        for key in expected:
            _check(actual.has(key), path + "/" + str(key) + " exists")
            if actual.has(key):
                _equal(actual[key], expected[key], path + "/" + str(key))
    elif actual is Array and expected is Array:
        _check(actual.size() == expected.size(), path + " size " + str(actual.size()) + " != " + str(expected.size()))
        for index in mini(actual.size(), expected.size()):
            _equal(actual[index], expected[index], path + "/" + str(index))
    else:
        _check(actual == expected, path + ": " + str(actual) + " != " + str(expected))


static func _number(value: Variant) -> bool:
    return value is int or value is float


func _flat_map(overrides: Array = []) -> Dictionary:
    var data := _read(MAP_PATH)
    data.cell_overrides = overrides
    return data


func _placement(definition_id: String, cell: Array, rotation: int) -> Dictionary:
    return {"definition_id": definition_id, "cell": cell, "rotation_quarters": rotation}


# ---------------------------------------------------------------- cases

func _stub_replay() -> void:
    ## Every placement/route expectation in the Task 01 stub replays unchanged.
    var stub := _read(STUB_PATH)
    _check(stub.get("schema_version") == 2, "stub schema version")
    var service := _service()
    for case in stub.placement_cases:
        var snapshot := _snapshot(case.snapshot)
        var response: Dictionary = service.validate_placement(case.request, snapshot)
        _equal(response, case.response, "placement " + str(case.request.cell))
    for case in stub.route_cases:
        var snapshot := _snapshot(case.snapshot)
        var response: Dictionary = service.query_route(case.request, snapshot)
        _equal(response, case.response, "route " + str(case.request.from_cell) + "->" + str(case.request.to_cell))
        var again: Dictionary = _service().query_route(case.request, snapshot)
        _equal(again, response, "route determinism across instances")
    # The expedition fixture stores the same route the service produces.
    var eva := _snapshot("eva_working_tick10")
    var expedition: Dictionary = eva.expeditions.values()[0]
    var route: Dictionary = service.query_route({"from_cell": [2, 8], "to_cell": eva.sites[expedition.site_id].cell}, _snapshot("salvage_6crew_tick0"))
    _equal(route.route_id, expedition.route_id, "expedition route id")
    _equal(route.waypoints_m, expedition.route_waypoints_m, "expedition waypoints")
    # Canonical JSON matches Python json.dumps(sort_keys=True, separators=(",", ":")).
    _equal(Service.canonical_json({"b": [1.0, 2.5], "a": null, "c": true, "d": "x"}), "{\"a\":null,\"b\":[1,2.5],\"c\":true,\"d\":\"x\"}", "canonical json")


func _rotation() -> void:
    _equal(Definitions.rotate_offset([1, 0], 1), [0, 1], "rotate q1")
    _equal(Definitions.rotate_offset([0, 1], 1), [-1, 0], "rotate q1 b")
    _equal(Definitions.rotate_offset([1, 0], 2), [-1, 0], "rotate q2")
    _equal(Definitions.rotate_offset([1, 0], 3), [0, -1], "rotate q3")
    _equal(Definitions.rotate_offset([1, 0], 4), [1, 0], "rotate q4 identity")
    _equal(Definitions.rotate_offset([2, 1], -1), [1, -2], "rotate negative quarter")
    var service := _service()
    var definition: Dictionary = service.definitions.get_definition("fixture_electrolyzer")
    definition.id = "test_wide"
    definition.footprint_cells = [[0, 0], [1, 0]]
    definition.entrance_cells = [[0, 1]]
    _check(service.definitions.add(definition).ok, "add wide test definition")
    var snapshot := _snapshot("salvage_6crew_tick0")
    var rotated: Dictionary = service.validate_placement(_placement("test_wide", [7, 5], 1), snapshot)
    _equal(rotated, {"valid": true, "code": "ok", "reason": "", "occupied_cells": [[7, 5], [7, 6]], "entrance_cells": [[6, 5]]}, "rotated wide placement")
    var unrotated: Dictionary = service.validate_placement(_placement("test_wide", [7, 5], 0), snapshot)
    _equal(unrotated.occupied_cells, [[7, 5], [8, 5]], "unrotated wide placement")
    # A definition whose footprint would overlap when rotated near an existing module is rejected.
    var overlap: Dictionary = service.validate_placement(_placement("test_wide", [6, 3], 0), snapshot)
    _equal(overlap, {"valid": false, "code": "placement_blocked", "reason": "cell [7, 3] is occupied", "occupied_cells": [], "entrance_cells": []}, "rotated overlap rejected")


func _terrain_and_reserved() -> void:
    var service := _service(_flat_map([
        {"cell": [7, 5], "buildable": false, "height_m": 1.5},
        {"cell": [8, 8], "passable": false, "buildable": false},
        {"cell": [12, 9], "passable": false},
    ]))
    var snapshot := _snapshot("salvage_6crew_tick0")
    var not_buildable: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), snapshot)
    _equal(not_buildable.reason, "cell [7, 5] is not buildable", "non-buildable terrain rejected")
    _equal(not_buildable.code, "placement_blocked", "non-buildable code")
    var blocked_route: Dictionary = service.query_route({"from_cell": [2, 8], "to_cell": [8, 8]}, snapshot)
    _equal(blocked_route.code, "route_unreachable", "impassable destination unreachable")
    var detour: Dictionary = service.query_route({"from_cell": [2, 8], "to_cell": [12, 8]}, snapshot)
    _check(detour.reachable and detour.distance_m == 12.0, "route detours around impassable terrain: " + str(detour.distance_m))
    _equal(detour.waypoints_m[0], [2.5, 0.0, 8.5], "detour start waypoint")
    var reserved: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [12, 8], 0), snapshot)
    _equal(reserved.reason, "cell [12, 8] is reserved by site_cargo_a", "site cell reserved")
    # Heights flow into waypoints but never into cost.
    var high := _service(_flat_map([{"cell": [3, 8], "height_m": 2.0}]))
    var route: Dictionary = high.query_route({"from_cell": [2, 8], "to_cell": [4, 8]}, snapshot)
    _equal(route.waypoints_m, [[2.5, 0.0, 8.5], [3.5, 2.0, 8.5], [4.5, 0.0, 8.5]], "height in waypoints")
    _equal(route.distance_m, 2.0, "height ignored in distance")
    # Entrance on impassable terrain cannot satisfy reachability.
    var entrance_blocked := _service(_flat_map([{"cell": [7, 6], "passable": false}]))
    var response: Dictionary = entrance_blocked.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), snapshot)
    _equal(response.reason, "no reachable entrance", "entrance on impassable terrain")


func _entrance_protection() -> void:
    var service := _service()
    var snapshot := _snapshot("salvage_6crew_tick0")
    # building_000001 sits at [3,3] with its only entrance at [3,4]; occupying [3,4] is refused.
    var response: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [3, 4], 0), snapshot)
    _equal(response.valid, false, "entrance block invalid")
    _equal(response.reason, "would block the only reachable entrance of building_000001", "entrance block reason")
    # Next to the entrance is fine.
    var beside: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [4, 4], 0), snapshot)
    _equal(beside.valid, true, "beside entrance valid")
    # Destroyed buildings neither block nor need protection.
    var destroyed := snapshot.duplicate(true)
    destroyed.buildings.building_000001.lifecycle = "destroyed"
    var over_destroyed: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [3, 3], 0), destroyed)
    _equal(over_destroyed.valid, true, "destroyed footprint is free")
    _check(not service.blocked_cells(destroyed).has([3, 3]), "destroyed building not in blocked set")
    # A module cannot be placed where it would wall itself off (airlock cell).
    var on_airlock: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [2, 8], 0), snapshot)
    _equal(on_airlock.reason, "no reachable entrance", "airlock occupancy rejected")


func _return_path_protection() -> void:
    ## Injected rubble encloses the site at [12,8]; the only way in is through [11,8].
    var wall: Array = [[11, 7], [12, 7], [13, 7], [13, 8], [13, 9], [12, 9], [11, 9]]
    var working := _service()
    working.set_injected_blocked_cells(wall)
    var eva := _snapshot("eva_working_tick10")
    var request := _placement("fixture_electrolyzer", [11, 8], 1)  # entrance rotates to [10,8], airlock side
    var response: Dictionary = working.validate_placement(request, eva)
    _equal(response.valid, false, "return path block invalid")
    _equal(response.reason, "would block the return path of expedition_000001", "return path reason")
    # Same geometry with no active expedition is a legal placement.
    var idle := _service()
    idle.set_injected_blocked_cells(wall)
    var allowed: Dictionary = idle.validate_placement(request, _snapshot("salvage_6crew_tick0"))
    _equal(allowed.valid, true, "no expedition: placement allowed")
    _equal(allowed.entrance_cells, [[10, 8]], "rotated entrance on airlock side")
    # Entrance on the enclosed side is unreachable once the gap is filled.
    var far: Dictionary = idle.validate_placement(_placement("fixture_electrolyzer", [11, 8], 3), _snapshot("salvage_6crew_tick0"))
    _equal(far.reason, "no reachable entrance", "far-side entrance unreachable")
    # Completed expeditions are not protected.
    var done := eva.duplicate(true)
    done.expeditions.expedition_000001.status = "completed"
    _equal(working.validate_placement(request, done).valid, true, "completed expedition not protected")


func _injected_blocked() -> void:
    var service := _service()
    var snapshot := _snapshot("salvage_6crew_tick0")
    var open_route: Dictionary = service.query_route({"from_cell": [2, 8], "to_cell": [12, 8]}, snapshot)
    service.set_injected_blocked_cells([[7, 8]])
    var detour: Dictionary = service.query_route({"from_cell": [2, 8], "to_cell": [12, 8]}, snapshot)
    _check(detour.reachable and detour.distance_m == 12.0, "injected cell forces detour")
    _check(detour.route_id != open_route.route_id, "route id changes with blocked set")
    _equal(detour.waypoints_m[5], [6.5, 0.0, 9.5], "detour goes +Z first (neighbour order)")
    var wall: Array = []
    for z in 16:
        wall.append([6, z])
    service.set_injected_blocked_cells(wall)
    var cut: Dictionary = service.query_route({"from_cell": [2, 8], "to_cell": [12, 8]}, snapshot)
    _equal(cut, {"reachable": false, "code": "route_unreachable", "reason": "no route", "route_id": null, "waypoints_m": [], "distance_m": 0.0}, "wall makes site unreachable")
    service.set_injected_blocked_cells([])
    _equal(service.query_route({"from_cell": [2, 8], "to_cell": [12, 8]}, snapshot).route_id, open_route.route_id, "clearing injection restores route id")


func _request_validation() -> void:
    var service := _service()
    var snapshot := _snapshot("salvage_6crew_tick0")
    var empty_cells := {"occupied_cells": [], "entrance_cells": []}
    var missing: Dictionary = service.validate_placement({"definition_id": "fixture_electrolyzer"}, snapshot)
    _equal(missing.code, "invalid_schema", "missing placement keys")
    _equal(missing.valid, false, "missing keys invalid")
    _equal({"occupied_cells": missing.occupied_cells, "entrance_cells": missing.entrance_cells}, empty_cells, "missing keys empty arrays")
    _equal(service.validate_placement(_placement("nope", [7, 5], 0), snapshot).code, "unknown_definition", "unknown definition")
    _equal(service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 4), snapshot).code, "invalid_value", "rotation out of range")
    _equal(service.validate_placement(_placement("fixture_electrolyzer", [7.5, 5], 0), snapshot).code, "invalid_value", "fractional cell")
    _equal(service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), {}).code, "invalid_schema", "snapshot without buildings")
    var other_map := snapshot.duplicate(true)
    other_map.map.id = "somewhere_else"
    _equal(service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), other_map).code, "invalid_state", "snapshot map mismatch")
    var unknown_building := snapshot.duplicate(true)
    unknown_building.buildings.building_000001.definition_id = "ghost"
    _equal(service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), unknown_building).code, "unknown_definition", "snapshot with unknown definition")
    _equal(service.query_route({"from_cell": [2, 8]}, snapshot).code, "invalid_schema", "route missing to_cell")
    _equal(service.query_route({"from_cell": [2, 8], "to_cell": [99, 8]}, snapshot).code, "route_unreachable", "route out of bounds")
    _equal(service.query_route({"from_cell": [3, 3], "to_cell": [2, 8]}, snapshot).code, "route_unreachable", "route from occupied cell")
    var uninitialized: RefCounted = Service.new()
    _equal(uninitialized.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), snapshot).code, "not_initialized", "uninitialized placement")
    _equal(uninitialized.query_route({"from_cell": [2, 8], "to_cell": [3, 8]}, snapshot).code, "not_initialized", "uninitialized route")
    # Float-typed JSON input (Godot parses all numbers as floats) is accepted.
    var float_request := {"definition_id": "fixture_electrolyzer", "cell": [7.0, 5.0], "rotation_quarters": 0.0}
    _equal(service.validate_placement(float_request, snapshot).valid, true, "float-typed request accepted")
    # Responses never alias the snapshot.
    var response: Dictionary = service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), snapshot)
    response.occupied_cells.clear()
    _equal(service.validate_placement(_placement("fixture_electrolyzer", [7, 5], 0), snapshot).occupied_cells, [[7, 5]], "response copies")


func _definition_validation() -> void:
    var base := _read(DEFINITION_DIR + "/fixture_electrolyzer.json")
    _check(Definitions.validate(base).ok, "fixture definition valid")
    var inside := base.duplicate(true)
    inside.entrance_cells = [[0, 0]]
    _equal(Definitions.validate(inside).code, "invalid_value", "entrance inside footprint rejected")
    var missing := base.duplicate(true)
    missing.erase("process")
    _equal(Definitions.validate(missing).code, "invalid_schema", "missing key rejected")
    var efficiency := base.duplicate(true)
    efficiency.battery_charge_efficiency = 0.0
    _equal(Definitions.validate(efficiency).code, "invalid_value", "zero efficiency rejected")
    var negative := base.duplicate(true)
    negative.power_demand_kw = -1.0
    _equal(Definitions.validate(negative).code, "invalid_value", "negative power rejected")
    var no_entrance := base.duplicate(true)
    no_entrance.entrance_cells = []
    _equal(Definitions.validate(no_entrance).code, "invalid_value", "empty entrances rejected")
    var duplicate_cells := base.duplicate(true)
    duplicate_cells.footprint_cells = [[0, 0], [0, 0]]
    _equal(Definitions.validate(duplicate_cells).code, "invalid_value", "duplicate footprint rejected")
    var registry: RefCounted = Definitions.new()
    _check(registry.add(base).ok, "add once")
    _equal(registry.add(base).code, "invalid_value", "duplicate id rejected")
    var copy: Dictionary = registry.get_definition(base.id)
    copy.footprint_cells.append([5, 5])
    _equal(registry.get_definition(base.id).footprint_cells.size(), 1, "registry hands out copies")
    var bad_map: Dictionary = MapData.from_dictionary({"schema_version": 1, "id": "x", "revision": 1, "size_cells": [4, 4],
        "default_cell": {"passable": true, "buildable": true, "height_m": 0.0}, "cell_overrides": [], "base_airlock_cell": [4, 4]})
    _equal(bad_map.code, "invalid_value", "airlock outside map rejected")
    var impassable_airlock: Dictionary = MapData.from_dictionary({"schema_version": 1, "id": "x", "revision": 1, "size_cells": [4, 4],
        "default_cell": {"passable": true, "buildable": true, "height_m": 0.0},
        "cell_overrides": [{"cell": [1, 1], "passable": false}], "base_airlock_cell": [1, 1]})
    _equal(impassable_airlock.code, "invalid_value", "impassable airlock rejected")


func _authored_content() -> void:
    ## Shipped content under data/ loads through the same validators.
    var defs: RefCounted = Definitions.new()
    var loaded: Dictionary = defs.load_directory("res://data/buildings")
    _check(loaded.ok, "data/buildings load: " + loaded.reason)
    _check(defs.size() >= 5, "at least five authored building definitions")
    for id in defs.ids():
        var definition: Dictionary = defs.get_definition(id)
        _check(definition.id == id, "authored id matches registry key " + id)
        _check(definition.metadata.get("balance_status") in ["placeholder_pending_science_md", "documented_game_abstraction"], "authored definition labelled with balance provenance: " + id)
    var map_result: Dictionary = MapData.load_file("res://data/maps/landing_plain.json")
    _check(map_result.ok, "landing_plain map load: " + map_result.reason)
    if not map_result.ok or not loaded.ok:
        return
    var service: RefCounted = Service.new()
    service.setup(map_result.map, defs)
    var empty := {"map": {"id": map_result.map.id, "revision": map_result.map.revision}, "buildings": {}, "sites": {}, "expeditions": {}}
    var placeable := 0
    for id in defs.ids():
        var found := false
        for x in map_result.map.width:
            for z in map_result.map.height:
                if service.validate_placement(_placement(id, [x, z], 0), empty).valid:
                    found = true
                    break
            if found:
                break
        if found:
            placeable += 1
        else:
            failures.append("authored definition has no valid placement on landing_plain: " + id)
    checks += defs.size()
    _check(placeable == defs.size(), "every authored definition placeable")


func _bridge_flow() -> void:
    ## The integration node drives the construct sequence of contract section 13 against the
    ## development stub: preview -> place_building -> constructing -> commissioned, with resources
    ## untouched throughout.
    var bridge: Node = preload("res://scripts/world/sim_bridge.gd").new()
    bridge.backend = bridge.Backend.STUB
    var boot: Dictionary = bridge.boot()
    _check(boot.ok, "bridge boot: " + boot.reason)
    if not boot.ok:
        return
    _equal(bridge.backend_kind, "stub", "stub backend selected")
    var before: Dictionary = bridge.get_snapshot()
    var resources_before := JSON.stringify(before.resources)
    var events: Array = []
    var resolved: Array = []
    bridge.game_event.connect(func(event: Dictionary) -> void: events.append(event))
    bridge.command_resolved.connect(func(id: String, ok: bool, reason: String) -> void: resolved.append([id, ok, reason]))
    # Preview is advisory and identical to the service answer.
    var preview: Dictionary = bridge.validate_placement({"definition_id": "fixture_generator", "cell": [7, 5], "rotation_quarters": 0})
    _equal(preview.valid, true, "bridge preview valid")
    # Blocked placement resolves as failed with no new building.
    var blocked: Dictionary = bridge.submit_place_building({"definition_id": "fixture_generator", "cell": [7, 3], "rotation_quarters": 0})
    _equal(blocked.accepted, true, "blocked command accepted at submission")
    _equal(blocked.result.success, false, "blocked command fails at resolution")
    _equal(blocked.result.code, "placement_blocked", "blocked command code")
    _equal(bridge.get_snapshot().buildings.size(), before.buildings.size(), "blocked command adds nothing")
    # Valid placement creates a constructing building and a task.
    var placed: Dictionary = bridge.submit_place_building({"definition_id": "fixture_generator", "cell": [7, 5], "rotation_quarters": 0})
    _equal(placed.result.success, true, "placement resolves")
    var building_id: String = placed.result.data.building_id
    var after: Dictionary = bridge.get_snapshot()
    _equal(after.buildings[building_id].lifecycle, "constructing", "new building constructing")
    _equal(after.buildings[building_id].blocking_codes, ["constructing"], "constructing blocking code")
    _equal(after.tasks[placed.result.data.task_id].kind, "construct", "construction task created")
    _check(after.revision > before.revision, "revision advanced")
    _equal(JSON.stringify(after.resources), resources_before, "stub never changes resources")
    # The new footprint now blocks routes and re-validation.
    _equal(bridge.query_route([2, 8], [7, 5]).reachable, false, "new footprint blocks routing")
    _equal(bridge.validate_placement({"definition_id": "fixture_generator", "cell": [7, 5], "rotation_quarters": 0}).reason, "cell [7, 5] is occupied", "re-validation sees new footprint")
    # Duplicate command id returns the cached result without a second building.
    var count_before: int = bridge.get_snapshot().buildings.size()
    var duplicate: Dictionary = bridge._backend.submit_command({"contract_version": "2.0.0", "command_id": placed.command_id, "type": "place_building", "payload": {"definition_id": "fixture_generator", "cell": [7, 5], "rotation_quarters": 0}})
    _equal(duplicate.duplicate, true, "duplicate flagged")
    _equal(bridge.get_snapshot().buildings.size(), count_before, "duplicate adds nothing")
    # Unsupported commands are rejected explicitly.
    _equal(bridge.submit_command("start_eva", {"site_id": "site_cargo_a", "crew_ids": ["crew_000001"], "work_duration_s": 10, "oxygen_kg_per_crew": 0.1, "battery_kwh_per_crew": 0.01}).code, "module_unavailable", "stub rejects EVA explicitly")
    # Advancing simulated time commissions the module (5 s of work for the fixture generator).
    bridge._backend.advance(6.0)
    var done: Dictionary = bridge.get_snapshot()
    _equal(done.buildings[building_id].lifecycle, "commissioned", "building commissioned after work")
    _equal(done.buildings[building_id].blocking_codes, [], "commissioned blocking codes clear")
    _equal(done.buildings[building_id].construction_task_id, null, "task reference cleared")
    _equal(done.clock.tick_index, 6, "six ticks elapsed")
    var commissioned := events.filter(func(event: Dictionary) -> bool: return event.type == "building_commissioned")
    _equal(commissioned.size(), 1, "one building_commissioned event")
    _equal(commissioned[0].entity_ids, [building_id], "event names the building")
    _equal(resolved.size(), 2, "two resolutions emitted (blocked + placed; duplicate re-emits nothing)")
    # Pause stops the clock.
    bridge.set_time_scale(0)
    bridge._backend.advance(5.0)
    _equal(bridge.get_snapshot().clock.tick_index, 6, "paused clock does not advance")
    bridge.free()


func _landing_plain_demo() -> void:
    ## The authored world (map, definitions, scenes, demo snapshot) loads through the bridge and
    ## every site and module entrance is reachable from the airlock.
    var bridge: Node = preload("res://scripts/world/sim_bridge.gd").new()
    bridge.backend = bridge.Backend.STUB
    var boot: Dictionary = bridge.boot()
    _check(boot.ok, "fixture bridge boot: " + boot.reason)
    var switched: Dictionary = bridge.load_world("res://data/maps/landing_plain.json", "res://data/buildings",
        "res://tests/world/fixtures/landing_plain_demo_snapshot.json", bridge.Backend.STUB)
    _check(switched.ok, "load landing_plain world: " + switched.reason)
    if not switched.ok:
        bridge.free()
        return
    var snapshot: Dictionary = bridge.get_snapshot()
    _equal(snapshot.map.id, "landing_plain", "demo snapshot map id")
    _equal(bridge.map_data.id, "landing_plain", "bridge map switched")
    var airlock: Array = bridge.map_data.base_airlock_cell
    for site_id in snapshot.sites:
        var route: Dictionary = bridge.query_route(airlock, snapshot.sites[site_id].cell)
        _check(route.reachable, "demo site reachable: " + site_id + " " + route.reason)
    var site_script := preload("res://scripts/world/site_view.gd")
    _equal(site_script.kind_of("ice_survey_hollow"), site_script.Kind.ICE, "ice site kind")
    _equal(site_script.kind_of("survey_ridge_saddle"), site_script.Kind.SURVEY, "survey site kind")
    _equal(site_script.kind_of("cargo_cache_lander_debris"), site_script.Kind.CARGO, "cargo site kind")
    for building_id in snapshot.buildings:
        var building: Dictionary = snapshot.buildings[building_id]
        var cells: Dictionary = bridge.world_service.building_cells(building)
        _check(not cells.occupied_cells.is_empty(), "demo building has footprint: " + building_id)
        for cell in cells.occupied_cells:
            _check(bridge.map_data.is_buildable(cell), "demo building on buildable terrain: " + building_id)
        var reachable := false
        for entrance in cells.entrance_cells:
            if bridge.query_route(airlock, entrance).reachable:
                reachable = true
        _check(reachable, "demo building entrance reachable: " + building_id)
    # Every authored definition points at a scene whose root carries the shared building logic.
    for id in bridge.definitions.ids():
        var definition: Dictionary = bridge.definitions.get_definition(id)
        _check(definition.scene_path is String and ResourceLoader.exists(definition.scene_path), "scene exists for " + id)
        if definition.scene_path is String and ResourceLoader.exists(definition.scene_path):
            var instance: Node = load(definition.scene_path).instantiate()
            _check(instance.has_method("apply_record"), "scene root uses building_node.gd: " + id)
            _check(instance.get_node_or_null("Art") != null, "scene has Art child: " + id)
            instance.free()
    # Utility lines follow authoritative routes; no module is cut off in the demo layout.
    var utilities: Node3D = preload("res://scripts/world/utility_view.gd").new()
    utilities.setup(bridge.world_service, null)
    utilities.apply_snapshot(snapshot)
    _equal(utilities.unreachable_buildings(), [], "no cut-off modules in demo layout")
    _equal(utilities.get_child_count(), snapshot.buildings.size(), "one utility line per building")
    utilities.free()
    # Placement on the apron (passable, not buildable) is refused with the terrain reason.
    var apron: Dictionary = bridge.validate_placement({"definition_id": "battery_bank_mk1", "cell": [11, 24], "rotation_quarters": 0})
    _equal(apron.reason, "cell [11, 24] is not buildable", "apron is not buildable")
    # A failed world switch keeps the current world.
    var failed: Dictionary = bridge.load_world("res://data/maps/missing.json", "res://data/buildings", "res://tests/world/fixtures/landing_plain_demo_snapshot.json", bridge.Backend.STUB)
    _equal(failed.ok, false, "missing map fails to load")
    _equal(bridge.map_data.id, "landing_plain", "failed switch keeps previous world")
    _equal(bridge.get_snapshot().map.id, "landing_plain", "failed switch keeps previous snapshot")
    bridge.free()
