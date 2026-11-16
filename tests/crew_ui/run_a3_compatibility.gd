extends SceneTree
## Production A3/crew integration and regressions found reviewing PR #6.
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

class InvalidProgressAdapter extends Adapter:
    var inject := false
    func plan_tick(snapshot: Dictionary, dt: float, context: Dictionary) -> Dictionary:
        var proposal: Dictionary = super.plan_tick(snapshot, dt, context)
        if inject and context.phase == "progress":
            proposal.crew_updates.crew_000001 = snapshot.crew.crew_000001.duplicate(true)
            proposal.crew_updates.crew_000001.health = 2.0
        return proposal

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
    check(spy.initialize_calls == 1, "facade initializes crew adapter")
    var snap = sim.get_snapshot()
    var partition = {"crew": snap.crew, "tasks": snap.tasks, "expeditions": snap.expeditions,
        "return_caches": {}, "completion_markers": {}, "private_counters": {}}
    check(spy.validate_state(spy.export_state(partition), snap).ok, "adapter validates actual A3 crew partition")
    check(sim.step(1).ok and spy.plan_calls == 2, "facade calls intent and progress in fixed tick order")
    for kind in ["assign_task", "cancel_task", "start_eva", "recall_eva", "place_building"]:
        var payload = {"assign_task": {"task_id": "task_test", "crew_ids": ["crew_000001"], "priority": 50},
            "cancel_task": {"task_id": "task_test"}, "start_eva": {"site_id": "site_cargo_a", "crew_ids": ["crew_000001"], "work_duration_s": 20, "oxygen_kg_per_crew": 0.12, "battery_kwh_per_crew": 0.006},
            "recall_eva": {"expedition_id": "expedition_test"}, "place_building": {"definition_id": "fixture_storage_module", "cell": [7,5], "rotation_quarters": 0}}[kind]
        var reply = sim.submit_command({"contract_version": "2.0.0", "command_id": "probe:" + kind, "type": kind, "payload": payload})
        check(reply.accepted, "real facade queues gameplay command " + kind)
    sim.process_pending_commands()
    check(sim.export_save().code == "module_unavailable", "production save remains explicitly unavailable")
    var hud = HUD.instantiate()
    hud.bind(sim, spy, bridge.world_service, sim._content.buildings)
    root.add_child(hud)
    check(hud._crew.item_count == 6 and "O₂" in hud._vitals.text, "HUD renders actual A3 roster/resources")
    hud._time(0)
    sim.process_pending_commands()
    check(sim.get_snapshot().clock.time_scale == 0 and hud._pending.is_empty(), "HUD pause resolves through actual A3 events")
    hud.select_crew("crew_000001")
    check(hud._launch.disabled, "busy crew cannot launch another expedition")
    hud.select_crew("crew_000002")
    hud._launch.pressed.emit()
    sim.process_pending_commands()
    check(sim.get_snapshot().expeditions.size() == 1, "site reservation prevents duplicate launches")
    var reference = Simulation.new()
    var reference_config = _read("res://tests/world/fixtures/landing_plain_init.json")
    check(reference.initialize(reference_config, null, null).ok, "reference A3 profile initializes")
    var reference_adapter = Adapter.new(bridge.world_service)
    check(reference_adapter.initialize(reference_config, reference.get_snapshot()).ok, "PR6 reads reference science without inventing EVA parameters")
    check(reference_adapter.estimate_eva({"site_id":"site_ice_hollow", "crew_ids":["crew_000001"], "work_duration_s":20.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006}, reference.get_snapshot()).code == "module_unavailable", "reference EVA disabled policy honored")
    _blocked_route(bridge, spy)
    _rate_mismatch(bridge, spy)
    _gameplay(bridge)
    _rollback(bridge)
    _cache_roundtrip(bridge)
    _reference_repairs()
    hud.free()
    bridge.free()
    for failure in failures: print("A3_CREW_FAIL ", failure)
    print("A3_CREW_RESULT checks=", checks, " failures=", failures.size())
    if failures.is_empty(): print("A3_CREW_PASS")
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
    var position: Array = proposal.crew_updates.get(trip.crew_ids[0], snap.crew[trip.crew_ids[0]]).position_m
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

var sequence := 0
func _command(sim: RefCounted, type: String, payload: Dictionary) -> Dictionary:
    sequence += 1
    var cmd := {"contract_version": "2.0.0", "command_id": "gameplay:%d" % sequence, "type": type, "payload": payload}
    var submitted: Dictionary = sim.submit_command(cmd)
    check(submitted.accepted, "enqueue " + type)
    sim.process_pending_commands()
    return sim.submit_command(cmd).result

