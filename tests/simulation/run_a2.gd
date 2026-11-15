extends SceneTree
const Simulation = preload("res://scripts/simulation/simulation.gd")
const Ledger = preload("res://scripts/simulation/resource_ledger.gd")
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const FIX = "res://tests/simulation/fixtures/"
var checks = 0
var failures: Array[String] = []

# Isolate A2's electrical/ledger regressions while the full facade now runs A3.
# run_a3.gd tests the combined phases and chemistry independently.
class PowerOnlySimulation extends Simulation:
    func _run_life_support(_candidate: RefCounted, _ledger: RefCounted) -> Dictionary:
        return {"ok": true, "code": "ok", "reason": ""}
    func _run_crew_demand(_candidate: RefCounted, _ledger: RefCounted) -> Dictionary:
        return {"ok": true, "code": "ok", "reason": ""}

class FailingSimulation extends PowerOnlySimulation:
    var fail_tick = true
    var captured_ledger: RefCounted
    var queue_during_dispatch = true
    func _dispatch_power(candidate: RefCounted, ledger: RefCounted) -> Dictionary:
        var result = super._dispatch_power(candidate, ledger)
        captured_ledger = ledger
        if not result.ok: return result
        if queue_during_dispatch:
            queue_during_dispatch = false
            submit_command({"contract_version": "2.0.0", "command_id": "during-tick", "type": "set_time_scale", "payload": {"time_scale": 1}})
        # Exercise the actual facade receipt staging after real battery writes.
        result = ledger.apply_system({"effect_id": "test:completion", "kind": "external_source",
            "owner_id": "test", "scope": "one_time", "debits": {"source/environment/co2_kg": 1}, "credits": {"base/co2_kg": 1}})
        candidate.rng.randi()
        if fail_tick:
            candidate.records.resources.oxygen_kg.amount = -1
        return result

func _initialize() -> void:
    _power_oracle()
    _ledger_bounds()
    _transfers()
    _identity()
    _dispatch_edges()
    _modifiers()
    _rollback()
    _time()
    _scaling()
    if failures.is_empty():
        print("A2_PASS checks=", checks)
        quit(0)
    else:
        for failure in failures: print("A2_FAIL ", failure)
        quit(1)

func _check(value: bool, label: String) -> void:
    checks += 1
    if not value: failures.append(label)

func _near(actual: float, expected: float, label: String) -> void:
    _check(is_finite(actual) and absf(actual - expected) <= 1e-10 + 1e-9 * absf(expected), label + " got=" + str(actual) + " expected=" + str(expected))

func _read(path: String) -> Dictionary:
    return JSON.parse_string(FileAccess.get_file_as_string(path))

func _new(name: String = "power_shortage_6crew") -> RefCounted:
    var sim = PowerOnlySimulation.new()
    _check(sim.initialize(_read(FIX + "init/" + name + ".json"), null, null).ok, "initialize " + name)
    return sim

func _command(sim: RefCounted, id: String, type: String, payload: Dictionary) -> void:
    _check(sim.submit_command({"contract_version": "2.0.0", "command_id": id, "type": type, "payload": payload}).accepted, "accept " + id)
    sim.process_pending_commands()

func _run(sim: RefCounted, ticks: int) -> void:
    for i in ticks: _check(sim.step(1).ok, "tick " + str(i))

func _effect(id: String, kind: String, debits: Dictionary, credits: Dictionary, scope: String = "one_time", owner: String = "expedition_test") -> Dictionary:
    return {"effect_id": id, "kind": kind, "owner_id": owner, "scope": scope, "debits": debits, "credits": credits}

func _ledger(sim: RefCounted, tick: int = 0) -> RefCounted:
    return Ledger.new(sim._state, sim._content, sim._committed_effects, tick)

