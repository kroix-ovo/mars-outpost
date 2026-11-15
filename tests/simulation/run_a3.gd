extends SceneTree
const Simulation = preload("res://scripts/simulation/simulation.gd")
const Demand = preload("res://scripts/systems/crew_demand_system.gd")
const FIX = "res://tests/simulation/fixtures/"
var checks = 0
var failures: Array[String] = []
var temporary_paths: Array[String] = []

class FailedDemandSimulation extends Simulation:
    var fail_tick = true
    var staged_ledger: RefCounted
    func _run_crew_demand(candidate: RefCounted, ledger: RefCounted) -> Dictionary:
        var result = super._run_crew_demand(candidate, ledger)
        if not result.ok: return result
        staged_ledger = ledger
        result = ledger.apply_system({"effect_id": "test:phase5:once", "kind": "external_source", "owner_id": "test", "scope": "one_time",
            "debits": {"source/environment/co2_kg": 1.0}, "credits": {"base/co2_kg": 1.0}})
        candidate.rng.randi()
        candidate.allocate("event")
        if fail_tick: candidate.records.resources.food_kcal.amount = -1.0
        return result

func _initialize() -> void:
    _oracle()
    _limits()
    _shortages()
    _suits()
    _reference_profile()
    _validation()
    _rollback()
    _time()
    for path in temporary_paths: DirAccess.remove_absolute(path)
    if failures.is_empty():
        print("A3_PASS checks=", checks)
        quit(0)
    else:
        for failure in failures: print("A3_FAIL ", failure)
        quit(1)

func _check(value: bool, label: String) -> void:
    checks += 1
    if not value: failures.append(label)

func _near(actual: float, expected: float, label: String) -> void:
    _check(is_finite(actual) and absf(actual - expected) <= 1e-8 + 1e-9 * absf(expected), label + " got=" + str(actual) + " expected=" + str(expected))

func _equal(actual: Variant, expected: Variant, path: String) -> void:
    if (actual is float or actual is int) and (expected is float or expected is int): _near(actual, expected, path)
    elif actual is Dictionary and expected is Dictionary:
        _check(actual.size() == expected.size(), path + " keys")
        for key in expected:
            _check(actual.has(key), path + "/" + str(key))
            if actual.has(key): _equal(actual[key], expected[key], path + "/" + str(key))
    elif actual is Array and expected is Array:
        _check(actual.size() == expected.size(), path + " length")
        for i in mini(actual.size(), expected.size()): _equal(actual[i], expected[i], path + "/" + str(i))
    else: _check(actual == expected, path + " equality")

