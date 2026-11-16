class_name SimulationBridge
extends Node
## Integration point between the world scene and the authoritative simulation.
##
## Loads immutable map data and building definitions, builds the headless WorldService, and
## owns the current snapshot. Scenes subscribe to snapshot_changed and read; commands flow the
## other way through submit_command. The backend is either Task 01's OutpostSimulation (when
## scripts/simulation/simulation.gd exists and initializes) or the fixture stub for development.
## Nothing in this node, or in any scene below it, changes resource balances.

signal snapshot_changed(snapshot: Dictionary)
signal command_resolved(command_id: String, success: bool, reason: String)
signal game_event(event: Dictionary)
signal backend_changed(kind: String, detail: String)
signal simulation_failed(result: Dictionary)

enum Backend { AUTO, STUB, SIMULATION }

const SIMULATION_SCRIPT := "res://scripts/simulation/simulation.gd"
const StubScript := preload("res://scripts/world/dev/fixture_simulation_stub.gd")
const MapData := preload("res://scripts/world/map_data.gd")
const Definitions := preload("res://scripts/world/building_definitions.gd")
const Service := preload("res://scripts/world/world_service.gd")

@export var backend: Backend = Backend.AUTO
@export_file("*.json") var map_path: String = "res://tests/simulation/fixtures/definitions/map/fixture_flat_16.json"
@export_dir var building_definition_dir: String = "res://tests/simulation/fixtures/definitions/buildings"
@export_file("*.json") var fixture_snapshot_path: String = "res://tests/simulation/fixtures/snapshots/salvage_6crew_tick0.json"
@export_file("*.json") var simulation_config_path: String = "res://tests/simulation/fixtures/init/salvage_6crew.json"
@export var command_prefix: String = "world_dev"
@export var auto_advance: bool = true

# Play pacing: one game minute per real second at normal speed. The backend
# retains its deterministic one-second ticks and pause/normal/fast/fastest modes.
const GAME_SECONDS_PER_REAL_SECOND := 60.0
const PLAY_RATES := {0: 0.0, 1: 60.0, 5: 120.0, 20: 240.0}
const FRAME_WORK_USEC := 8000

var world_service: RefCounted
var map_data: RefCounted
var definitions: RefCounted
var snapshot: Dictionary = {}
var backend_kind: String = "none"
var backend_detail: String = ""
var last_error: Dictionary = {}
var crew_adapter: RefCounted = null  # Task 03 supplies this through attach_crew_adapter()

var _backend: RefCounted
var _command_counter: int = 0
var _ready_ok: bool = false


func _ready() -> void:
    var result := boot()
    if not result.ok:
        push_error("SimulationBridge boot failed: %s (%s)" % [result.reason, result.code])


func boot() -> Dictionary:
    var map_result: Dictionary = MapData.load_file(map_path)
    if not map_result.ok:
        return map_result
    map_data = map_result.map
    definitions = Definitions.new()
    var loaded: Dictionary = definitions.load_directory(building_definition_dir)
    if not loaded.ok:
        return loaded
    world_service = Service.new()
    world_service.setup(map_data, definitions)
    var attached := _attach_backend()
    if not attached.ok:
        return attached
    _ready_ok = true
    return {"ok": true, "code": "ok", "reason": ""}


func is_ready() -> bool:
    return _ready_ok


func load_world(new_map_path: String, new_definition_dir: String, new_snapshot_path: String, new_backend: int = Backend.AUTO, new_config_path: String = "") -> Dictionary:
    ## Rebuilds map, definitions, service and backend for another world. On failure the previous
    ## world stays active.
    if new_backend not in [Backend.AUTO, Backend.STUB, Backend.SIMULATION]:
        return {"ok": false, "code": "invalid_value", "reason": "Unknown backend selection."}
    # Prepare off to the side: failed loads publish no intermediate snapshot and
    # leave the previous world, signal connections and error state intact.
    var candidate = get_script().new()
    candidate.map_path = new_map_path
    candidate.building_definition_dir = new_definition_dir
    candidate.fixture_snapshot_path = new_snapshot_path
    candidate.simulation_config_path = new_config_path if not new_config_path.is_empty() else simulation_config_path
    candidate.backend = new_backend
    var result: Dictionary = candidate.boot()
    if not result.ok:
        candidate.free()
        return result
    var next_backend: RefCounted = candidate._backend
    candidate._disconnect_backend()
    _disconnect_backend()
    map_path = candidate.map_path
    building_definition_dir = candidate.building_definition_dir
    fixture_snapshot_path = candidate.fixture_snapshot_path
    simulation_config_path = candidate.simulation_config_path
    backend = new_backend as Backend
    world_service = candidate.world_service
    map_data = candidate.map_data
    definitions = candidate.definitions
    backend_kind = candidate.backend_kind
    backend_detail = candidate.backend_detail
    _backend = next_backend
    crew_adapter = candidate.crew_adapter
    _connect_backend()
    _ready_ok = true
    last_error = {}
    _publish(_backend.get_snapshot())
    backend_changed.emit(backend_kind, backend_detail)
    candidate.free()
    return result