func _synthetic_remote(sim: RefCounted) -> void:
    # Existing authoritative records only: this does not implement EVA lifecycle.
    sim._state.records.expeditions.expedition_test = {"crew_ids": ["crew_000001", "crew_000002"],
        "site_id": "site_test", "suit_stores": {
            "crew_000001": {"oxygen_kg": 0.0, "battery_kwh": 0.0},
            "crew_000002": {"oxygen_kg": 0.0, "battery_kwh": 0.0}},
        "cargo": {"alloy": 0.0, "electronics": 0.0}}
    sim._state.records.sites.site_test = {"reserved_by_expedition_id": "expedition_test", "remaining_cargo": {"alloy": 4.0, "electronics": 4.0}}
    sim._state.return_caches.expedition_test = {"alloy": 0.0, "electronics": 0.0}

func _power_oracle() -> void:
    var sim = _new()
    var original = sim.get_snapshot()
    _run(sim, 4)
    _near(sim.get_snapshot().resources.energy_kwh.amount, 0.003, "four charges /3600")
    _near(sim.get_snapshot().resources.energy_kwh.net_rate_per_s, 0.00025, "actual charge rate")
    _check(sim.get_snapshot().resources.energy_kwh.forecast_empty_s == null, "charging has no depletion forecast")
    _compare_power(sim, "power_charged_tick4")
    _command(sim, "off", "set_building_enabled", {"building_id": "building_000001", "enabled": false})
    var drain = 2.0 / 3600.0 / 0.9
    _run(sim, 4)
    _near(sim.get_snapshot().resources.energy_kwh.amount, 0.003 - 4 * drain, "four full discharges")
    _near(sim.get_snapshot().resources.energy_kwh.net_rate_per_s, -drain, "actual discharge rate")
    _near(sim.get_snapshot().resources.energy_kwh.forecast_empty_s, (0.003 - 4 * drain) / drain, "constant rate forecast")
    _run(sim, 1)
    _compare_power(sim, "power_partial_tick9")
    var snap = sim.get_snapshot()
    _near(snap.power.served_kw, 1.72, "partial 1.72kW")
    _near(snap.buildings.building_000005.power_served_kw, 0.5, "scrubber highest priority")
    _near(snap.buildings.building_000003.power_served_kw, 1.0, "electrolyzer next priority")
    _near(snap.buildings.building_000004.power_served_kw, 0.22, "recycler residual")
    _near(snap.power.battery_stored_kwh, 0, "battery exhausted")
    _run(sim, 1)
    _compare_power(sim, "power_none_tick10")
    _run(sim, 10)
    _command(sim, "on", "set_building_enabled", {"building_id": "building_000001", "enabled": true})
    _run(sim, 1)
    _compare_power(sim, "power_restored_tick21")
    for rid in original.resources:
        if rid != "energy_kwh": _near(sim.get_snapshot().resources[rid].amount, original.resources[rid].amount, "no A3 resource activity " + rid)
    for b in sim.get_snapshot().buildings.values():
        if b.power_requested_kw > 0: _near(b.operating_fraction, 0, "served power does not claim chemistry")

func _compare_power(sim: RefCounted, fixture: String) -> void:
    var expected = _read(FIX + "snapshots/" + fixture + ".json")
    var actual = sim.get_snapshot()
    for key in expected.power: _near(actual.power[key], expected.power[key], fixture + "/" + key)
    for id in expected.buildings:
        for key in ["power_requested_kw", "power_served_kw"]:
            _near(actual.buildings[id][key], expected.buildings[id][key], fixture + "/" + id + "/" + key)
    _near(actual.resources.energy_kwh.amount, expected.resources.energy_kwh.amount, fixture + "/energy")
    _near(actual.resources.energy_kwh.net_rate_per_s, expected.resources.energy_kwh.net_rate_per_s, fixture + "/rate")

