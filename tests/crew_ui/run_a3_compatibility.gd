extends SceneTree
## Review probe for PR #6 f00efcf against A3 152546f. No production wiring or fixes.
const Simulation = preload("res://scripts/simulation/simulation.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const Bridge = preload("res://scripts/world/sim_bridge.gd")
const Ledger = preload("res://scripts/simulation/resource_ledger.gd")
const Demand = preload("res://scripts/systems/crew_demand_system.gd")
const HUD = preload("res://scenes/ui/outpost_hud.tscn")
const Routes = preload("res://scripts/crew/crew_routes.gd")
const FIX = "res://tests/simulation/fixtures/"
var checks = 0
var failures: Array[String] = []

class SpyAdapter extends Adapter:
    var initialize_calls = 0
    var plan_calls = 0
    func initialize(config: Dictionary, snapshot: Dictionary) -> Dictionary:
        initialize_calls += 1
        return super.initialize(config, snapshot)
    func plan_tick(snapshot: Dictionary, dt: float, context: Dictionary) -> Dictionary:
        plan_calls += 1
        return super.plan_tick(snapshot, dt, context)

func _initialize() -> void:
    call_deferred("_run")

func _read(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition: failures.append(label)

func _run() -> void:
    var bridge = Bridge.new()
    bridge.backend = Bridge.Backend.SIMULATION
    bridge.auto_advance = false
    check(bridge.boot().ok, "A3 bridge boots with PR6 files")
    var config = _read(bridge.simulation_config_path)
    var sim = Simulation.new()
    var spy = SpyAdapter.new(bridge.world_service)
    check(sim.initialize(config, bridge.world_service, spy).ok, "A3 accepts supplied adapter reference")
    check(spy.initialize_calls == 0, "observe integration gap: A3 does not initialize adapter")
    check(spy.initialize(config, sim.get_snapshot()).ok, "PR6 adapter manually initializes on actual A3 fixture snapshot")
    var snap = sim.get_snapshot()
    var partition = {"crew": snap.crew, "tasks": snap.tasks, "expeditions": snap.expeditions,
        "return_caches": {}, "completion_markers": {}, "private_counters": {}}
    check(spy.validate_state(spy.export_state(partition), snap).ok, "adapter validates actual A3 crew partition")
    check(sim.step(1).ok and spy.plan_calls == 0, "observe integration gap: A3 ticks do not request crew proposals")
    for kind in ["assign_task", "cancel_task", "start_eva", "recall_eva", "place_building"]:
        var payload = {"assign_task": {"task_id": "task_test", "crew_ids": ["crew_000001"], "priority": 50},
            "cancel_task": {"task_id": "task_test"}, "start_eva": {"site_id": "site_cargo_a", "crew_ids": ["crew_000001"], "work_duration_s": 20, "oxygen_kg_per_crew": 0.12, "battery_kwh_per_crew": 0.006},
            "recall_eva": {"expedition_id": "expedition_test"}, "place_building": {"definition_id": "fixture_storage_module", "cell": [7,5], "rotation_quarters": 0}}[kind]
        var reply = sim.submit_command({"contract_version": "2.0.0", "command_id": "probe:" + kind, "type": kind, "payload": payload})
        check(not reply.accepted and reply.code == "module_unavailable", "observe integration gap: unavailable real facade command " + kind)
    check(sim.export_save().code == "module_unavailable", "production save remains explicitly unavailable")
    var hud = HUD.instantiate()
    hud.bind(sim, spy, bridge.world_service, sim._content.buildings)
    root.add_child(hud)
    check(hud._crew.item_count == 6 and "O₂" in hud._vitals.text, "HUD renders actual A3 roster/resources")
    hud._time(0)
    sim.process_pending_commands()
    check(sim.get_snapshot().clock.time_scale == 0 and hud._pending.is_empty(), "HUD pause resolves through actual A3 events")
    hud.select_crew("crew_000001")
    check(not hud._launch.disabled, "observe integration gap: synthetic EVA preview is available before facade handler is wired")
    hud._launch.pressed.emit()
    check("not implemented" in hud._status.text and sim.get_snapshot().expeditions.is_empty(), "actual A3 refuses HUD launch without stock mutation")
    var reference = Simulation.new()
    var reference_config = _read("res://tests/world/fixtures/landing_plain_init.json")
    check(reference.initialize(reference_config, null, null).ok, "reference A3 profile initializes")
    var reference_adapter = Adapter.new(bridge.world_service)
    check(reference_adapter.initialize(reference_config, reference.get_snapshot()).ok, "PR6 reads reference science without inventing EVA parameters")
    check(reference_adapter.estimate_eva({"site_id":"site_ice_hollow", "crew_ids":["crew_000001"], "work_duration_s":20.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006}, reference.get_snapshot()).code == "module_unavailable", "reference EVA disabled policy honored")
    _blocked_route(bridge, spy)
    _rate_mismatch(bridge, spy)
    hud.free()
    bridge.free()
    for failure in failures: print("A3_CREW_FAIL ", failure)
    print("A3_CREW_RESULT checks=", checks, " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)

func _blocked_route(bridge: Node, adapter: RefCounted) -> void:
    var snap = _read(FIX + "snapshots/eva_outbound_tick1.json")
    var trip: Dictionary = snap.expeditions.expedition_000001
    trip.route_progress_m = 3.0
    for cid in trip.crew_ids: snap.crew[cid].position_m = Routes.position(trip.route_waypoints_m, 3.0)
    var request = {"definition_id": "fixture_electrolyzer", "cell": [6,8], "rotation_quarters": 0}
    var preview = bridge.world_service.validate_placement(request, snap)
    check(preview.valid, "real WorldService allows a detour-preserving placement ahead of active EVA")
    var added: Dictionary = snap.buildings.building_000003.duplicate(true)
    added.merge({"id":"building_000006", "cell":[6,8], "lifecycle":"constructing", "construction_progress":0.0, "construction_task_id":"task_000002"}, true)
    snap.buildings[added.id] = added
    snap.tasks.task_000002 = {"id":"task_000002", "kind":"construct", "target_id":added.id, "status":"queued", "priority":50, "crew_required":1, "assigned_crew_ids":[], "required_work_s":10.0, "completed_work_s":0.0, "blocked_code":null, "expedition_id":null}
    var proposal = adapter.plan_tick(snap, 1.0, {"phase":"progress", "tick_index":1, "unmet_needs":{}})
    var position: Array = proposal.crew_updates[trip.crew_ids[0]].position_m
    var next_cell = Routes.cell(position)
    print("BLOCKED_ROUTE_REPRO placement_valid=", preview.valid, " proposed_position=", position, " cell=", next_cell)
    check(next_cell != [6,8], "EVA must not advance into a newly occupied route cell when a detour exists")

func _rate_mismatch(bridge: Node, adapter: RefCounted) -> void:
    var sim = Simulation.new()
    check(sim.initialize(_read(bridge.simulation_config_path), bridge.world_service, null).ok, "demand mismatch setup")
    var snap = _read(FIX + "snapshots/eva_working_tick10.json")
    sim._state.records = snap.duplicate(true)
    sim._state.records.erase("rng")
    sim._state.per_battery_energy = {"building_000002":snap.resources.energy_kwh.amount}
    sim._content.science.eva_policy.phase_rates_per_s = {"working":{"oxygen_kg":0.001}}
    adapter._eva.policy.phase_rates_per_s = {"working":{"oxygen_kg":0.001}}
    var before: float = sim._state.records.expeditions.expedition_000001.suit_stores.crew_000001.oxygen_kg
    var predicted: float = adapter._eva.rate(snap, "working", "oxygen_kg")
    var ledger = Ledger.new(sim._state, sim._content, {}, 10)
    var result = Demand.new().run(sim._state, sim._content, ledger)
    check(result.ok, "actual A3 demand accepts phase-specific policy input")
    var consumed: float = before - sim._state.records.expeditions.expedition_000001.suit_stores.crew_000001.oxygen_kg
    print("WORKLOAD_RATE_REPRO forecast_per_s=", predicted, " actual_A3_per_s=", consumed)
    check(absf(consumed - predicted) < 1e-10, "forecast workload and A3 demand must use the same oxygen rate")
