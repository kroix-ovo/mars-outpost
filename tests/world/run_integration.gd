extends SceneTree
## Integration check between the world bridge/scene and Task 01's OutpostSimulation.
## Run: Godot --headless --path . --script tests/world/run_integration.gd
## Prints INTEGRATION_SKIP (exit 0) when scripts/simulation/simulation.gd is not on this branch,
## INTEGRATION_PASS checks=N when the bridge, the scene and the simulation agree, and
## INTEGRATION_FAIL (exit 1) otherwise. Nothing here spends resources; the scene only submits
## commands and reads snapshots.

const Bridge := preload("res://scripts/world/sim_bridge.gd")
const Service := preload("res://scripts/world/world_service.gd")
const SIMULATION_SCRIPT := "res://scripts/simulation/simulation.gd"
const PROBE_PLACEMENT := {"definition_id": "fixture_storage_module", "cell": [7, 5], "rotation_quarters": 0}

var checks := 0
var failures := 0
var _done := false
var _main: Node
var _frames := 0
var _scene_tick_at_start := -1


func _initialize() -> void:
    if not ResourceLoader.exists(SIMULATION_SCRIPT):
        print("INTEGRATION_SKIP scripts/simulation/simulation.gd is not present on this branch")
        _done = true
        quit(0)
        return
    _headless_bridge()
    _main = load("res://scenes/world/main.tscn").instantiate()
    root.add_child(_main)


func _process(_delta: float) -> bool:
    if _done:
        return true
    _frames += 1
    var bridge: Node = _main.get_node("Integration")
    if _frames == 2:
        _check(bridge.backend_kind == "simulation", "scene AUTO backend picks OutpostSimulation, got " + bridge.backend_kind)
        _scene_tick_at_start = int(bridge.get_snapshot().get("clock", {}).get("tick_index", -1))
        bridge.set_time_scale(20)
    elif _frames == 40:
        var tick := int(bridge.get_snapshot().get("clock", {}).get("tick_index", -1))
        _check(tick > _scene_tick_at_start, "scene clock advances through the bridge (%d -> %d)" % [_scene_tick_at_start, tick])
        var buildings: Node = _main.get_node("Buildings")
        _check(buildings.get_child_count() == bridge.get_snapshot().buildings.size(), "one building node per simulation building")
        var utilities: Node = _main.get_node("Utilities")
        _check(utilities.unreachable_buildings().is_empty(), "every simulation building has a reachable entrance")
        var switched: Dictionary = _main.load_world(1)
        _check(switched.ok, "authored world loads on the stub: " + str(switched.reason))
        _check(bridge.backend_kind == "stub", "authored world uses the stub while Task 01 has no scenario for it")
        var back: Dictionary = _main.load_world(0)
        _check(back.ok, "fixture world reloads: " + str(back.reason))
        _check(bridge.backend_kind == "simulation", "fixture world returns to OutpostSimulation")
        _finish()
    return false


