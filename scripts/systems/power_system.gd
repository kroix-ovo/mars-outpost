class_name OutpostPowerSystem
extends RefCounted
## Phase 3, fixed dt = one second. No scene access or independent balance writes.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const Storm = preload("res://scripts/systems/dust_storm.gd")

func dispatch(state: RefCounted, content: Dictionary, ledger: RefCounted) -> Dictionary:
    var buildings: Dictionary = state.records.buildings
    var ids = buildings.keys()
    ids.sort()
    var modifier = 1.0
    var modifier_ids: Array[String] = []
    var event_ids = state.records.active_events.keys()
    event_ids.sort()
    for id in event_ids:
        var event: Dictionary = state.records.active_events[id]
        if not Schema.whole(event.starts_tick) or not Schema.whole(event.ends_tick) or event.ends_tick <= event.starts_tick:
            return _fail("Invalid modifier interval.")
        if not (event.starts_tick <= ledger.tick and ledger.tick < event.ends_tick): continue
        for m in event.modifiers:
            if not m is Dictionary or not Schema.exact_keys(m, ["target", "factor"]) or m.target not in ["power_generation", "eva_movement", "eva_oxygen_kg", "eva_battery_kwh"] or not Schema.number(m.factor) or m.factor < 0:
                return _fail("Invalid or unsupported simulation modifier.")
            if m.target != "power_generation": continue
            modifier *= m.factor
            if not is_finite(modifier): return _fail("Electrical modifier overflow.")
            if id not in modifier_ids: modifier_ids.append(id)
    var generation = 0.0
    var consumers: Array = []
    var batteries: Array = []
    var available: Dictionary = {}
    var delivered: Dictionary = {}
    for id in ids:
        var b: Dictionary = buildings[id]
        var d: Dictionary = content.buildings[b.definition_id]
        if not Schema.number(b.condition) or b.condition < 0 or b.condition > 1 or not b.enabled is bool or b.lifecycle not in ["constructing", "commissioned", "destroyed"]:
            return _fail("Invalid building availability.")
        for key in ["power_generation_kw", "power_demand_kw", "battery_charge_limit_kw", "battery_discharge_limit_kw"]:
            if not Schema.number(d[key]) or d[key] < 0: return _fail("Invalid electrical definition.")
        for key in ["battery_charge_efficiency", "battery_discharge_efficiency"]:
            if not Schema.number(d[key]) or d[key] <= 0 or d[key] > 1: return _fail("Invalid battery efficiency.")
        if not Schema.whole(d.power_priority): return _fail("Invalid power priority.")
        b.power_requested_kw = 0.0
        b.power_served_kw = 0.0
        b.operating_fraction = 0.0 # A2 does not execute chemical processes.
        b.blocking_codes = []
        if b.lifecycle == "constructing": b.blocking_codes.append("constructing")
        if b.lifecycle == "destroyed": b.blocking_codes.append("destroyed")
        if not b.enabled: b.blocking_codes.append("disabled")
        if b.condition < 1: b.blocking_codes.append("damaged")
        if b.lifecycle != "commissioned" or not b.enabled or b.condition <= 0:
            b.blocking_codes.sort()
            continue
        if d.power_generation_kw > 0:
            # Solar-only storm factor; the global event modifier keeps its meaning.
            var storm_factor: float = Storm.solar_factor(state, b.definition_id)
            generation += d.power_generation_kw * b.condition * modifier * storm_factor
            b.operating_fraction = b.condition * minf(1.0, modifier) * storm_factor
            if storm_factor < 1.0: b.blocking_codes.append("dust_storm")
            for event_id in modifier_ids: b.blocking_codes.append("event_modifier:" + event_id)
        if d.power_demand_kw > 0:
            if Storm.sheds(state, b.definition_id): b.blocking_codes.append("storm_load_shed")
            else: consumers.append(id)
        if state.per_battery_energy.has(id):
            batteries.append(id)
            available[id] = minf(d.battery_discharge_limit_kw,
                state.per_battery_energy[id] * d.battery_discharge_efficiency * 3600.0)
            delivered[id] = 0.0
        b.blocking_codes.sort()
    consumers.sort_custom(func(a, b):
        var pa: float = content.buildings[buildings[a].definition_id].power_priority
        var pb: float = content.buildings[buildings[b].definition_id].power_priority
        return a < b if pa == pb else pa > pb)
    # Reserve base energy before allocating any individual battery output.
    var reserved: float = state.records.resources.energy_kwh.reserved
    var accessible = 0.0
    for id in batteries: accessible += state.per_battery_energy[id]
    # Disabled batteries retain energy but cannot make reserved energy spendable.
    var spendable = minf(accessible, state.records.resources.energy_kwh.amount - reserved)
    var remaining: float = generation
    var requested = 0.0
    var served = 0.0
    for id in consumers:
        var b: Dictionary = buildings[id]
        var d: Dictionary = content.buildings[b.definition_id]
        var need: float = d.power_demand_kw
        requested += need
        var got = minf(need, remaining)
        remaining -= got
        for bid in batteries:
            var bd: Dictionary = content.buildings[buildings[bid].definition_id]
            var take = minf(need - got, minf(available[bid] - delivered[bid], spendable * bd.battery_discharge_efficiency * 3600.0))
            delivered[bid] += take
            spendable -= take / 3600.0 / bd.battery_discharge_efficiency
            if spendable < 0 and spendable > -1e-15: spendable = 0.0 # arithmetic noise only
            got += take
            if got >= need: break
        b.power_requested_kw = need
        b.power_served_kw = got
        if got == 0: b.blocking_codes.append("no_power")
        elif got < need: b.blocking_codes.append("partial_power")
        b.blocking_codes.sort()
        served += got
    var debits: Dictionary = {"source/generation/energy_kwh": generation / 3600.0}
    var credits: Dictionary = {"sink/load/energy_kwh": served / 3600.0}
    var loss = 0.0
    for id in batteries:
        var d: Dictionary = content.buildings[buildings[id].definition_id]
        var path = "battery/%s/energy_kwh" % id
        if delivered[id] > 0:
            var grid: float = delivered[id] / 3600.0
            # When exactly exhausting a battery, use its exact stored balance.
            var stored: float = grid / d.battery_discharge_efficiency
            if absf(stored - state.per_battery_energy[id]) < 1e-15: stored = state.per_battery_energy[id]
            debits[path] = stored
            loss += stored - grid
        elif remaining > 0:
            var room: float = ledger.battery_capacity(id) - state.per_battery_energy[id]
            var input_kw = minf(remaining, minf(d.battery_charge_limit_kw, room * 3600.0 / d.battery_charge_efficiency))
            var input: float = input_kw / 3600.0
            var gain: float = input * d.battery_charge_efficiency
            if input_kw > 0 and absf(gain - room) < 1e-15: gain = room
            credits[path] = gain
            loss += input - gain
            remaining -= input_kw
    if not is_finite(remaining) or remaining < 0 or not is_finite(loss) or loss < 0 or not is_finite(requested) or not is_finite(served) or not is_finite(generation):
        return _fail("Invalid electrical residual.")
    credits["sink/battery_loss/energy_kwh"] = loss
    credits["sink/curtailment/energy_kwh"] = remaining / 3600.0
    var result = ledger.apply_system({"effect_id": "tick:%d:power:base" % ledger.tick,
        "kind": "power_dispatch", "owner_id": "base", "scope": "tick", "debits": debits, "credits": credits})
    if not result.ok: return result
    state.power_flows = result.flows.duplicate(true)
    state.records.power.generated_kw = generation
    state.records.power.requested_kw = requested
    state.records.power.served_kw = served
    return {"ok": true, "code": "ok", "reason": ""}

static func _fail(reason: String) -> Dictionary:
    return Schema.failure("invalid_state", reason)