func _ledger_bounds() -> void:
    var sim = _new()
    var ledger = _ledger(sim)
    var invalid: Array = []
    for q in [-1.0, NAN, INF, -INF, "1", true]:
        invalid.append(_effect("bad", "external_source", {"source/production/oxygen_kg": q}, {"base/oxygen_kg": q}))
    invalid.append(_effect("bad", "external_source", {"source/production/unobtainium": 1}, {"base/unobtainium": 1}))
    invalid.append(_effect("bad", "external_source", {"source/production/alloy": 0.5}, {"base/alloy": 0.5}))
    invalid.append(_effect("bad", "external_source", {"source/production/oxygen_kg": 1000}, {"base/oxygen_kg": 1000}))
    invalid.append(_effect("bad", "conversion", {"base/oxygen_kg": 1, "base/food_kcal": 1e9}, {"sink/conversion/oxygen_kg": 1, "sink/conversion/food_kcal": 1e9}))
    invalid.append(_effect("bad", "conversion", {"base/oxygen_kg": 121, "source/production/oxygen_kg": 10}, {"base/oxygen_kg": 10, "sink/conversion/oxygen_kg": 121}))
    invalid.append(_effect("bad", "conversion", {"base/oxygen_kg": 1}, {"sink/conversion/raw_water_kg": 1}))
    invalid.append(_effect("bad", "external_sink", {"base/energy_kwh": 0, "battery/building_000002/energy_kwh": 0}, {"sink/load/energy_kwh": 0}))
    for e in invalid:
        var before = sim.get_snapshot()
        var batteries = sim._state.per_battery_energy.duplicate()
        _check(not ledger.apply_system(e).ok, "reject invalid transaction " + str(e))
        _check(sim.get_snapshot() == before and sim._state.per_battery_energy == batteries, "entire transaction atomic")
        _check(ledger.staged.is_empty() and ledger.tick_guards.is_empty(), "failed transaction has no receipts")
    sim._state.records.resources.oxygen_kg.reserved = 119
    _check(not ledger.apply_system(_effect("reserved", "external_sink", {"base/oxygen_kg": 2}, {"sink/environment/oxygen_kg": 2})).ok, "reserved stock protected")
    _check(ledger.apply_system(_effect("available", "external_sink", {"base/oxygen_kg": 1}, {"sink/environment/oxygen_kg": 1})).ok, "available stock spendable")
    _check(ledger.apply_system(_effect("accumulator", "external_source", {"source/production/co2_kg": 1e6}, {"base/co2_kg": 1e6})).ok, "accumulator uncapped")
    _near(sim.get_snapshot().resources.co2_kg.amount, 1000000.5, "CO2 retained")
    sim._state.records.resources.oxygen_kg.unit = "kwh"
    _check(not ledger.apply_system(_effect("unit", "external_source", {"source/production/co2_kg": 1}, {"base/co2_kg": 1})).ok, "bad unit rejected before any write")
    sim._state.records.resources.oxygen_kg.unit = "kg"
    sim._state.records.resources.co2_kg.capacity = 100
    _check(not ledger.validate().ok, "fictional accumulator capacity rejected")

