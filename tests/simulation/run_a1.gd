extends SceneTree
## Run with: Godot --headless --path . --script tests/simulation/run_a1.gd
const Simulation = preload("res://scripts/simulation/simulation.gd")
const Schemas = preload("res://scripts/simulation/command_schemas.gd")
const FIXTURES = "res://tests/simulation/fixtures/"
var checks = 0
var failures: Array[String] = []
var temporary_paths: Array[String] = []

func _initialize() -> void:
    _initialization()
    _invalid_content()
    _schemas()
    _commands()
    _clock()
    _callbacks()
    _journal_scaling()
    for path in temporary_paths: DirAccess.remove_absolute(path)
    if failures.is_empty():
        print("A1_PASS checks=", checks)
        quit(0)
    else:
        for failure in failures: print("A1_FAIL ", failure)
        quit(1)

func _read(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

func _new(name: String = "habitat_6crew") -> RefCounted:
    var simulation = Simulation.new()
    var result = simulation.initialize(_read(FIXTURES + "init/" + name + ".json"), null, null)
    _check(result.ok, "initialize " + name + ": " + result.reason)
    return simulation

func _check(value: bool, label: String) -> void:
    checks += 1
    if not value: failures.append(label)

func _equal(actual: Variant, expected: Variant, path: String) -> void:
    if Schemas.number(actual) and Schemas.number(expected):
        _check(abs(float(actual) - float(expected)) <= 1e-8 + 1e-9 * abs(float(expected)), path)
    elif actual is Dictionary and expected is Dictionary:
        _check(actual.size() == expected.size(), path + " keys")
        for key in expected:
            _check(actual.has(key), path + "/" + key + " exists")
            if actual.has(key): _equal(actual[key], expected[key], path + "/" + key)
    elif actual is Array and expected is Array:
        _check(actual.size() == expected.size(), path + " size")
        for index in mini(actual.size(), expected.size()):
            _equal(actual[index], expected[index], path + "/" + str(index))
    else:
        _check(actual == expected, path + ": " + str(actual) + " != " + str(expected))

func _command(id: String, type: String, payload: Dictionary) -> Dictionary:
    return {"contract_version": "2.0.0", "command_id": id, "type": type, "payload": payload}

func _scale(simulation: RefCounted, id: String, scale: Variant) -> Dictionary:
    return simulation.submit_command(_command(id, "set_time_scale", {"time_scale": scale}))

func _initialization() -> void:
    for name in ["habitat_5crew", "habitat_6crew", "habitat_9crew", "habitat_6crew_alt",
            "power_shortage_6crew", "salvage_6crew", "salvage_full_store_6crew", "storage_limits_6crew"]:
        var simulation = _new(name)
        _equal(simulation.get_snapshot(), _read(FIXTURES + "snapshots/" + name + "_tick0.json"), name)
        var snap = simulation.get_snapshot()
        snap.crew.clear()
        snap.resources.oxygen_kg.amount = -10
        _check(simulation.get_snapshot().crew.size() >= 5, "Detached nested crew map")
        _check(simulation.get_snapshot().resources.oxygen_kg.amount == 120, "Detached resource records")
    var config = _read(FIXTURES + "init/habitat_6crew.json")
    var simulation = Simulation.new()
    _check(simulation.step(1.0).code == "not_initialized", "Uninitialized tick rejected")
    _check(_scale(simulation, "x", 1).code == "not_initialized", "Uninitialized command rejected")
    for seed_value in ["-1", "9223372036854775808", "1.0", "not-a-seed"]:
        var bad = config.duplicate(true)
        bad.seed = seed_value
        _check(not simulation.initialize(bad, null, null).ok, "Invalid seed " + seed_value)
        _check(simulation.get_snapshot().code == "not_initialized", "Failed initialization is atomic")
    var bad_hash = config.duplicate(true)
    bad_hash.definition_manifest[config.scenario_path] = "0".repeat(64)
    _check(simulation.initialize(bad_hash, null, null).code == "definition_mismatch", "Bad content hash rejected")
    var bad_crew = config.duplicate(true)
    bad_crew.initial_crew_definition_ids[0] = "unknown"
    _check(simulation.initialize(bad_crew, null, null).code == "unknown_definition", "Unknown crew rejected")
    _check(simulation.initialize(config, null, null).ok, "Recover after failed initialization")
    var before = simulation.get_snapshot()
    _check(simulation.initialize(config, null, null).code == "invalid_state", "No reinitialization during campaign")
    _equal(simulation.get_snapshot(), before, "Reinitialize leaves original state")
    _check(simulation.export_save().code == "module_unavailable", "Save not falsely implemented")
    _check(simulation.import_save({}).code == "module_unavailable", "Load not falsely implemented")

func _schemas() -> void:
    var valid = [
        _command("p", "place_building", {"definition_id": "habitat", "cell": [-2.0, 4.0], "rotation_quarters": 1.0}),
        _command("e", "set_building_enabled", {"building_id": "building_000001", "enabled": false}),
        _command("a", "assign_task", {"task_id": "task_000001", "crew_ids": ["crew_000001"], "priority": 50.0}),
        _command("c", "cancel_task", {"task_id": "task_000001"}),
        _command("s", "start_eva", {"site_id": "site_a", "crew_ids": ["crew_000001"], "work_duration_s": 5,
            "oxygen_kg_per_crew": 1, "battery_kwh_per_crew": 0.1}),
        _command("r", "recall_eva", {"expedition_id": "expedition_000001"}),
        _command("t", "set_time_scale", {"time_scale": 5.0})]
    for command in valid:
        _check(Schemas.validate(command).ok, "Valid schema: " + command.type)
        var missing = command.duplicate(true)
        missing.payload.erase(missing.payload.keys()[0])
        _check(Schemas.validate(missing).code == "invalid_schema", "Missing payload key: " + command.type)
        var extra = command.duplicate(true)
        extra.payload.unrecognized = true
        _check(Schemas.validate(extra).code == "invalid_schema", "Unknown payload key: " + command.type)
        for field in command.payload:
            var wrong_type = command.duplicate(true)
            wrong_type.payload[field] = {"not": "a valid value"}
            _check(not Schemas.validate(wrong_type).ok, "Wrong payload type: " + command.type + "/" + field)
    var duplicate_crew = valid[2].duplicate(true)
    duplicate_crew.payload.crew_ids.append("crew_000001")
    _check(not Schemas.validate(duplicate_crew).ok, "Duplicate crew IDs rejected")
    for value in [-1, 2, 1.5, true, "5", INF, NAN]:
        _check(not Schemas.validate(_command("t", "set_time_scale", {"time_scale": value})).ok, "Invalid scale: " + str(value))
    var bad = valid[0].duplicate(true)
    bad.payload.cell = [0, 0.5]
    _check(not Schemas.validate(bad).ok, "Fractional cell rejected")
    bad = valid[4].duplicate(true)
    bad.payload.work_duration_s = NAN
    _check(not Schemas.validate(bad).ok, "NaN resource/duration rejected")
    bad = valid[0].duplicate(true)
    bad.contract_version = "1.0.0"
    _check(Schemas.validate(bad).code == "unsupported_contract", "Old contract rejected")

func _override_content(config: Dictionary, content: Dictionary, field: String = "scenario_path") -> Dictionary:
    var copy = config.duplicate(true)
    var path = "res://.godot/a1_test_content_%d_%d.json" % [OS.get_process_id(), temporary_paths.size()]
    DirAccess.make_dir_recursive_absolute("res://.godot")
    var file = FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(content, "", true, true))
    file.close()
    temporary_paths.append(path)
    copy.definition_manifest.erase(copy[field])
    copy[field] = path
    copy.definition_manifest[path] = FileAccess.get_sha256(path)
    return copy