func _gameplay(bridge: Node) -> void:
    var sim = Simulation.new()
    check(sim.initialize(_read(bridge.simulation_config_path), bridge.world_service, Adapter.new(bridge.world_service)).ok, "gameplay initializes production facade")
    var first_trip := _command(sim, "start_eva", {"site_id":"site_cargo_a", "crew_ids":["crew_000001", "crew_000002"], "work_duration_s":2.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006})
    check(first_trip.success, "salvage supplies construction materials")
    if not first_trip.success:
        print("FIRST_LAUNCH_ERROR ", first_trip)
        return
    for i in range(100):
        var tick: Dictionary = sim.step(1.0)
        if not tick.ok:
            check(false, "first EVA tick: " + tick.reason)
            return
        if sim.get_snapshot().expeditions[first_trip.data.expedition_id].status == "completed": break
    check(sim.get_snapshot().expeditions[first_trip.data.expedition_id].status == "completed", "first salvage returns to base")
    _command(sim, "set_time_scale", {"time_scale": 0})
    var original: Dictionary = sim.get_snapshot()
    var placed := _command(sim, "place_building", {"definition_id":"fixture_storage_module", "cell":[7,5], "rotation_quarters":0})
    check(placed.success, "construction command creates task and building")
    if not placed.success:
        print("CONSTRUCTION_ERROR ", placed)
        return
    var building: String = placed.data.building_id
    var task: String = placed.data.task_id
    var snap: Dictionary = sim.get_snapshot()
    var cost: Dictionary = sim._content.buildings.fixture_storage_module.build_cost
    for rid in cost: check(snap.resources[rid].amount == original.resources[rid].amount - cost[rid], "construction ledger debit " + rid)
    check(snap.resources.oxygen_kg.capacity == original.resources.oxygen_kg.capacity, "unfinished storage supplies no capacity")
    var rejected := _command(sim, "place_building", {"definition_id":"fixture_storage_module", "cell":[7,5], "rotation_quarters":0})
    check(not rejected.success and sim.get_snapshot() == snap, "rejected placement changes nothing")
    var cancelled := _command(sim, "cancel_task", {"task_id": task})
    check(cancelled.success and not sim.get_snapshot().buildings.has(building), "cancel construction removes unfinished module")
    for rid in cost: check(sim.get_snapshot().resources[rid].amount == original.resources[rid].amount, "construction refund exactly once " + rid)
    placed = _command(sim, "place_building", {"definition_id":"fixture_storage_module", "cell":[7,5], "rotation_quarters":0})
    task = placed.data.task_id
    building = placed.data.building_id
    var assignment := _command(sim, "assign_task", {"task_id": task, "crew_ids":["crew_000001"], "priority":50})
    check(assignment.success, "assign construction crew")
    _command(sim, "set_time_scale", {"time_scale": 1})
    for i in range(100):
        var tick: Dictionary = sim.step(1.0)
        if not tick.ok:
            check(false, "construction tick: " + tick.reason)
            return
        if sim.get_snapshot().tasks[task].status == "completed": break
    snap = sim.get_snapshot()
    check(snap.tasks[task].status == "completed" and snap.buildings[building].lifecycle == "commissioned", "labor commissions storage")
    check(snap.resources.oxygen_kg.capacity > original.resources.oxygen_kg.capacity, "commissioning adds storage capacity")
    check(snap.crew.crew_000001.task_id == null, "completed construction releases crew")
    var launch := _command(sim, "start_eva", {"site_id":"site_cargo_a", "crew_ids":["crew_000002"], "work_duration_s":2.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006})
    check(launch.success, "launch through production ledger")
    if not launch.success:
        print("LAUNCH_ERROR ", launch)
        return
    var trip: String = launch.data.expedition_id
    var site_before: Dictionary = sim.get_snapshot().sites.site_cargo_a.remaining_cargo.duplicate(true)
    for i in range(100):
        var tick: Dictionary = sim.step(1.0)
        if not tick.ok:
            check(false, "EVA tick: " + tick.reason)
            return
        if sim.get_snapshot().expeditions[trip].status in ["completed", "failed"]: break
    snap = sim.get_snapshot()
    check(snap.expeditions[trip].status == "completed", "EVA travels works collects returns")
    check(snap.crew.crew_000002.location_kind == "base" and snap.crew.crew_000002.expedition_id == null, "return releases astronaut")
    check(snap.sites.site_cargo_a.reserved_by_expedition_id == null, "return releases site")
    check(snap.expeditions[trip].cargo.is_empty() and snap.expeditions[trip].suit_stores.crew_000002.oxygen_kg == 0.0, "return credits all held balances")
    check(snap.sites.site_cargo_a.remaining_cargo != site_before, "salvage debits site once")
    var recall := _command(sim, "start_eva", {"site_id":"site_cargo_a", "crew_ids":["crew_000003"], "work_duration_s":2.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006})
    if not recall.success:
        check(false, "recall setup launches")
        return
    check(sim.step(1.0).ok, "recall advances outbound once")
    var recalled := _command(sim, "recall_eva", {"expedition_id":recall.data.expedition_id})
    check(recalled.success, "explicit recall routes to base")
    var returning: Dictionary = sim.get_snapshot()
    var repeated := _command(sim, "recall_eva", {"expedition_id":recall.data.expedition_id})
    check(repeated.success and sim.get_snapshot() == returning, "repeated recall is a gameplay no-op")
    for i in range(20):
        var tick: Dictionary = sim.step(1.0)
        if not tick.ok:
            check(false, "recall tick: " + tick.reason)
            return
        if sim.get_snapshot().expeditions[recall.data.expedition_id].status == "completed": break
    check(sim.get_snapshot().expeditions[recall.data.expedition_id].status == "completed", "recalled crew returns with no salvage reward")