func _transfers() -> void:
    var sim = _new()
    _synthetic_remote(sim)
    var ledger = _ledger(sim)
    var before = sim.get_snapshot()
    var load = _effect("load", "eva_load", {"base/oxygen_kg": 0.1, "base/energy_kwh": 0.001},
        {"suit/expedition_test/crew_000001/oxygen_kg": 0.1, "suit/expedition_test/crew_000001/battery_kwh": 0.001})
    _check(ledger.apply_transfer(load).ok, "suit load and energy alias")
    _near(sim._state.per_battery_energy.building_000002, 0.001, "direct energy transfer has no conversion loss")
    _check(ledger.apply_transfer(_effect("return", "eva_return", load.credits, load.debits)).ok, "suit return round trip")
    _check(sim.get_snapshot() == before, "suit round trip preserves snapshot")
    var collect = _effect("collect", "salvage_collect", {"site/site_test/alloy": 4}, {"cargo/expedition_test/alloy": 4})
    _check(ledger.apply_transfer(collect).ok, "site to cargo")
    _check(not ledger.apply_transfer(_effect("carry", "salvage_collect", {"site/site_test/electronics": 3}, {"cargo/expedition_test/electronics": 3})).ok, "combined carry capacity")
    _check(not ledger.apply_transfer(_effect("owner", "salvage_collect", {"site/site_test/electronics": 1}, {"cargo/expedition_test/electronics": 1}, "one_time", "other_expedition")).ok, "owner mismatch")
    var alloy: Dictionary = sim._state.records.resources.alloy
    alloy.amount = alloy.capacity - 1
    _check(ledger.apply_transfer(_effect("cargo-return", "cargo_return", {"cargo/expedition_test/alloy": 4}, {"base/alloy": 1, "return_cache/expedition_test/alloy": 3})).ok, "cargo overflow cached")
    _near(sim._state.return_caches.expedition_test.alloy, 3, "cache authoritative balance")
    alloy.amount -= 3
    _check(ledger.apply_transfer(_effect("cache-return", "cache_return", {"return_cache/expedition_test/alloy": 3}, {"base/alloy": 3})).ok, "cache drain")
    _check(not ledger.apply_transfer(_effect("missing", "eva_load", {"base/oxygen_kg": 0}, {"suit/expedition_test/crew_000003/oxygen_kg": 0})).ok, "unknown suit account")
    _check(not ledger.apply_transfer(_effect("missing-cache", "cargo_return", {"cargo/expedition_test/alloy": 0}, {"return_cache/missing/alloy": 0})).ok, "missing cache not created")
    _check(not ledger.apply_transfer(_effect("fraction", "salvage_collect", {"site/site_test/electronics": 0.5}, {"cargo/expedition_test/electronics": 0.5})).ok, "fractional cargo count")
    _check(not ledger.apply_transfer(_effect("loss-bypass", "eva_load", {"base/oxygen_kg": 1}, {"loss/oxygen_kg": 1})).ok, "load cannot vent")
    _check(not ledger.apply_transfer(_effect("reward", "production", {}, {"base/oxygen_kg": 1})).ok, "adapter cannot manufacture rewards")
    _check(not ledger.apply_transfer(_effect("fake-loss", "eva_return", {"suit/expedition_test/crew_000001/oxygen_kg": 0}, {"loss/oxygen_kg": 1})).ok, "unbalanced loss rejected")
    var suit: Dictionary = sim._state.records.expeditions.expedition_test.suit_stores.crew_000001
    suit.oxygen_kg = 0.1
    var oxygen: Dictionary = sim._state.records.resources.oxygen_kg
    oxygen.amount = oxygen.capacity - 0.025
    _check(not ledger.apply_transfer(_effect("avoidable-loss", "eva_return", {"suit/expedition_test/crew_000001/oxygen_kg": 0.1}, {"loss/oxygen_kg": 0.1})).ok, "return must fill available storage")
    _check(ledger.apply_transfer(_effect("vent", "eva_return", {"suit/expedition_test/crew_000001/oxygen_kg": 0.1}, {"base/oxygen_kg": 0.025, "loss/oxygen_kg": 0.075})).ok, "only unavoidable suit overflow vented")
    _near(ledger.staged.vent.result.flows["loss/oxygen_kg"], 0.075, "explicit vent receipt")
    _check(ledger.validate().ok, "all remote balances valid")
    # Suit electrical return overflow has the same precise-fit policy, and no
    # dispatch efficiency or per-second charge limit applies to direct transfer.
    suit.battery_kwh = 0.001
    sim._content.buildings.fixture_battery.storage_capacity.energy_kwh = 0.0025
    _set_energy(sim, {"building_000002": 0.002})
    var energy_return = _effect("energy-return", "eva_return", {"suit/expedition_test/crew_000001/battery_kwh": 0.001},
        {"base/energy_kwh": 0.0005, "loss/energy_kwh": 0.0005})
    _check(ledger.apply_transfer(energy_return).ok, "suit energy overflow precise fit")
    _near(sim._state.per_battery_energy.building_000002, 0.0025, "direct suit credit no charge loss")
    _near(ledger.staged["energy-return"].result.flows["loss/energy_kwh"], 0.0005, "energy return loss explicit")