func _invalid_content() -> void:
    var config = _read(FIXTURES + "init/habitat_6crew.json")
    var scenario = _read(config.scenario_path)
    var cases: Array = []
    var bad = scenario.duplicate(true)
    bad.starting_inventory.oxygen_kg = 300.0
    cases.append([bad, "capacity_exceeded"])
    bad = scenario.duplicate(true)
    bad.starting_inventory.alloy = 1.5
    cases.append([bad, "invalid_value"])
    bad = scenario.duplicate(true)
    bad.metadata = false
    cases.append([bad, "invalid_schema"])
    bad = scenario.duplicate(true)
    bad.starting_buildings[0].cell = [-1, 3]
    cases.append([bad, "invalid_value"])
    bad = scenario.duplicate(true)
    bad.starting_buildings[1].cell = bad.starting_buildings[0].cell.duplicate()
    cases.append([bad, "placement_blocked"])
    bad = scenario.duplicate(true)
    bad.starting_buildings[1].battery_stored_kwh = 41.0
    cases.append([bad, "capacity_exceeded"])
    bad = scenario.duplicate(true)
    bad.schema_version = 2
    cases.append([bad, "invalid_schema"])
    for item in cases:
        var simulation = Simulation.new()
        var changed = _override_content(config, item[0])
        var result = simulation.initialize(changed, null, null)
        _check(result.code == item[1], "Invalid content fails atomically: " + result.code + " / " + item[1])
        _check(simulation.get_snapshot().code == "not_initialized", "Bad content has no partially initialized colony")
    var science = _read(config.science_config_path)
    science.metadata = {"status": "unverified_real_science"}
    var simulation = Simulation.new()
    _check(simulation.initialize(_override_content(config, science, "science_config_path"), null, null).code == "module_unavailable", "Unadopted production science is not silently loaded")