func _read(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

func _new(name: String = "habitat_6crew") -> RefCounted:
    var sim = Simulation.new()
    var result = sim.initialize(_read(FIX + "init/" + name + ".json"), null, null)
    _check(result.ok, "initialize " + name + ": " + result.reason)
    return sim

func _ticks(sim: RefCounted, count: int) -> void:
    for i in count:
        var result = sim.step(1.0)
        _check(result.ok, "tick " + str(i) + ": " + result.reason)
        if not result.ok: return

func _compare(sim: RefCounted, filename: String) -> void:
    var snap = sim.get_snapshot()
    var expected = _read(FIX + "snapshots/" + filename + ".json")
    _equal(snap.resources, expected.resources, filename + "/resources")
    _equal(snap.power, expected.power, filename + "/power")
    for id in expected.buildings:
        for key in ["power_requested_kw", "power_served_kw", "operating_fraction", "blocking_codes"]:
            _equal(snap.buildings[id][key], expected.buildings[id][key], filename + "/" + id + "/" + key)
    var actual_alerts: Dictionary = {}
    for a in snap.alerts: actual_alerts[a.id] = a.first_tick
    for a in expected.alerts:
        _check(actual_alerts.has(a.id), filename + "/alert " + a.id)
        if actual_alerts.has(a.id): _check(actual_alerts[a.id] == a.first_tick, filename + "/first_tick " + a.id)

func _oracle() -> void:
    for crew in [5, 6, 9]:
        var sim = _new("habitat_%dcrew" % crew)
        _ticks(sim, 1)
        _compare(sim, "habitat_%dcrew_tick1" % crew)
        _ticks(sim, 99)
        _compare(sim, "habitat_%dcrew_tick100" % crew)
        _ticks(sim, 500)
        _compare(sim, "habitat_%dcrew_tick600" % crew)
        _near(sim.get_snapshot().resources.oxygen_kg.amount, 120 + (0.008 - crew * 0.001) * 600, "independent O2 600-tick balance")
        _near(sim.get_snapshot().resources.food_kcal.amount, 100000 - crew * 600, "independent food balance")
        _check(sim._committed_effects.is_empty(), "no per-second retained effects")
    var storage = _new("storage_limits_6crew")
    storage.submit_command(_read(FIX + "scripts/storage_limits.json").steps[0].command)
    _ticks(storage, 3)
    _compare(storage, "storage_limits_tick3")
    _near(storage._state.crew_demand.wastewater_overflow_kg, 0.006, "independent obligatory wastewater overflow")
    _ticks(storage, 3)
    _compare(storage, "storage_limits_tick6")
    var power = _new("power_shortage_6crew")
    _ticks(power, 4)
    _compare(power, "power_charged_tick4")
    power.submit_command({"contract_version": "2.0.0", "command_id": "off", "type": "set_building_enabled", "payload": {"building_id": "building_000001", "enabled": false}})
    _ticks(power, 5)
    _compare(power, "power_partial_tick9")
    _ticks(power, 1)
    _compare(power, "power_none_tick10")
    _ticks(power, 10)
    power.submit_command({"contract_version": "2.0.0", "command_id": "on", "type": "set_building_enabled", "payload": {"building_id": "building_000001", "enabled": true}})
    _ticks(power, 1)
    _compare(power, "power_restored_tick21")

func _limits() -> void:
    var sim = _new()
    sim._state.records.buildings.building_000003.condition = 0.5
    _ticks(sim, 1)
    _near(sim.get_snapshot().resources.oxygen_kg.amount, 119.998, "condition applied once to chemical output")
    _near(sim.get_snapshot().buildings.building_000003.operating_fraction, 0.5, "single process fraction")
    _near(sim._state.power_flows["sink/idle_power_loss/energy_kwh"], 0.5 / 3600, "unused allocated power explicit loss")
    var total = sim._state.power_flows["sink/load/energy_kwh"] + sim._state.power_flows["sink/idle_power_loss/energy_kwh"]
    _near(total, 2.0 / 3600, "load reclassification conserves allocated electricity")
    sim = _new()
    sim._state.records.resources.hydrogen_kg.amount = sim._state.records.resources.hydrogen_kg.capacity
    _ticks(sim, 1)
    _near(sim.get_snapshot().buildings.building_000003.operating_fraction, 0, "full H2 throttles whole electrolyzer")
    _near(sim.get_snapshot().resources.oxygen_kg.amount, 119.994, "full H2 creates no O2")
    _near(sim.get_snapshot().resources.potable_water_kg.amount, 500, "full H2 spends no process water")
    sim = _new()
    sim._state.records.resources.oxygen_kg.amount = sim._state.records.resources.oxygen_kg.capacity
    _ticks(sim, 1)
    _near(sim.get_snapshot().resources.hydrogen_kg.amount, 0, "full O2 creates no H2")
    _near(sim.get_snapshot().buildings.building_000003.operating_fraction, 0, "phase order does not anticipate later crew demand")
    sim = _new()
    var b: Dictionary = sim._state.records.buildings.building_000003.duplicate(true)
    b.id = "building_000007"
    sim._state.records.buildings[b.id] = b
    sim._state.records.resources.potable_water_kg.amount = 0.009
    sim._state.records.buildings.building_000004.enabled = false
    _ticks(sim, 1)
    _near(sim.get_snapshot().buildings.building_000003.operating_fraction, 1, "equal-priority input competition stable ID first")
    _near(sim.get_snapshot().buildings[b.id].operating_fraction, 0, "later process cannot spend same water")
    sim = _new()
    sim._state.records.resources.potable_water_kg.reserved = 500
    sim._state.records.buildings.building_000004.enabled = false
    _ticks(sim, 1)
    _near(sim.get_snapshot().buildings.building_000003.operating_fraction, 0, "process respects reserved stock")
    _check(sim._state.crew_demand.unmet_needs.crew_000001.has("water"), "crew cannot spend reserved water")
    sim = _new()
    # A deliberately lossy recycler remains explicit rather than manufacturing
    # full-recovery water. The unused 10% is not available to another process.
    sim._content.buildings.fixture_water_recycler.process.outputs_per_s.potable_water_kg = 0.0108
    _ticks(sim, 1)
    _near(sim._state.life_support_flows["sink/recycler_loss/wastewater_kg"], 0.0012, "explicit recycler loss")
    _near(sim.get_snapshot().resources.potable_water_kg.amount, 499.9898, "loss reduces retained water")
    _near(sim._state.life_support_flows["sink/process_removal/co2_kg"], 0.006, "CO2 scrubbing sink explicit")

func _shortages() -> void:
    var sim = _new()
    for b in sim._state.records.buildings.values(): b.enabled = false
    sim._state.records.crew.crew_000005.status = "dead"
    sim._state.records.crew.crew_000006.status = "incapacitated"
    sim._state.records.resources.oxygen_kg.amount = 0.003
    var events: Array = []
    sim.game_event.connect(func(event): events.append(event))
    _ticks(sim, 1)
    _check(sim._state.crew_demand.requested.size() == 5, "dead crew excluded; incapacitated crew still consume")
    for id in sim._state.crew_demand.provided:
        _near(sim._state.crew_demand.provided[id].oxygen_kg, 0.0006, "proportional limited oxygen")
        _check(sim._state.crew_demand.unmet_needs[id] == ["oxygen"], "per-crew unmet need")
    _near(sim.get_snapshot().resources.oxygen_kg.amount, 0, "scarce resource never negative")
    _near(sim.get_snapshot().resources.co2_kg.amount, 0.503, "CO2 output scales with delivered O2")
    _check(events.size() == 5, "one shortage-entry event per affected living crew")
    _ticks(sim, 1)
    _check(events.size() == 5, "unchanged shortage does not flood events")
    _near(sim.get_snapshot().resources.co2_kg.amount, 0.503, "no modeled CO2 output from empty O2 input")
    _check(sim.get_snapshot().alerts.any(func(a): return a.id == "low_oxygen"), "oxygen shortage alert")
    # CO2 is an independent accumulator and warning, even with full O2 reserves.
    sim._state.records.resources.oxygen_kg.amount = sim._state.records.resources.oxygen_kg.capacity
    sim._state.records.resources.co2_kg.amount = 10
    _ticks(sim, 1)
    _check(sim.get_snapshot().alerts.any(func(a): return a.id == "co2_high"), "full oxygen does not hide CO2 warning")
    _check(sim.get_snapshot().resources.co2_kg.capacity == null and sim.get_snapshot().resources.co2_kg.amount > 10, "CO2 never storage-clamped")
    var waste = sim._state.records.resources.wastewater_kg
    waste.amount = waste.capacity
    _ticks(sim, 1)
    _near(sim._state.crew_demand.flows["sink/capacity_overflow/wastewater_kg"], 0.010, "full wastewater has explicit unrecoverable overflow")
    _check(sim.get_snapshot().alerts.any(func(a): return a.id == "storage_full:wastewater_kg"), "overflow alert")
    sim._state.records.resources.food_kcal.amount = 0
    sim._state.records.resources.potable_water_kg.amount = 0
    _ticks(sim, 1)
    _near(sim._state.crew_demand.wastewater_overflow_kg, 0, "empty water/food cannot mint wastewater")
    _check(not sim.get_snapshot().alerts.any(func(a): return a.id == "storage_full:wastewater_kg"), "resolved overflow alert clears")

func _suits() -> void:
    var sim = _new()
    for b in sim._state.records.buildings.values(): b.enabled = false
    var ids = ["crew_000001", "crew_000002"]
    for id in ids:
        sim._state.records.crew[id].location_kind = "eva"
        sim._state.records.crew[id].status = "eva"
        sim._state.records.crew[id].expedition_id = "expedition_test"
    sim._state.records.expeditions.expedition_test = {"crew_ids": ids, "cargo": {}, "suit_stores": {
        "crew_000001": {"oxygen_kg": 0.001, "battery_kwh": 0.00005}, "crew_000002": {"oxygen_kg": 0.1, "battery_kwh": 0.005}}}
    var initial_energy: float = sim.get_snapshot().resources.energy_kwh.amount
    _ticks(sim, 1)
    var suits: Dictionary = sim._state.records.expeditions.expedition_test.suit_stores
    _near(suits.crew_000001.oxygen_kg, 0, "individual suit oxygen exhausted")
    _near(suits.crew_000001.battery_kwh, 0, "individual suit battery exhausted")
    _near(suits.crew_000002.oxygen_kg, 0.098, "other suit not pooled")
    _near(sim.get_snapshot().resources.oxygen_kg.amount, 119.996, "EVA does not also draw base oxygen")
    _near(sim.get_snapshot().resources.food_kcal.amount, 99996, "synthetic EVA policy avoids base food double draw")
    _near(sim.get_snapshot().resources.energy_kwh.amount, initial_energy, "suit energy is not also debited from base batteries")
    _equal(sim._state.crew_demand.unmet_needs.crew_000001, ["oxygen", "suit_energy"], "suit unmet needs")
    sim._content.science.crew_metabolism.eva_draws_base_water_and_food = true
    _ticks(sim, 1)
    _near(sim.get_snapshot().resources.food_kcal.amount, 99990, "configured EVA base-food policy applied once")
    suits.crew_000002.erase("battery_kwh") # Previous candidate is detached: deliberately corrupt the current one instead.
    sim._state.records.expeditions.expedition_test.suit_stores.crew_000002.erase("battery_kwh")
    var before = sim.get_snapshot()
    _check(not sim.step(1).ok and sim.get_snapshot() == before, "missing suit account fails atomically")

func _reference_profile() -> void:
    var config = _read("res://tests/world/fixtures/landing_plain_init.json")
    var sim = Simulation.new()
    _check(sim.initialize(config, null, null).ok, "reference authored scenario initializes")
    var science = sim._content.science
    _near(science.crew_metabolism.base_activity_rates_per_s.idle.oxygen_kg * 86400, 0.895, "Earth-day O2 normalization")
    _near(science.crew_metabolism.base_activity_rates_per_s.working.potable_water_kg * 86400, 3.217, "Earth-day water normalization")
    _near(science.time.sol_s, 88775.244, "separate Martian mean solar day")
    _check(absf(science.crew_metabolism.base_activity_rates_per_s.idle.oxygen_kg * science.time.sol_s - 0.895) > 0.02, "Earth-day rate is not silently per-sol")
    var a: Dictionary = science.atmosphere
    _near(science.alerts.co2_high_kg * a.molar_gas_constant_j_mol_k * a.temperature_k / (a.co2_molar_mass_kg_mol * a.volume_m3), 400, "configured instantaneous ideal-gas CO2 warning")
    _ticks(sim, 600)
    _near(sim.get_snapshot().resources.oxygen_kg.amount, 140 + (6.444 - 6 * 0.895) * 600 / 86400, "independent authored O2 balance")
    _near(sim.get_snapshot().resources.food_kcal.amount, 100000 - 6 * 3000 * 600 / 86400, "independent authored food draw")
    _near(sim._state.crew_demand.flows["source/metabolism/wastewater_kg"] * 86400, 6 * 4.366, "documented collection boundary")

func _override_science(config: Dictionary, science: Dictionary) -> Dictionary:
    var copy = config.duplicate(true)
    var path = "res://.godot/a3_science_%d_%d.json" % [OS.get_process_id(), temporary_paths.size()]
    DirAccess.make_dir_recursive_absolute("res://.godot")
    var file = FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(science))
    file.close()
    temporary_paths.append(path)
    copy.definition_manifest.erase(copy.science_config_path)
    copy.science_config_path = path
    copy.definition_manifest[path] = FileAccess.get_sha256(path)
    return copy