func _identity() -> void:
    var sim = _new()
    var ledger = _ledger(sim)
    var effect = _effect("receipt", "external_source", {"source/production/co2_kg": 1}, {"base/co2_kg": 1})
    var result = ledger.apply_system(effect)
    _check(result.ok and sim._committed_effects.is_empty() and ledger.staged.size() == 1, "receipt staged before outer commit")
    var retry = effect.duplicate(true)
    retry.debits["source/production/co2_kg"] = 1.0
    retry.credits["base/co2_kg"] = 1.0
    _check(ledger.apply_system(retry) == result, "normalized same-candidate retry cached")
    _near(sim.get_snapshot().resources.co2_kg.amount, 1.5, "retry once")
    sim._committed_effects.merge(ledger.staged)
    ledger = _ledger(sim, 1)
    _check(ledger.apply_system(effect) == result, "retained retry cached across ticks")
    result.flows.clear()
    _check(not ledger.apply_system(effect).flows.is_empty(), "cached receipt result detached")
    effect.credits["base/co2_kg"] = 2
    _check(not ledger.apply_system(effect).ok, "conflicting ID rejected")
    var tick_effect = _effect("tick:1:flow:test", "external_source", {"source/production/co2_kg": 1}, {"base/co2_kg": 1}, "tick")
    _check(ledger.apply_system(tick_effect).ok and ledger.apply_system(tick_effect).ok, "tick duplicate cached")
    _near(sim.get_snapshot().resources.co2_kg.amount, 2.5, "tick effect once")
    _check(sim._committed_effects.size() == 1 and ledger.tick_guards.size() == 1, "bounded tick receipt")
    ledger = _ledger(sim, 2)
    _check(ledger.tick_guards.is_empty() and not ledger.apply_system(tick_effect).ok, "new boundary clears guards and rejects old tick IDs")
    tick_effect.effect_id = "tick:2:flow:test"
    _check(ledger.apply_system(tick_effect).ok, "new tick can execute new flow")
    tick_effect.scope = "one_time"
    _check(not ledger.apply_system(tick_effect).ok, "cannot persist per-tick receipts")

func _set_energy(sim: RefCounted, values: Dictionary) -> void:
    # Synthetic setup only, runtime writes remain ledger-exclusive.
    sim._state.per_battery_energy = values.duplicate()
    var total = 0.0
    var capacity = 0.0
    var ledger = _ledger(sim)
    for id in values:
        total += values[id]
        capacity += ledger.battery_capacity(id)
    sim._state.records.resources.energy_kwh.amount = total
    sim._state.records.resources.energy_kwh.capacity = capacity
    sim._state.records.power.battery_stored_kwh = total
    sim._state.records.power.battery_capacity_kwh = capacity