func get_snapshot() -> Dictionary:
    return snapshot.duplicate(true)


func attach_crew_adapter(adapter: RefCounted) -> void:
    ## Task 03 hands its crew adapter here before the simulation backend initializes.
    crew_adapter = adapter


func attach_simulation(simulation: RefCounted, detail: String = "external") -> Dictionary:
    ## Lets an outer scene (or Task 01's harness) supply an already initialized facade.
    if simulation == null:
        return {"ok": false, "code": "invalid_value", "reason": "Not a simulation facade."}
    for method in ["get_snapshot", "submit_command", "process_pending_commands", "advance"]:
        if not simulation.has_method(method):
            return {"ok": false, "code": "invalid_value", "reason": "Simulation is missing " + method}
    var checked = _validate_snapshot(simulation.get_snapshot())
    if not checked.ok: return checked
    _disconnect_backend()
    _backend = simulation
    _connect_backend()
    backend_kind = "simulation"
    backend_detail = detail
    _publish(_backend.get_snapshot())
    backend_changed.emit(backend_kind, backend_detail)
    return {"ok": true, "code": "ok", "reason": ""}


func submit_command(type: String, payload: Dictionary) -> Dictionary:
    ## Wraps a payload in the contract envelope with a caller-unique command id and submits it.
    if _backend == null:
        return {"accepted": false, "command_id": null, "reason": "No simulation backend.", "code": "not_initialized",
            "receive_sequence": null, "status": "rejected", "duplicate": false, "result": null}
    _command_counter += 1
    var command := {
        "contract_version": "2.0.0",
        "command_id": "%s:%06d" % [command_prefix, _command_counter],
        "type": type,
        "payload": payload.duplicate(true),
    }
    var response: Dictionary = _backend.submit_command(command)
    if _backend.has_method("process_pending_commands"):
        _backend.process_pending_commands()
    return response


func submit_place_building(payload: Dictionary) -> Dictionary:
    return submit_command("place_building", payload)


func set_time_scale(scale: int) -> Dictionary:
    return submit_command("set_time_scale", {"time_scale": scale})


func validate_placement(request: Dictionary) -> Dictionary:
    return world_service.validate_placement(request, snapshot)


func query_route(from_cell: Array, to_cell: Array) -> Dictionary:
    return world_service.query_route({"from_cell": from_cell, "to_cell": to_cell}, snapshot)


func dev_patch_building(building_id: String, patch: Dictionary) -> Dictionary:
    ## Only the development stub supports forced visual states.
    if _backend != null and _backend.has_method("dev_patch_building"):
        return _backend.dev_patch_building(building_id, patch)
    return {"ok": false, "code": "module_unavailable", "reason": "Only the fixture stub supports dev patches."}


func _process(delta: float) -> void:
    if auto_advance and _backend != null and _backend.has_method("advance"):
        var result: Dictionary
        if _backend.has_method("advance_budgeted"):
            var scale: int = snapshot.get("clock", {}).get("time_scale", 0)
            var paced_delta := delta * float(PLAY_RATES.get(scale, 60.0)) / maxf(1.0, scale)
            result = _backend.advance_budgeted(paced_delta, FRAME_WORK_USEC)
        else:
            result = _backend.advance(delta * GAME_SECONDS_PER_REAL_SECOND)
        if not result.get("ok", false):
            last_error = result.duplicate(true)
            auto_advance = false # Preserve failed-tick backlog; avoid retrying every frame.
            simulation_failed.emit(last_error.duplicate(true))


# ---------------------------------------------------------------- backend selection

func _attach_backend() -> Dictionary:
    if backend != Backend.STUB and ResourceLoader.exists(SIMULATION_SCRIPT):
        var attempt := _try_simulation()
        if attempt.ok:
            return attempt
        return attempt # A present but broken simulation must not become a successful stub.
    elif backend == Backend.SIMULATION:
        return {"ok": false, "code": "module_unavailable", "reason": "scripts/simulation/simulation.gd is not present."}
    return _try_stub()