func _commands() -> void:
    var simulation = _new()
    var events: Array = []
    var snapshots: Array = []
    simulation.game_event.connect(func(event): events.append(event))
    simulation.state_changed.connect(func(snapshot): snapshots.append(snapshot))
    var initial = simulation.get_snapshot()
    var cmd = _command("one", "set_building_enabled", {"building_id": "building_000001", "enabled": false})
    var acceptance = simulation.submit_command(cmd)
    _check(acceptance.accepted and acceptance.status == "queued" and acceptance.receive_sequence == 1, "Command queued")
    cmd.payload.enabled = true
    _equal(simulation.get_snapshot(), initial, "Submission leaves colony unchanged")
    var retry = _command("one", "set_building_enabled", {"building_id": "building_000001", "enabled": false})
    _check(simulation.submit_command(retry).duplicate, "Queued retry cached")
    _check(simulation.submit_command(cmd).code == "command_id_conflict", "Conflicting command rejected")
    simulation.process_pending_commands()
    _check(not simulation.get_snapshot().buildings.building_000001.enabled, "Detached command payload resolved")
    _check(events.size() == 1 and snapshots.size() == 1, "One resolution event and snapshot")
    var cached = simulation.submit_command(retry)
    _check(cached.duplicate and cached.status == "resolved" and cached.result.success, "Completed retry cached")
    cached.result.success = false
    _check(simulation.submit_command(retry).result.success, "Cached result detached")
    simulation.process_pending_commands()
    _check(events.size() == 1, "Retry emits nothing")
    simulation.submit_command(_command("missing", "set_building_enabled", {"building_id": "no_such_building", "enabled": false}))
    var before = simulation.get_snapshot()
    simulation.process_pending_commands()
    _equal(simulation.get_snapshot(), before, "Failed resolution has no colony effect")
    _check(events[-1].data.code == "unknown_entity", "Failure code in resolution event")
    _scale(simulation, "float-id", 5.0)
    _check(_scale(simulation, "float-id", 5).duplicate, "Integer normalization preserves deduplication")
    simulation.process_pending_commands()
    var unknown = simulation.submit_command(_command("future", "cancel_task", {"task_id": "task_000001"}))
    _check(unknown.code == "module_unavailable", "Missing handler explicitly rejected")
    _check(_scale(simulation, "future", 0).accepted, "Rejected command does not claim ID")
    simulation.process_pending_commands()
    var revision = simulation.get_snapshot().revision
    _scale(simulation, "same", 0)
    simulation.process_pending_commands()
    _check(simulation.get_snapshot().revision == revision, "No-op command does not revise colony")
    _check(simulation.get_snapshot().clock.tick_index == 0, "Control boundaries do not tick")

