class_name OutpostLifeSupportSystem
extends RefCounted
## Phase 4. Linear A3 chemistry only, no construction, crops or generic plugins.
const Schema = preload("res://scripts/simulation/command_schemas.gd")

static func validate_process(definition: Dictionary) -> Dictionary:
    var inputs: Dictionary = definition.process.inputs_per_s
    var outputs: Dictionary = definition.process.outputs_per_s
    for rates in [inputs, outputs]:
        for rid in rates:
            if not Schema.number(rates[rid]) or rates[rid] < 0: return Schema.failure("invalid_value", "Invalid process rate.")
    if inputs.is_empty() and outputs.is_empty(): return {"ok": true, "kind": "none"}
    if Schema.exact_keys(inputs, ["potable_water_kg"]) and Schema.exact_keys(outputs, ["oxygen_kg", "hydrogen_kg"]):
        var water: float = inputs.potable_water_kg
        if absf(outputs.oxygen_kg - water * 8.0 / 9.0) > 1e-12 + water * 1e-8 or absf(outputs.hydrogen_kg - water / 9.0) > 1e-12 + water * 1e-8:
            return Schema.failure("invalid_value", "A3 electrolysis must use the documented rounded 8:1 product mass ratio.")
        return {"ok": true, "kind": "electrolysis"}
    if Schema.exact_keys(inputs, ["wastewater_kg"]) and Schema.exact_keys(outputs, ["potable_water_kg"]):
        if outputs.potable_water_kg > inputs.wastewater_kg:
            return Schema.failure("invalid_value", "Recycler cannot create more water than it processes.")
        return {"ok": true, "kind": "recycling"}
    if Schema.exact_keys(inputs, ["co2_kg"]) and outputs.is_empty():
        return {"ok": true, "kind": "co2_removal"}
    return Schema.failure("module_unavailable", "Only electrolysis, water recycling and CO2 removal execute in A3.")

func run(state: RefCounted, content: Dictionary, ledger: RefCounted) -> Dictionary:
    var ids = state.records.buildings.keys()
    ids.sort_custom(func(a, b):
        var pa: float = content.buildings[state.records.buildings[a].definition_id].process_priority
        var pb: float = content.buildings[state.records.buildings[b].definition_id].process_priority
        return a < b if pa == pb else pa > pb)
    var flows: Dictionary = {}
    var idle_kwh = 0.0
    for id in ids:
        var b: Dictionary = state.records.buildings[id]
        if b.lifecycle != "commissioned" or not b.enabled or b.condition <= 0: continue
        var d: Dictionary = content.buildings[b.definition_id]
        var checked = validate_process(d)
        if not checked.ok: return checked
        if checked.kind == "none":
            if d.power_generation_kw == 0: b.operating_fraction = b.condition
            continue
        var inputs: Dictionary = d.process.inputs_per_s
        var outputs: Dictionary = d.process.outputs_per_s
        var pf: float = b.power_served_kw / d.power_demand_kw if d.power_demand_kw > 0 else 1.0
        var fraction = minf(pf, b.condition)
        var initial_fraction = fraction
        var any_rate = false
        var input_ids = inputs.keys()
        var output_ids = outputs.keys()
        input_ids.sort()
        output_ids.sort()
        for rid in input_ids:
            var rate: float = inputs[rid]
            if rate <= 0: continue
            any_rate = true
            var balance: Dictionary = state.records.resources[rid]
            var possible: float = (balance.amount - balance.reserved) / rate
            if possible < initial_fraction: b.blocking_codes.append("input_limited:" + rid)
            fraction = minf(fraction, possible)
        for rid in output_ids:
            var rate: float = outputs[rid]
            if rate <= 0: continue
            var balance: Dictionary = state.records.resources[rid]
            if balance.capacity == null: continue
            var possible: float = (balance.capacity - balance.amount) / rate
            if possible < initial_fraction: b.blocking_codes.append("output_full:" + rid)
            fraction = minf(fraction, possible)
        if not any_rate: fraction = 0.0
        if not Schema.number(fraction) or fraction < 0 or fraction > 1:
            return Schema.failure("invalid_state", "Invalid process operating fraction.")
        var debits: Dictionary = {}
        var credits: Dictionary = {}
        for rid in input_ids:
            var available: float = state.records.resources[rid].amount - state.records.resources[rid].reserved
            var q = minf(inputs[rid] * fraction, available)
            debits["base/" + rid] = q
            credits["sink/conversion/" + rid] = q
        for rid in output_ids:
            var q: float = outputs[rid] * fraction
            var balance: Dictionary = state.records.resources[rid]
            if balance.capacity != null: q = minf(q, balance.capacity - balance.amount)
            debits["source/conversion/" + rid] = q
            credits["base/" + rid] = q
        if checked.kind == "co2_removal":
            credits.erase("sink/conversion/co2_kg")
            credits["sink/process_removal/co2_kg"] = debits["base/co2_kg"]
        elif checked.kind == "recycling":
            var loss: float = debits["base/wastewater_kg"] - credits["base/potable_water_kg"]
            if loss < -1e-15: return Schema.failure("invalid_state", "Negative recycler loss.")
            credits["sink/conversion/wastewater_kg"] = credits["base/potable_water_kg"]
            credits["sink/recycler_loss/wastewater_kg"] = maxf(0.0, loss)
        var result = ledger.apply_system({"effect_id": "tick:%d:process:%s" % [ledger.tick, id],
            "kind": "conversion", "owner_id": id, "scope": "tick", "debits": debits, "credits": credits})
        if not result.ok: return result
        for path in result.flows: flows[path] = flows.get(path, 0.0) + result.flows[path]
        if pf > 0: idle_kwh += b.power_served_kw / 3600.0 * (1.0 - fraction / pf)
        b.operating_fraction = fraction
        b.blocking_codes.sort()
    var classified = ledger.classify_idle_power(idle_kwh)
    if not classified.ok: return classified
    state.life_support_flows = flows
    return {"ok": true, "code": "ok", "reason": ""}