func _try_simulation() -> Dictionary:
    var script: Variant = load(SIMULATION_SCRIPT)
    if script == null:
        return {"ok": false, "code": "module_unavailable", "reason": "Could not load simulation script."}
    var simulation: RefCounted = script.new()
    if not FileAccess.file_exists(simulation_config_path):
        return {"ok": false, "code": "invalid_value", "reason": "Missing simulation config " + simulation_config_path}
    var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(simulation_config_path))
    if not config is Dictionary:
        return {"ok": false, "code": "invalid_schema", "reason": "Simulation config is not an object."}
    if not config.get("definition_manifest") is Dictionary:
        return {"ok": false, "code": "invalid_schema", "reason": "Simulation manifest is missing."}
    var world_files: Array = [map_path]
    for filename in DirAccess.get_files_at(building_definition_dir):
        if filename.ends_with(".json"): world_files.append(building_definition_dir.path_join(filename))
    for path in world_files:
        if config.definition_manifest.get(path) != FileAccess.get_sha256(path):
            return {"ok": false, "code": "definition_mismatch", "reason": "World content is absent from simulation manifest: " + path}
    if crew_adapter == null: crew_adapter = preload("res://scripts/crew/crew_adapter.gd").new(world_service)
    var result: Dictionary = simulation.initialize(config, world_service, crew_adapter)
    if not result.get("ok", false):
        return {"ok": false, "code": str(result.get("code", "internal_error")), "reason": str(result.get("reason", "initialize failed"))}
    var checked = _validate_snapshot(simulation.get_snapshot())
    if not checked.ok: return checked
    _disconnect_backend()
    _backend = simulation
    _connect_backend()
    backend_kind = "simulation"
    backend_detail = simulation_config_path.get_file()
    _publish(_backend.get_snapshot())
    backend_changed.emit(backend_kind, backend_detail)
    return {"ok": true, "code": "ok", "reason": ""}


func _try_stub() -> Dictionary:
    var stub: RefCounted = StubScript.new()
    var loaded: Dictionary = stub.load_fixture(fixture_snapshot_path, world_service)
    if not loaded.ok:
        return loaded
    var checked = _validate_snapshot(stub.get_snapshot())
    if not checked.ok: return checked
    _disconnect_backend()
    _backend = stub
    _connect_backend()
    backend_kind = "stub"
    backend_detail = fixture_snapshot_path.get_file()
    _publish(_backend.get_snapshot())
    backend_changed.emit(backend_kind, backend_detail)
    return {"ok": true, "code": "ok", "reason": ""}


func _connect_backend() -> void:
    if _backend.has_signal("state_changed"):
        _backend.state_changed.connect(_publish)
    if _backend.has_signal("command_resolved"):
        _backend.command_resolved.connect(_forward_command_resolved)
    if _backend.has_signal("game_event"):
        _backend.game_event.connect(_forward_game_event)


func _disconnect_backend() -> void:
    if _backend == null:
        return
    for connection in [["state_changed", _publish], ["command_resolved", _forward_command_resolved], ["game_event", _forward_game_event]]:
        if _backend.has_signal(connection[0]) and _backend.is_connected(connection[0], connection[1]):
            _backend.disconnect(connection[0], connection[1])
    _backend = null


func _publish(new_snapshot: Dictionary) -> void:
    if not new_snapshot.has("buildings"):
        return
    snapshot = new_snapshot.duplicate(true)
    snapshot_changed.emit(snapshot.duplicate(true))


func _forward_command_resolved(id: String, ok: bool, reason: String) -> void:
    command_resolved.emit(id, ok, reason)


func _forward_game_event(event: Dictionary) -> void:
    game_event.emit(event.duplicate(true))


func _validate_snapshot(value: Dictionary) -> Dictionary:
    if map_data == null or definitions == null:
        return {"ok": false, "code": "not_initialized", "reason": "Load world content before attaching a simulation."}
    if not value.get("map") is Dictionary or not value.get("buildings") is Dictionary:
        return {"ok": false, "code": "invalid_schema", "reason": "Backend has no initialized world snapshot."}
    if value.map.get("id") != map_data.id or value.map.get("revision") != map_data.revision:
        return {"ok": false, "code": "definition_mismatch", "reason": "Backend snapshot and rendered map differ."}
    for b in value.buildings.values():
        if not b is Dictionary or not definitions.has(b.get("definition_id", "")):
            return {"ok": false, "code": "unknown_definition", "reason": "Backend building has no matching world definition."}
    return {"ok": true, "code": "ok", "reason": ""}
