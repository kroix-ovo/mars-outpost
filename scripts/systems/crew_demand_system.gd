class_name OutpostCrewDemandSystem
extends RefCounted
## Phase 5. Sole demand writer; produces diagnostics, never crew job/health edits.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const NEED_CODES = {"oxygen_kg": "oxygen", "potable_water_kg": "water", "food_kcal": "food", "energy_kwh": "suit_energy"}

static func validate_science(science: Dictionary) -> Dictionary:
    var m: Variant = science.get("crew_metabolism")
    if not m is Dictionary or m.get("time_basis") != "per_simulated_second":
        return Schema.failure("invalid_schema", "Metabolism requires normalized per-simulated-second rates.")
    if not m.get("base_activity_rates_per_s") is Dictionary or not Schema.exact_keys(m.base_activity_rates_per_s, ["idle", "working"]):
        return Schema.failure("invalid_schema", "Idle/working demand tables are required.")
    for activity in ["idle", "working"]:
        if not _rates(m.base_activity_rates_per_s[activity], ["oxygen_kg", "potable_water_kg", "food_kcal"]):
            return Schema.failure("invalid_value", "Invalid base metabolic rates.")
    if not _rates(m.get("base_outputs_per_s"), ["co2_kg", "wastewater_kg"]) or not _rates(m.get("eva_suit_rates_per_s"), ["oxygen_kg", "battery_kwh"]):
        return Schema.failure("invalid_value", "Invalid metabolic output/suit rates.")
    if not m.get("eva_draws_base_water_and_food") is bool or (m.has("eva_supported") and not m.eva_supported is bool):
        return Schema.failure("invalid_value", "Invalid EVA demand policy.")
    if not science.get("alerts") is Dictionary:
        return Schema.failure("invalid_schema", "Alert configuration is required.")
    for key in ["low_oxygen_forecast_s", "co2_high_kg", "battery_low_fraction", "expedition_low_margin_s"]:
        if not Schema.number(science.alerts.get(key)) or science.alerts[key] < 0:
            return Schema.failure("invalid_value", "Invalid alert threshold: " + key)
    if science.alerts.battery_low_fraction > 1: return Schema.failure("invalid_value", "Battery alert fraction exceeds one.")
    if not science.get("losses") is Dictionary or not Schema.number(science.losses.get("oxygen_leak_kg_per_s")) or science.losses.oxygen_leak_kg_per_s < 0:
        return Schema.failure("invalid_value", "Explicit leakage policy required.")
    if science.losses.oxygen_leak_kg_per_s != 0:
        return Schema.failure("module_unavailable", "Leakage and environmental losses remain A5.")
    if science.metadata.status == "source_backed_reference_model":
        var a: Variant = science.get("atmosphere")
        var fields = ["volume_m3", "temperature_k", "molar_gas_constant_j_mol_k", "co2_molar_mass_kg_mol", "instantaneous_warning_pa"]
        if not _rates(a, fields): return Schema.failure("invalid_value", "Reference atmosphere assumptions are required.")
        for key in fields:
            if a[key] <= 0: return Schema.failure("invalid_value", "Reference atmosphere values must be positive.")
        var threshold: float = a.instantaneous_warning_pa * a.volume_m3 * a.co2_molar_mass_kg_mol / (a.molar_gas_constant_j_mol_k * a.temperature_k)
        if not Schema.number(threshold) or absf(threshold - science.alerts.co2_high_kg) > 1e-10:
            return Schema.failure("invalid_value", "CO2 mass threshold does not match declared atmosphere assumptions.")
    return {"ok": true, "code": "ok", "reason": ""}

static func _rates(value: Variant, keys: Array) -> bool:
    if not value is Dictionary or not Schema.exact_keys(value, keys): return false
    for key in keys:
        if not Schema.number(value[key]) or value[key] < 0: return false
    return true