func _validation() -> void:
    var config = _read(FIX + "init/habitat_6crew.json")
    var original = _read(config.science_config_path)
    for value in [-1, NAN, INF, "daily"]:
        var bad = original.duplicate(true)
        bad.crew_metabolism.base_activity_rates_per_s.idle.oxygen_kg = value
        _check(not Demand.validate_science(bad).ok, "invalid metabolic numeric value rejected")
    for field in ["time_basis", "base_outputs_per_s", "eva_suit_rates_per_s", "eva_draws_base_water_and_food"]:
        var bad = original.duplicate(true)
        bad.crew_metabolism.erase(field)
        var sim = Simulation.new()
        _check(not sim.initialize(_override_science(config, bad), null, null).ok, "missing science rejected before initialization: " + field)
        _check(sim.get_snapshot().code == "not_initialized", "science failure leaves no live state")
    var reference = _read("res://data/science/a3_reference_science.json")
    reference.atmosphere.volume_m3 = 0
    _check(not Demand.validate_science(reference).ok, "invalid habitat volume rejected")
    reference = _read("res://data/science/a3_reference_science.json")
    reference.alerts.co2_high_kg *= 2
    _check(not Demand.validate_science(reference).ok, "inconsistent CO2 unit conversion rejected")
    var sim = _new()
    sim._content.buildings.fixture_electrolyzer.process.outputs_per_s.oxygen_kg = 0.009
    var before = sim.get_snapshot()
    _check(not sim.step(1).ok and sim.get_snapshot() == before, "invalid stoichiometry rolls back power and chemistry")