func _clock() -> void:
    var simulation = _new()
    _check(simulation.advance(0.4).ok, "Fractional accumulation")
    _check(simulation.get_snapshot().clock.tick_index == 0, "Fractional time does not tick")
    _scale(simulation, "pause", 0)
    simulation.advance(50.0)
    _check(simulation.get_snapshot().clock.tick_index == 0, "Paused wall time is not accumulated")
    simulation.step(1.0)
    _scale(simulation, "resume", 1)
    simulation.advance(0.6)
    _check(simulation.get_snapshot().clock.tick_index == 1, "Fractional accumulator survives pause")
    for delta in [0.0, -1.0, 0.5, INF, NAN]:
        _check(simulation.step(delta).code == "invalid_timestep", "Invalid step: " + str(delta))
    for delta in [-1.0, INF, NAN]:
        _check(simulation.advance(delta).code == "invalid_value", "Invalid wall delta: " + str(delta))
    var baseline = simulation.get_snapshot()
    _check(absf(baseline.resources.oxygen_kg.amount - 120.002) < 1e-8, "One committed A3 interval follows the clock")
    var backlog = _new()
    _scale(backlog, "fast", 20)
    backlog.advance(20.0)
    _check(backlog.get_snapshot().clock.tick_index == 120, "Tick budget capped at 120")
    backlog.advance(0.0)
    _check(backlog.get_snapshot().clock.tick_index == 240, "Backlog retained")
    _scale(backlog, "pause", 0)
    backlog.advance(0.0)
    _check(backlog.get_snapshot().clock.tick_index == 240, "Paused backlog does not drain")
    _scale(backlog, "resume", 1)
    backlog.advance(0.0)
    backlog.advance(0.0)
    _check(backlog.get_snapshot().clock.tick_index == 400, "Resume drains exact remaining backlog")
    var reference: Dictionary = {}
    for scale in [1, 5, 20]:
        var replay = _new()
        _scale(replay, "pause", 0)
        _scale(replay, "scale", scale)
        replay.advance(20.0 / scale)
        var snap = replay.get_snapshot()
        snap.clock.time_scale = 1
        if reference.is_empty(): reference = snap
        else: _equal(snap, reference, "Clock replay at scale " + str(scale))
    for scale in [1, 5, 20]:
        var replay = _new()
        _scale(replay, "pause", 0)
        _scale(replay, "scale", scale)
        for frame in int(80 / scale): replay.advance(0.25)
        var snap = replay.get_snapshot()
        snap.clock.time_scale = 1
        _equal(snap, reference, "Partitioned frame replay at scale " + str(scale))
    var validation = _new()
    _scale(validation, "pending-pause", 0)
    var before = validation.get_snapshot()
    validation.step(0.5)
    validation.advance(NAN)
    _equal(validation.get_snapshot(), before, "Invalid update does not resolve pending commands")
    validation.process_pending_commands()
    _check(validation.get_snapshot().clock.time_scale == 0, "Rejected update preserves accepted queue")
    var invalid_id = validation.submit_command(_command("", "set_time_scale", {"time_scale": 1}))
    _check(not invalid_id.accepted, "Empty command ID rejected")
    var object_id = _command("placeholder", "set_time_scale", {"time_scale": 1})
    object_id.command_id = {"invalid": "object"}
    _check(validation.submit_command(object_id).command_id == null, "Invalid command IDs do not leak objects into response records")