func run(state: RefCounted, content: Dictionary, ledger: RefCounted) -> Dictionary:
    var m: Dictionary = content.science.crew_metabolism
    var ids = state.records.crew.keys()
    ids.sort()
    var requested: Dictionary = {}
    var provided: Dictionary = {}
    var unmet: Dictionary = {}
    var base_ids: Array = []
    var eva_ids: Array = []
    for id in ids:
        var c: Dictionary = state.records.crew[id]
        if c.status not in ["idle", "working", "travelling", "eva", "incapacitated", "dead"] or c.location_kind not in ["base", "eva"]:
            return Schema.failure("invalid_state", "Unknown crew activity/location.")
        if c.status == "dead": continue
        requested[id] = {}
        provided[id] = {}
        if c.location_kind == "base": base_ids.append(id)
        else:
            if not m.get("eva_supported", true): return Schema.failure("module_unavailable", "No reference suit model adopted; real EVA remains unavailable.")
            if not state.records.expeditions.has(c.expedition_id): return Schema.failure("unknown_entity", "Missing expedition for EVA demand.")
            eva_ids.append(id)
    var debits: Dictionary = {}
    var credits: Dictionary = {}
    # Allocate each shared resource proportionally, then distribute roundoff in
    # stable crew-ID order. Reservations remain unavailable to metabolism.
    for rid in ["oxygen_kg", "potable_water_kg", "food_kcal"]:
        var draws: Array = base_ids.duplicate()
        if rid != "oxygen_kg" and m.eva_draws_base_water_and_food: draws.append_array(eva_ids)
        draws.sort()
        var total = 0.0
        for id in draws:
            var activity = "working" if state.records.crew[id].status in ["working", "travelling"] else "idle"
            var q: float = m.base_activity_rates_per_s[activity][rid]
            requested[id][rid] = q
            total += q
        if not is_finite(total): return Schema.failure("invalid_value", "Metabolic demand overflow.")
        var balance: Dictionary = state.records.resources[rid]
        var target = minf(total, balance.amount - balance.reserved)
        var fraction = target / total if total > 0 else 1.0
        var remaining = target
        for id in draws:
            var got = minf(requested[id][rid] * fraction, remaining)
            provided[id][rid] = got
            remaining -= got
        for id in draws:
            var remainder = minf(remaining, requested[id][rid] - provided[id][rid])
            provided[id][rid] += remainder
            remaining -= remainder
            if provided[id][rid] + 1e-15 < requested[id][rid]: _unmet(unmet, id, NEED_CODES[rid])
        var used = target - remaining
        debits["base/" + rid] = used
        credits["sink/metabolism/" + rid] = used
    # Synthetic suit tests exercise the demand interface without implementing
    # launch, travel, refill, return or medical outcomes.
    for id in eva_ids:
        var c: Dictionary = state.records.crew[id]
        var e: Dictionary = state.records.expeditions[c.expedition_id]
        if id not in e.crew_ids or not e.suit_stores.has(id): return Schema.failure("invalid_state", "Suit ownership mismatch.")
        if not e.suit_stores[id] is Dictionary or not Schema.exact_keys(e.suit_stores[id], ["oxygen_kg", "battery_kwh"]):
            return Schema.failure("invalid_state", "Incomplete suit stores.")
        for key in ["oxygen_kg", "battery_kwh"]:
            var rid = "energy_kwh" if key == "battery_kwh" else key
            var q: float = preload("res://scripts/crew/eva_rates.gd").rate(state.records, e.get("status", "outbound"), key, m.eva_suit_rates_per_s, content.science.get("eva_policy", {}))
            if not Schema.number(q) or q < 0: return Schema.failure("invalid_state", "Invalid EVA workload rate.")
            var path = "suit/%s/%s/%s" % [c.expedition_id, id, key]
            var got = minf(q, e.suit_stores[id][key])
            requested[id][rid] = q
            provided[id][rid] = got
            debits[path] = got
            credits["sink/metabolism/" + rid] = credits.get("sink/metabolism/" + rid, 0.0) + got
            if got + 1e-15 < q: _unmet(unmet, id, NEED_CODES[rid])
    var co2 = 0.0
    var wastewater = 0.0
    for id in base_ids:
        var oxygen_fraction = _service_fraction(requested[id], provided[id], "oxygen_kg")
        var water_fraction = _service_fraction(requested[id], provided[id], "potable_water_kg")
        var food_fraction = _service_fraction(requested[id], provided[id], "food_kcal")
        co2 += m.base_outputs_per_s.co2_kg * oxygen_fraction
        wastewater += m.base_outputs_per_s.wastewater_kg * minf(water_fraction, food_fraction)
    debits["source/metabolism/co2_kg"] = co2
    credits["base/co2_kg"] = co2
    debits["source/metabolism/wastewater_kg"] = wastewater
    var waste: Dictionary = state.records.resources.wastewater_kg
    var retained = minf(wastewater, waste.capacity - waste.amount)
    credits["base/wastewater_kg"] = retained
    credits["sink/capacity_overflow/wastewater_kg"] = wastewater - retained
    var result = ledger.apply_system({"effect_id": "tick:%d:metabolism:crew" % ledger.tick,
        "kind": "conversion", "owner_id": "crew", "scope": "tick", "debits": debits, "credits": credits})
    if not result.ok: return result
    for id in unmet: unmet[id].sort()
    state.crew_demand = {"requested": requested, "provided": provided, "unmet_needs": unmet, "flows": result.flows,
        "wastewater_overflow_kg": wastewater - retained}
    return {"ok": true, "code": "ok", "reason": ""}

static func _unmet(unmet: Dictionary, id: String, code: String) -> void:
    if not unmet.has(id): unmet[id] = []
    unmet[id].append(code)

static func _service_fraction(requested: Dictionary, provided: Dictionary, rid: String) -> float:
    return provided[rid] / requested[rid] if requested.get(rid, 0.0) > 0 else 1.0
