extends SceneTree
const Bridge = preload("res://scripts/world/sim_bridge.gd")
const Placement = preload("res://scripts/world/placement_controller.gd")
const Simulation = preload("res://scripts/simulation/simulation.gd")
var checks = 0
var failures: Array[String] = []

class FailedTickSimulation extends Simulation:
    var attempts = 0
    func _tick() -> Dictionary:
        attempts += 1
        return {"ok": false, "code": "internal_error", "reason": "Forced integration failure"}

func _initialize() -> void:
    var bridge = Bridge.new()
    bridge.backend = Bridge.Backend.SIMULATION
    _check(bridge.boot().ok, "real backend boots")
    var original = bridge.get_snapshot().duplicate(true)
    var returned = bridge.get_snapshot()
    returned.buildings.clear()
    _check(bridge.get_snapshot() == original, "snapshot reads detached")
    # Repair only the test's deliberately mutated cache before checking next case.
    bridge._publish(bridge._backend.get_snapshot())
    var listener = func(s): s.resources.clear()
    bridge.snapshot_changed.connect(listener)
    bridge._publish(bridge._backend.get_snapshot())
    _check(not bridge.get_snapshot().resources.is_empty(), "signal payload detached from cached view")
    bridge.snapshot_changed.disconnect(listener)
    bridge._publish(bridge._backend.get_snapshot())
    var previous_backend = bridge._backend
    var forwarded: Array = []
    bridge.command_resolved.connect(func(_id, _ok, _reason): forwarded.append("command"))
    bridge.game_event.connect(func(_event): forwarded.append("event"))
    _check(bridge.load_world(bridge.map_path, bridge.building_definition_dir, bridge.fixture_snapshot_path, Bridge.Backend.SIMULATION).ok, "reload world")
    var current = bridge.get_snapshot().duplicate(true)
    var stale = previous_backend.get_snapshot()
    stale.campaign_id = "retired_backend"
    previous_backend.state_changed.emit(stale)
    previous_backend.command_resolved.emit("retired", true, "")
    previous_backend.game_event.emit({"type": "retired"})
    _check(bridge.get_snapshot() == current and forwarded.is_empty(), "retired backend cannot publish snapshots or events")
    var bad = Bridge.new()
    bad.backend = Bridge.Backend.SIMULATION
    bad.map_path = "res://data/maps/landing_plain.json"
    bad.building_definition_dir = "res://data/buildings"
    _check(not bad.boot().ok, "mismatched map/config refuses real backend")
    bad.free()
    var auto = Bridge.new()
    auto.simulation_config_path = "res://missing_config.json"
    _check(not auto.boot().ok and auto.backend_kind != "stub", "AUTO cannot hide broken simulation behind a visual stub")
    auto.free()
    var placement = Placement.new()
    placement.setup(bridge.world_service, null, null, Callable(bridge, "get_snapshot"))
    placement.setup(bridge.world_service, null, null, Callable(bridge, "get_snapshot"))
    _check(placement.get_child_count() == 2, "world reload reuses cursor/ghost instead of leaking nodes")
    placement.free()
    var failing = FailedTickSimulation.new()
    var config = JSON.parse_string(FileAccess.get_file_as_string(bridge.simulation_config_path))
    _check(failing.initialize(config, bridge.world_service, null).ok, "failure backend initialized")
    _check(bridge.attach_simulation(failing).ok, "attach matching facade")
    var errors: Array = []
    bridge.simulation_failed.connect(func(result): errors.append(result))
    var before_failure = bridge.get_snapshot()
    bridge._process(1.0)
    bridge._process(1.0)
    _check(not bridge.auto_advance and failing.attempts == 1 and errors.size() == 1, "tick failure surfaced once and automatic retries stop")
    _check(bridge.get_snapshot() == before_failure and bridge.last_error.code == "internal_error", "tick failure keeps last committed view")
    var connection_count = failing.state_changed.get_connections().size()
    _check(not bridge.load_world(bridge.map_path, bridge.building_definition_dir, bridge.fixture_snapshot_path, Bridge.Backend.SIMULATION, "res://missing_config.json").ok, "failed replacement reports error")
    _check(bridge._backend == failing and failing.state_changed.get_connections().size() == connection_count and not bridge.auto_advance and bridge.last_error.code == "internal_error", "failed replacement preserves backend connections and error state")
    var uninitialized = Simulation.new()
    _check(not bridge.attach_simulation(uninitialized).ok and bridge._backend == failing, "uninitialized facade cannot replace current world")
    _check(bridge.load_world(bridge.map_path, bridge.building_definition_dir, bridge.fixture_snapshot_path, Bridge.Backend.SIMULATION).ok, "world can restart after tick failure")
    _check(bridge.last_error.is_empty(), "successful replacement clears runtime error")
    bridge.free()
    if failures.is_empty():
        print("BRIDGE_PASS checks=", checks)
        quit(0)
    else:
        for failure in failures: print("BRIDGE_FAIL ", failure)
        quit(1)

func _check(condition: bool, label: String) -> void:
    checks += 1
    if not condition: failures.append(label)