func _dispatch_edges() -> void:
    var sim = _new()
    var battery_id = "building_000002"
    var battery: Dictionary = sim._state.records.buildings[battery_id]
    var battery_def: Dictionary = sim._content.buildings.fixture_battery
    battery_def.storage_capacity.energy_kwh = 0.003
    _set_energy(sim, {battery_id: 0.003})
    _run(sim, 1)
    _near(sim._state.power_flows["sink/curtailment/energy_kwh"], 1.0 / 3600, "full storage curtails surplus")
    _near(sim._state.power_flows["sink/battery_loss/energy_kwh"], 0, "no charge loss when full")
    _set_energy(sim, {battery_id: 0.0029})
    _run(sim, 1)
    _near(sim._state.per_battery_energy[battery_id], 0.003, "partial headroom fills exactly")
    _near(sim._state.power_flows["sink/battery_loss/energy_kwh"], 0.0001 / 0.9 - 0.0001, "charge efficiency loss")
    _near(sim._state.power_flows["sink/curtailment/energy_kwh"], 1.0 / 3600 - 0.0001 / 0.9, "remaining generation curtailed")
    _command(sim, "off", "set_building_enabled", {"building_id": "building_000001", "enabled": false})
    battery_def.battery_discharge_limit_kw = 0.75
    var second = battery.duplicate(true)
    second.id = "building_000006"
    sim._state.records.buildings[second.id] = second
    _set_energy(sim, {second.id: 0.002, battery_id: 0.002})
    # Tie consumers deliberately, and reverse dictionary insertion order.
    for d in sim._content.buildings.values(): d.power_priority = 1
    var reversed: Dictionary = {}
    var ids = sim._state.records.buildings.keys()
    ids.reverse()
    for id in ids: reversed[id] = sim._state.records.buildings[id]
    sim._state.records.buildings = reversed
    _run(sim, 1)
    var snap = sim.get_snapshot()
    _near(snap.power.served_kw, 1.5, "two discharge rate limits")
    _near(snap.buildings.building_000003.power_served_kw, 1, "tie first stable ID")
    _near(snap.buildings.building_000004.power_served_kw, 0.5, "tie second stable ID")
    _near(snap.buildings.building_000005.power_served_kw, 0, "tie last stable ID")
    _near(sim._state.per_battery_energy[battery_id], 0.002 - 0.75 / 3600 / 0.9, "first battery by ID")
    _near(sim._state.power_flows["sink/battery_loss/energy_kwh"], 1.5 / 3600 * (1 / 0.9 - 1), "discharge loss explicit")
    _near(snap.resources.energy_kwh.amount, sim._state.per_battery_energy[battery_id] + sim._state.per_battery_energy[second.id], "battery sum")
    _check(snap.buildings.building_000005.blocking_codes.has("no_power"), "no power blocking")
    _command(sim, "disable-bat", "set_building_enabled", {"building_id": battery_id, "enabled": false})
    var retained: float = sim._state.per_battery_energy[battery_id]
    sim._state.records.buildings[second.id].condition = 0
    _run(sim, 1)
    _near(sim.get_snapshot().power.served_kw, 0, "disabled and condition-zero batteries unavailable")
    _near(sim._state.per_battery_energy[battery_id], retained, "disabled energy retained")
    _near(sim.get_snapshot().power.battery_capacity_kwh, 0.006, "unavailable battery capacity retained")
    _check(sim.get_snapshot().buildings[second.id].blocking_codes.has("damaged"), "damaged blocking")
    _set_energy(sim, {battery_id: 0, second.id: 0})
    _run(sim, 1)
    _near(sim.get_snapshot().power.served_kw, 0, "empty storage")
    # Stable battery ordering with enough power from the first battery only.
    sim._state.records.buildings[battery_id].enabled = true
    sim._state.records.buildings[second.id].condition = 1
    battery_def.battery_discharge_limit_kw = 2
    _set_energy(sim, {second.id: 0.002, battery_id: 0.002})
    _run(sim, 1)
    _near(sim._state.per_battery_energy[second.id], 0.002, "second battery untouched if first can supply")
    _check(not sim._state.power_flows.has("battery/" + battery_id), "flows record external destinations only")
    # All aggregate energy reserved: dispatch must serve no battery load.
    sim._state.records.resources.energy_kwh.reserved = sim._state.records.resources.energy_kwh.amount
    _run(sim, 1)
    _near(sim.get_snapshot().power.served_kw, 0, "reserved energy excluded from dispatch")
    # Disabled loads request zero and keep their preference across snapshots.
    sim._state.records.buildings.building_000003.enabled = false
    _run(sim, 1)
    _near(sim.get_snapshot().buildings.building_000003.power_requested_kw, 0, "disabled load not requested")
    _check(sim.get_snapshot().buildings.building_000003.blocking_codes.has("disabled"), "disabled blocking")
    var first_tick: int = sim.get_snapshot().alerts[0].first_tick
    _run(sim, 1)
    _check(sim.get_snapshot().alerts[0].first_tick == first_tick, "persistent power alerts retain first occurrence")