func _headless_bridge() -> void:
    var bridge: Node = Bridge.new()
    bridge.backend = Bridge.Backend.SIMULATION
    var booted: Dictionary = bridge.boot()
    _check(booted.ok, "bridge boots on OutpostSimulation: " + str(booted.get("reason", "")))
    if not booted.ok:
        bridge.free()
        return
    _check(bridge.backend_kind == "simulation", "backend kind reported as simulation")
    var snap: Dictionary = bridge.get_snapshot()
    _check(str(snap.get("map", {}).get("id", "")) == bridge.map_data.id, "snapshot map id matches the loaded map")
    _check(int(snap.get("map", {}).get("revision", -1)) == bridge.map_data.revision, "snapshot map revision matches the loaded map")
    _check(snap.buildings.size() > 0, "simulation starts with buildings")
    _check(snap.sites.size() > 0, "simulation starts with sites")

    # Every starting building and site is reachable through the world service against the live snapshot.
    for building_id in snap.buildings:
        var building: Dictionary = snap.buildings[building_id]
        var entrances: Array = bridge.world_service.building_cells(building).entrance_cells
        var reachable := false
        for entrance in entrances:
            if bridge.query_route(bridge.map_data.base_airlock_cell, entrance).reachable:
                reachable = true
                break
        _check(reachable, "entrance reachable for " + building_id)
    for site_id in snap.sites:
        var route: Dictionary = bridge.query_route(bridge.map_data.base_airlock_cell, snap.sites[site_id].cell)
        _check(route.reachable, "site reachable: " + site_id)

    # Preview is advisory and never touches the simulation.
    var before_resources := Service.canonical_json(snap.resources)
    var before_revision := int(snap.revision)
    var preview: Dictionary = bridge.validate_placement(PROBE_PLACEMENT)
    _check(preview.valid, "probe placement previews valid: " + str(preview.reason))
    _check(int(bridge.get_snapshot().revision) == before_revision, "preview leaves the simulation revision unchanged")

    # place_building goes through the contract envelope. Task 01 may still reject it as unavailable;
    # either way the scene never changes balances itself.
    var response: Dictionary = bridge.submit_place_building(PROBE_PLACEMENT)
    for key in ["accepted", "command_id", "reason", "code", "receive_sequence", "status", "duplicate", "result"]:
        _check(response.has(key), "place_building response has " + key)
    if response.accepted:
        var after: Dictionary = bridge.get_snapshot()
        _check(after.buildings.size() == snap.buildings.size() + 1, "accepted placement adds exactly one building")
        var created := false
        for building_id in after.buildings:
            var building: Dictionary = after.buildings[building_id]
            if not snap.buildings.has(building_id):
                created = true
                _check(building.lifecycle == "constructing", "new building starts constructing")
                _check(building.definition_id == PROBE_PLACEMENT.definition_id, "new building keeps the requested definition")
        _check(created, "accepted placement is visible in the snapshot")
        _check(not bridge.validate_placement(PROBE_PLACEMENT).valid, "footprint is occupied after placement")
    else:
        _check(response.code in ["module_unavailable", "placement_blocked", "insufficient_resources", "invalid_state"],
            "rejected placement carries a contract code: " + str(response.code))
        _check(not str(response.reason).is_empty(), "rejected placement explains itself")
        _check(Service.canonical_json(bridge.get_snapshot().resources) == before_resources, "rejected placement leaves balances untouched")
        _check(bridge.get_snapshot().buildings.size() == snap.buildings.size(), "rejected placement creates no building")

    # Controls resolve through the same path and the snapshot reflects them.
    var scaled: Dictionary = bridge.set_time_scale(5)
    _check(scaled.accepted, "set_time_scale accepted: " + str(scaled.reason))
    _check(int(bridge.get_snapshot().clock.time_scale) == 5, "time scale applied after resolution")
    var ids: Array = snap.buildings.keys()
    ids.sort()
    var toggled: Dictionary = bridge.submit_command("set_building_enabled", {"building_id": ids[0], "enabled": false})
    _check(toggled.accepted, "set_building_enabled accepted: " + str(toggled.reason))
    _check(bridge.get_snapshot().buildings[ids[0]].enabled == false, "building disabled in snapshot")
    var reenabled: Dictionary = bridge.submit_command("set_building_enabled", {"building_id": ids[0], "enabled": true})
    _check(reenabled.accepted and bridge.get_snapshot().buildings[ids[0]].enabled == true, "building re-enabled in snapshot")

    # Advancing real time ticks the simulation and republishes snapshots.
    var counter := [0]
    bridge.snapshot_changed.connect(func(_s: Dictionary) -> void: counter[0] += 1)
    var tick_before := int(bridge.get_snapshot().clock.tick_index)
    bridge._process(2.0)
    var tick_after := int(bridge.get_snapshot().clock.tick_index)
    _check(tick_after >= tick_before + 10, "2 s at scale 5 advances at least 10 ticks (%d -> %d)" % [tick_before, tick_after])
    _check(counter[0] >= 1, "snapshot_changed emitted while advancing")
    _check(bridge.get_snapshot().buildings.size() == snap.buildings.size() + (1 if response.accepted else 0), "building set stable across ticks")

    # Development-only hooks are refused on the real simulation.
    var patch: Dictionary = bridge.dev_patch_building(ids[0], {"lifecycle": "destroyed"})
    _check(not patch.ok and patch.code == "module_unavailable", "dev patches refused on OutpostSimulation")

    # Pausing stops the clock.
    bridge.set_time_scale(0)
    var paused_tick := int(bridge.get_snapshot().clock.tick_index)
    bridge._process(3.0)
    _check(int(bridge.get_snapshot().clock.tick_index) == paused_tick, "paused clock does not tick")
    bridge.free()


func _check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures += 1
        printerr("INTEGRATION_CHECK_FAILED: ", label)


func _finish() -> void:
    _done = true
    if failures == 0:
        print("INTEGRATION_PASS checks=", checks)
        quit(0)
    else:
        print("INTEGRATION_FAIL failures=", failures, " checks=", checks)
        quit(1)