func _callbacks() -> void:
    var simulation = _new()
    var events: Array = []
    var guards: Array = []
    var snapshots: Array = []
    simulation.state_changed.connect(func(snapshot): snapshots.append(snapshot))
    simulation.game_event.connect(func(event):
        events.append(event.data.command_id)
        if event.data.command_id == "pause":
            _scale(simulation, "callback-resume", 5)
            guards.append(simulation.step(1.0).code)
            guards.append(simulation.advance(1.0).code)
            simulation.process_pending_commands()
            event.data.command_id = "mutated-listener-copy"
    )
    _scale(simulation, "pause", 0)
    simulation.step(1.0)
    _check(events == ["pause"] and simulation.get_snapshot().clock.tick_index == 0, "Callback command deferred")
    _check(guards == ["invalid_state", "invalid_state"], "Recursive public advancement rejected")
    simulation.step(1.0)
    _check(events == ["pause", "callback-resume"], "Callback command resolves at next boundary")
    _check(simulation.get_snapshot().clock.tick_index == 1 and snapshots.size() == 2, "One final snapshot per step")
    var fifo = _new()
    var order: Array = []
    fifo.command_resolved.connect(func(id, success, _reason): order.append([id, success]))
    fifo.submit_command(_command("off", "set_building_enabled", {"building_id": "building_000001", "enabled": false}))
    fifo.submit_command(_command("on", "set_building_enabled", {"building_id": "building_000001", "enabled": true}))
    fifo.submit_command(_command("unknown", "set_building_enabled", {"building_id": "missing", "enabled": true}))
    fifo.process_pending_commands()
    _check(order == [["off", true], ["on", true], ["unknown", false]], "FIFO resolution includes failures")
    _check(fifo.get_snapshot().buildings.building_000001.enabled, "Last FIFO setting wins")
    _check(fifo.get_snapshot().revision == 2, "Only successful mutations revise colony")

func _measure_ticks(simulation: RefCounted) -> float:
    # Median amortizes timer granularity and avoids a single scheduling outlier.
    var samples: Array[float] = []
    for batch in 3:
        var started = Time.get_ticks_usec()
        for tick in 32:
            if not simulation.step(1.0).ok: return INF
        samples.append(float(Time.get_ticks_usec() - started) / 32000.0)
    samples.sort()
    return samples[1]

func _journal_scaling() -> void:
    var sizes = [0, 250, 2000]
    if "--benchmark" in OS.get_cmdline_user_args(): sizes = [0, 250, 1000, 2000, 20000]
    var baseline_ms = 0.0
    var baseline_resolve_per_command_ms = 0.0
    for count in sizes:
        var simulation = _new()
        # White-box structural guard: transactional candidates must not carry
        # facade journal/queue metadata, even if timing happens to hide a copy.
        var candidate = simulation._state.clone()
        for property in candidate.get_property_list():
            _check(property.name not in ["journal", "pending", "next_receive_sequence"], "Gameplay clone excludes command history")
        var submit_started = Time.get_ticks_usec()
        for index in count:
            var accepted = _scale(simulation, "benchmark:%d" % index, 1)
            _check(accepted.accepted and accepted.receive_sequence == index + 1, "Large journal submission sequence")
        var submit_ms = float(Time.get_ticks_usec() - submit_started) / 1000.0
        var resolve_started = Time.get_ticks_usec()
        simulation.process_pending_commands()
        var resolve_ms = float(Time.get_ticks_usec() - resolve_started) / 1000.0
        if count == 250: baseline_resolve_per_command_ms = resolve_ms / count
        elif count > 250:
            _check(resolve_ms / count <= maxf(2.0, baseline_resolve_per_command_ms * 4.0), "Batch resolution stays linear in command count at %d commands" % count)
        # One no-op control warms up the tick path without growing the journal.
        simulation.step(1.0)
        var per_tick_ms = _measure_ticks(simulation)
        if count == 0: baseline_ms = per_tick_ms
        else:
            _check(per_tick_ms <= maxf(2.0, baseline_ms * 8.0), "Tick cost independent of retained journal at %d commands" % count)
            for index in [0, count - 1]:
                var cached = _scale(simulation, "benchmark:%d" % index, 1.0)
                _check(cached.duplicate and cached.status == "resolved" and cached.result.success, "Old cached result survives transactions")
            var before = simulation.get_snapshot()
            simulation.submit_command(_command("benchmark:failed", "set_building_enabled", {"building_id": "missing", "enabled": false}))
            simulation.process_pending_commands()
            _equal(simulation.get_snapshot(), before, "Failed large-history candidate rolls back gameplay")
            _check(_scale(simulation, "benchmark:0", 1).result.success, "Failure preserves unrelated journal entries")
        print("A1_BENCH commands=%d tick_ms=%.4f resolve_ms=%.3f submit_ms=%.3f" % [count, per_tick_ms, resolve_ms, submit_ms])