func _modifiers() -> void:
    var sim = _new()
    sim._state.records.buildings.building_000001.condition = 0.5
    sim._state.records.active_events.dust = {"starts_tick": 0, "ends_tick": 1, "modifiers": [{"target": "power_generation", "factor": 0.5}]}
    _run(sim, 1)
    _near(sim.get_snapshot().power.generated_kw, 0.75, "condition and modifier each applied once")
    _check(sim.get_snapshot().buildings.building_000001.blocking_codes.has("event_modifier:dust"), "modifier diagnostic")
    _run(sim, 1)
    _near(sim.get_snapshot().power.generated_kw, 1.5, "modifier end interval exclusive")
    sim._state.records.active_events.unknown = {"starts_tick": 2, "ends_tick": 5, "modifiers": [{"target": "magic", "factor": 0.5}]}
    var before = sim.get_snapshot()
    _check(sim.step(1).code == "internal_error" and sim.get_snapshot() == before, "unsupported modifier rejects atomically")
    sim._state.records.active_events.clear()
    sim._state.records.buildings.building_000001.lifecycle = "constructing"
    _run(sim, 1)
    _near(sim.get_snapshot().power.generated_kw, 0, "uncommissioned generator unavailable")
    sim._state.records.buildings.building_000001.lifecycle = "destroyed"
    _run(sim, 1)
    _near(sim.get_snapshot().power.generated_kw, 0, "destroyed generator unavailable")
    _check(sim.get_snapshot().buildings.building_000001.blocking_codes.has("destroyed"), "destroyed blocking")

func _rollback() -> void:
    var sim = FailingSimulation.new()
    _check(sim.initialize(_read(FIX + "init/power_shortage_6crew.json"), null, null).ok, "failing sim initialize")
    var signals_seen: Array = []
    sim.game_event.connect(func(e): signals_seen.append(e))
    sim.state_changed.connect(func(s): signals_seen.append(s))
    var before = sim.get_snapshot()
    var rng: int = sim._state.rng.state
    var battery = sim._state.per_battery_energy.duplicate()
    _check(sim.advance(2.5).code == "internal_error", "forced post-dispatch invariant failure")
    _check(sim.get_snapshot() == before and sim._state.per_battery_energy == battery, "failed tick rolls back battery and resources")
    _check(sim._state.rng.state == rng, "failed tick rolls back RNG")
    _near(sim._state.accumulator_s, 2.5, "failed tick time retained for retry")
    _check(sim._committed_effects.is_empty() and signals_seen.is_empty(), "no speculative receipt or event escaped")
    _check(sim._pending == ["during-tick"] and sim._journal["during-tick"].status == "queued", "new pending command preserved through failed tick")
    _check(sim.captured_ledger.staged.size() == 1 and sim.captured_ledger.tick_guards.size() == 1, "failure happened after staged balance and receipts")
    # Commands arriving while running the candidate remain queued on tick failure.
    var pending_command = {"contract_version": "2.0.0", "command_id": "queued-on-failure", "type": "set_time_scale", "payload": {"time_scale": 1}}
    sim.submit_command(pending_command)
    _check(sim.step(1).code == "internal_error", "boundary action precedes failing tick")
    _check(sim.submit_command(pending_command).status == "resolved", "committed boundary remains resolved")
    sim.fail_tick = false
    signals_seen.clear()
    _check(sim.advance(0).ok, "retry retained two ticks")
    _check(sim.get_snapshot().clock.tick_index == 2 and sim._committed_effects.size() == 1, "retry commits receipt once")
    _near(sim.get_snapshot().resources.co2_kg.amount, 1.5, "one-time effect committed only once")
    _near(sim._state.accumulator_s, 0.5, "only successful ticks consume time")
    _check(signals_seen.size() == 1, "one committed notification")