func _rollback(bridge: Node) -> void:
    var adapter := InvalidProgressAdapter.new(bridge.world_service)
    var sim := Simulation.new()
    check(sim.initialize(_read(bridge.simulation_config_path), bridge.world_service, adapter).ok, "rollback setup")
    var before: Dictionary = sim.get_snapshot()
    var counters: Dictionary = sim._state.counters.duplicate(true)
    var receipts: Dictionary = sim._committed_effects.duplicate(true)
    var observed: Array = []
    sim.game_event.connect(func(event): observed.append(event))
    adapter.inject = true
    check(not sim.step(1.0).ok, "invalid phase-six proposal rejects tick")
    check(sim.get_snapshot() == before and sim._state.counters == counters and sim._committed_effects == receipts and observed.is_empty(), "failed crew tick rolls back power metabolism records counters and events")
    adapter.inject = false
    check(sim.step(1.0).ok and sim.get_snapshot().clock.tick_index == 1, "failed tick can retry cleanly")

func _cache_roundtrip(bridge: Node) -> void:
    var sim := Simulation.new()
    check(sim.initialize(_read(bridge.simulation_config_path), bridge.world_service, Adapter.new(bridge.world_service)).ok, "cache setup")
    # Synthetic test stock establishes a full warehouse through the actual ledger.
    var ledger := Ledger.new(sim._state, sim._content, sim._committed_effects, 0)
    var account: Dictionary = sim.get_snapshot().resources.alloy
    var quantity: float = account.capacity - account.amount
    check(ledger.apply_system({"effect_id":"test:fill", "kind":"external_source", "owner_id":"test", "scope":"one_time", "debits":{"source/environment/alloy":quantity}, "credits":{"base/alloy":quantity}}).ok, "test fills warehouse through ledger")
    var launched := _command(sim, "start_eva", {"site_id":"site_cargo_a", "crew_ids":["crew_000001", "crew_000002"], "work_duration_s":2.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006})
    check(launched.success, "full warehouse allows EVA launch")
    if not launched.success: return
    for i in range(80):
        var tick: Dictionary = sim.step(1.0)
        if not tick.ok:
            check(false, "cache EVA tick: " + tick.reason)
            return
        if sim.get_snapshot().expeditions[launched.data.expedition_id].status == "completed": break
    check(sim._state.return_caches.get(launched.data.expedition_id, {}).get("alloy") == 4.0 and sim.get_snapshot().resources.alloy.amount == account.capacity, "full warehouse caches exact cargo overflow")
    var placed := _command(sim, "place_building", {"definition_id":"fixture_storage_module", "cell":[7,5], "rotation_quarters":0})
    check(placed.success, "construction frees storage for cached cargo")
    check(sim.step(1.0).ok, "cache drain tick commits")
    check(sim.get_snapshot().resources.alloy.amount == account.capacity - 10.0 + 4.0 and sim._state.return_caches.is_empty(), "cache drains once when space opens")

func _reference_repairs() -> void:
    var bridge := Bridge.new()
    bridge.backend = Bridge.Backend.SIMULATION
    bridge.map_path = "res://data/maps/landing_plain.json"
    bridge.building_definition_dir = "res://data/buildings"
    bridge.simulation_config_path = "res://tests/world/fixtures/landing_plain_init.json"
    check(bridge.boot().ok, "authored crew runtime initializes")
    var sim: RefCounted = bridge._backend
    var snapshot: Dictionary = sim.get_snapshot()
    check(snapshot.crew.crew_000001.display_name == "Inez Solis", "authored map uses collaborator's named roster")
    check(not snapshot.tasks.is_empty(), "damaged authored modules get repair jobs")
    var task_id: String = snapshot.tasks.keys()[0]
    var target: String = snapshot.tasks[task_id].target_id
    check(_command(sim, "assign_task", {"task_id":task_id, "crew_ids":["crew_000001"], "priority":75}).success, "assign authored repair")
    for i in range(150):
        var tick: Dictionary = sim.step(1.0)
        if not tick.ok:
            check(false, "authored repair tick: " + tick.reason)
            break
        if sim.get_snapshot().tasks[task_id].status == "completed": break
    snapshot = sim.get_snapshot()
    check(snapshot.tasks[task_id].status == "completed" and snapshot.buildings[target].condition == 1.0 and snapshot.crew.crew_000001.task_id == null, "repair restores condition and releases crew")
    check(sim.supports_building("greenhouse_mk1") and not sim.get_capabilities().agriculture, "greenhouse production is available; full agriculture stays unavailable")
    bridge.free()