func _rollback() -> void:
    var sim = FailedDemandSimulation.new()
    _check(sim.initialize(_read(FIX + "init/habitat_6crew.json"), null, null).ok, "rollback simulation initializes")
    var events: Array = []
    sim.game_event.connect(func(event): events.append(event))
    sim.state_changed.connect(func(snap): events.append(snap))
    var before = sim.get_snapshot()
    var counters = sim._state.counters.duplicate()
    _check(sim.advance(1.5).code == "internal_error", "forced failure after crew demand")
    _equal(sim.get_snapshot(), before, "whole phase-5 rollback including RNG")
    _equal(sim._state.counters, counters, "rollback counters")
    _near(sim._state.accumulator_s, 1.5, "failed tick time retained")
    _check(events.is_empty() and sim._committed_effects.is_empty(), "failed demand leaks no event/receipt")
    _check(sim.staged_ledger.staged.size() == 1 and sim.staged_ledger.tick_guards.size() == 5, "failure occurred after power, three processes, demand and staged completion")
    sim.fail_tick = false
    _check(sim.advance(0).ok, "retry same interval")
    _near(sim.get_snapshot().resources.oxygen_kg.amount, 120.002, "retry chemistry and metabolism exactly once")
    _check(sim._committed_effects.size() == 1 and events.size() == 1, "successful retry commits one receipt and one notification")

func _time() -> void:
    var direct = _new()
    _ticks(direct, 20)
    for scale in [1, 5, 20]:
        var sim = _new()
        sim.submit_command({"contract_version": "2.0.0", "command_id": "scale", "type": "set_time_scale", "payload": {"time_scale": scale}})
        for i in 40: _check(sim.advance(0.5 / scale).ok, "partitioned A3 frames")
        _equal(sim.get_snapshot().resources, direct.get_snapshot().resources, "equal-tick A3 resources")
        sim.submit_command({"contract_version": "2.0.0", "command_id": "pause", "type": "set_time_scale", "payload": {"time_scale": 0}})
        sim.process_pending_commands()
        var before = sim.get_snapshot()
        _check(sim.advance(100).ok and sim.step(1).ok and sim.get_snapshot() == before, "pause freezes processes, crew and alerts")