func _time() -> void:
    var baseline = _new()
    _run(baseline, 20)
    for scale in [1, 5, 20]:
        var sim = _new()
        _command(sim, "scale", "set_time_scale", {"time_scale": scale})
        for i in 40: _check(sim.advance(0.5 / scale).ok, "partitioned advancement")
        _check(sim.get_snapshot().clock.tick_index == 20, "equal completed ticks")
        _check(sim.get_snapshot().power == baseline.get_snapshot().power and sim.get_snapshot().resources == baseline.get_snapshot().resources, "frame/scale independent power")
        _command(sim, "pause", "set_time_scale", {"time_scale": 0})
        var before = sim.get_snapshot()
        _check(sim.advance(100).ok and sim.step(1).ok and sim.get_snapshot() == before, "pause freezes all rates and dispatch")
        _synthetic_remote(sim)
        _check(_ledger(sim, 20).apply_transfer(_effect("paused-load", "eva_load", {"base/oxygen_kg": 0.1}, {"suit/expedition_test/crew_000001/oxygen_kg": 0.1})).ok, "ledger permits authorized paused boundary transfers")
    var backlog = _new()
    _command(backlog, "fast", "set_time_scale", {"time_scale": 20})
    _check(backlog.advance(20).ok and backlog.get_snapshot().clock.tick_index == 120, "tick budget")
    _command(backlog, "pause", "set_time_scale", {"time_scale": 0})
    var before = backlog.get_snapshot()
    _check(backlog.advance(0).ok and backlog.get_snapshot() == before, "paused backlog retained")
    _command(backlog, "resume", "set_time_scale", {"time_scale": 1})
    for i in 3: _check(backlog.advance(0).ok, "drain backlog")
    var direct = _new()
    _run(direct, 400)
    _check(backlog.get_snapshot().power == direct.get_snapshot().power and backlog.get_snapshot().resources == direct.get_snapshot().resources, "backlog identical electrical state")

func _median_tick(sim: RefCounted) -> float:
    var samples: Array[float] = []
    for batch in 5:
        var start = Time.get_ticks_usec()
        for i in 30: _check(sim.step(1).ok, "benchmark tick")
        samples.append((Time.get_ticks_usec() - start) / 30000.0)
    samples.sort()
    return samples[2]

func _scaling() -> void:
    var timings: Array[float] = []
    var resolves: Array[float] = []
    for count in [0, 20000]:
        var sim = _new()
        var ledger = _ledger(sim)
        for i in count:
            # Real staged effects, merged once like an outer gameplay commit.
            _check(ledger.apply_system(_effect("history:" + str(i), "external_source", {"source/environment/co2_kg": 0}, {"base/co2_kg": 0})).ok, "seed receipt history")
            _check(sim.submit_command({"contract_version": "2.0.0", "command_id": "history:" + str(i), "type": "set_time_scale", "payload": {"time_scale": 1}}).accepted, "seed journal")
        sim._committed_effects.merge(ledger.staged)
        sim.process_pending_commands()
        var ms = _median_tick(sim)
        timings.append(ms)
        var start = Time.get_ticks_usec()
        for i in 250:
            sim.submit_command({"contract_version": "2.0.0", "command_id": "measure:" + str(i), "type": "set_time_scale", "payload": {"time_scale": 1}})
        sim.process_pending_commands()
        var resolve_ms = (Time.get_ticks_usec() - start) / 250000.0
        resolves.append(resolve_ms)
        _check(sim._committed_effects.size() == count, "ticks never retain per-second receipts")
        _check(not "_committed_effects" in sim._state and not "_journal" in sim._state, "gameplay clone excludes retained history")
        var candidate = sim._state.clone()
        _check(candidate.per_battery_energy == sim._state.per_battery_energy, "clone retains battery state only")
        print("A2_BENCH retained_commands=", count, " retained_effects=", count, " tick_ms=", ms, " command_ms=", resolve_ms)
    _check(timings[1] < maxf(2.0, timings[0] * 8), "tick cost independent of both histories")
    _check(resolves[1] < maxf(2.0, resolves[0] * 4), "command cost independent of both histories")
