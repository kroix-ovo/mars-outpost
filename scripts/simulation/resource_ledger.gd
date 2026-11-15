class_name OutpostResourceLedger
extends RefCounted
## Internal service: mutations affect a caller-owned candidate only. Receipts are
## staged here; the facade merges them only after the enclosing gameplay commit.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const TRANSFERS = ["eva_load", "eva_return", "cargo_return", "salvage_collect", "cache_return"]
const SYSTEM_KINDS = ["power_dispatch", "production", "conversion", "external_source", "external_sink"]
const EPS = 1e-12
var state: RefCounted
var content: Dictionary
var retained: Dictionary
var staged: Dictionary = {}
var tick_guards: Dictionary = {}
var tick: int
var registry: Dictionary = {}

func _init(candidate: RefCounted, definitions: Dictionary, receipts: Dictionary, tick_index: int) -> void:
    state = candidate
    content = definitions
    retained = receipts # Read-only shared collection, never duplicate or mutate it.
    tick = tick_index
    for resource in content.registry.resources: registry[resource.id] = resource

func apply_transfer(effect: Dictionary) -> Dictionary:
    return _apply(effect, false)

func apply_system(effect: Dictionary) -> Dictionary:
    # Trusted Task 01 call site only. Never forward a player/adapter kind here.
    return _apply(effect, true)

func _apply(effect: Dictionary, trusted: bool) -> Dictionary:
    if not Schema.exact_keys(effect, ["effect_id", "kind", "owner_id", "scope", "debits", "credits"]):
        return _fail("invalid_schema", "Invalid internal effect fields.")
    if not Schema.identifier(effect.effect_id) or not Schema.identifier(effect.owner_id) or effect.scope not in ["one_time", "tick"] or not effect.debits is Dictionary or not effect.credits is Dictionary:
        return _fail("invalid_schema", "Invalid internal effect record.")
    if (trusted and effect.kind not in SYSTEM_KINDS) or (not trusted and effect.kind not in TRANSFERS):
        return _fail("invalid_value", "Unauthorized effect kind.")
    if effect.scope == "tick" and not effect.effect_id.begins_with("tick:%d:" % tick):
        return _fail("invalid_value", "Tick effect must name the current interval.")
    if effect.scope == "one_time" and effect.effect_id.begins_with("tick:"):
        return _fail("invalid_value", "Tick IDs cannot have campaign retention.")
    var normalized = effect.duplicate(true)
    for side in ["debits", "credits"]:
        for path in effect[side]:
            if not path is String or not Schema.number(effect[side][path]) or effect[side][path] < 0:
                return _fail("invalid_value", "Nonnegative finite quantities required.")
            normalized[side][path] = float(effect[side][path])
    var fingerprint = Schema.canonical({"trusted": trusted, "effect": normalized})
    var prior: Dictionary = retained.get(effect.effect_id, staged.get(effect.effect_id, tick_guards.get(effect.effect_id, {})))
    if not prior.is_empty():
        if prior.fingerprint != fingerprint: return _fail("invalid_state", "Conflicting effect ID.")
        return prior.result.duplicate(true)
    var valid = validate()
    if not valid.ok: return valid
    var accounts: Dictionary = {}
    var totals: Dictionary = {"debits": {}, "credits": {}}
    for side in ["debits", "credits"]:
        for path in normalized[side]:
            var slot = _resolve(path, trusted)
            if not slot.ok: return slot
            if not slot.external and (not Schema.number(slot.amount) or not Schema.number(slot.reserved) or slot.amount < 0 or slot.reserved < 0 or slot.reserved > slot.amount or (slot.capacity != null and (not Schema.number(slot.capacity) or slot.capacity < slot.amount))):
                return _fail("invalid_value", "Invalid existing account bounds: " + path)
            var q: float = normalized[side][path]
            if registry[slot.resource].whole_valued and not Schema.whole(q):
                return _fail("invalid_value", "Count resources must remain whole.")
            if not trusted and not _allowed(effect, path, side):
                return _fail("invalid_value", "Transfer ownership/destination mismatch: " + path)
            if slot.external and ((slot.source and side != "debits") or (not slot.source and side != "credits")):
                return _fail("invalid_value", "Source/sink direction mismatch.")
            if not accounts.has(path):
                accounts[path] = {"slot": slot, "debits": 0.0, "credits": 0.0}
            accounts[path][side] += q
            totals[side][slot.resource] = totals[side].get(slot.resource, 0.0) + q
    for rid in registry:
        if not _close(totals.debits.get(rid, 0.0), totals.credits.get(rid, 0.0)):
            return _fail("invalid_value", "Unbalanced canonical resource: " + rid)
    if not trusted:
        var loss_check = _check_return_losses(effect, accounts)
        if not loss_check.ok: return loss_check
    # Energy aggregate paths expand into the same battery slots used by dispatch.
    # Reject aliases in one operation rather than double-spend the same reservoir.
    if accounts.has("base/energy_kwh"):
        for path in accounts:
            if path.begins_with("battery/"): return _fail("invalid_value", "Mixed aggregate/per-battery operation.")
    var writes: Array = []
    var battery_next = state.per_battery_energy.duplicate()
    var energy_debit = 0.0
    for path in accounts:
        var a: Dictionary = accounts[path]
        var s: Dictionary = a.slot
        if s.external: continue
        # A credit never finances the debit in this same transaction.
        if a.debits > s.amount - s.reserved:
            return _fail("insufficient_resources", "Insufficient available stock: " + path)
        var next: float = s.amount - a.debits + a.credits
        if not Schema.number(next) or next < 0:
            return _fail("invalid_value", "Invalid resulting amount: " + path)
        if s.capacity != null and next > s.capacity:
            return _fail("capacity_exceeded", "Capacity exceeded: " + path)
        if s.resource == "energy_kwh" and (path.begins_with("base/") or path.begins_with("battery/")):
            energy_debit += a.debits
            if path.begins_with("battery/"):
                battery_next[path.split("/")[1]] = next
            else:
                var debit: float = a.debits
                var credit: float = a.credits
                var ids = battery_next.keys()
                ids.sort()
                for id in ids:
                    var take = minf(debit, battery_next[id])
                    battery_next[id] -= take
                    debit -= take
                for id in ids:
                    var put = minf(credit, battery_capacity(id) - battery_next[id])
                    battery_next[id] += put
                    credit -= put
                if debit > EPS or credit > EPS: return _fail("invalid_state", "Energy expansion failed.")
        else:
            writes.append({"slot": s, "amount": next})
    # Respect base reservations for direct per-battery operations too.
    var energy: Dictionary = state.records.resources.energy_kwh
    if energy_debit > energy.amount - energy.reserved:
        return _fail("insufficient_resources", "Reserved energy cannot be spent.")
    var cargo_check = _check_cargo_totals(writes)
    if not cargo_check.ok: return cargo_check
    # No validation below this point can fail: apply the whole preflighted plan.
    for write in writes: write.slot.store[write.slot.key] = write.amount
    state.per_battery_energy = battery_next
    _sync_energy()
    var flows: Dictionary = {}
    for path in accounts:
        if accounts[path].slot.external:
            flows[path] = accounts[path].debits + accounts[path].credits
    var result = {"ok": true, "code": "ok", "reason": "", "applied_tick": tick, "flows": flows}
    var receipt = {"fingerprint": fingerprint, "result": result.duplicate(true)}
    if effect.scope == "one_time": staged[effect.effect_id] = receipt
    else: tick_guards[effect.effect_id] = receipt
    return result

func battery_capacity(id: String) -> float:
    var b: Dictionary = state.records.buildings[id]
    if b.lifecycle != "commissioned": return 0.0
    return float(content.buildings[b.definition_id].storage_capacity.get("energy_kwh", 0.0))

func _sync_energy() -> void:
    var amount = 0.0
    var capacity = 0.0
    var ids = state.per_battery_energy.keys()
    ids.sort()
    for id in ids:
        amount += state.per_battery_energy[id]
        capacity += battery_capacity(id)
    state.records.resources.energy_kwh.amount = amount
    state.records.resources.energy_kwh.capacity = capacity
    state.records.power.battery_stored_kwh = amount
    state.records.power.battery_capacity_kwh = capacity

func _resolve(path: String, trusted: bool) -> Dictionary:
    var p = path.split("/")
    var rid = p[-1]
    if p[0] == "suit" and rid == "battery_kwh": rid = "energy_kwh"
    if not registry.has(rid): return _fail("unknown_definition", "Unknown resource: " + rid)
    var store: Dictionary = {}
    var key: String = p[-1]
    var cap: Variant = null
    var reserved = 0.0
    if p.size() == 2 and p[0] == "loss" and rid in ["oxygen_kg", "energy_kwh"]:
        return {"ok": true, "resource": rid, "external": true, "source": false}
    if p.size() == 3 and p[0] in ["source", "sink"] and trusted:
        var names = ["generation", "production", "environment", "conversion"] if p[0] == "source" else ["load", "battery_loss", "curtailment", "conversion", "environment"]
        if p[1] not in names: return _fail("invalid_value", "Unknown source/sink classification.")
        return {"ok": true, "resource": rid, "external": true, "source": p[0] == "source"}
    if p.size() == 2 and p[0] == "base" and state.records.resources.has(rid):
        store = state.records.resources[rid]
        key = "amount"
        cap = store.capacity
        reserved = store.reserved
        if store.unit != registry[rid].unit: return _fail("invalid_value", "Resource unit mismatch.")
    elif p.size() == 3 and p[0] == "battery" and rid == "energy_kwh" and trusted and state.per_battery_energy.has(p[1]):
        store = state.per_battery_energy
        key = p[1]
        cap = battery_capacity(p[1])
    elif p.size() == 4 and p[0] == "suit" and state.records.expeditions.has(p[1]) and state.records.crew.has(p[2]):
        var e: Dictionary = state.records.expeditions[p[1]]
        if p[2] not in e.crew_ids or not e.suit_stores.has(p[2]) or not content.crew[state.records.crew[p[2]].definition_id].suit_capacity.has(key):
            return _fail("unknown_entity", "Suit ownership/capacity missing.")
        store = e.suit_stores[p[2]]
        cap = content.crew[state.records.crew[p[2]].definition_id].suit_capacity[key]
    elif p.size() == 3 and p[0] == "cargo" and state.records.expeditions.has(p[1]):
        store = state.records.expeditions[p[1]].cargo
    elif p.size() == 3 and p[0] == "site" and state.records.sites.has(p[1]):
        store = state.records.sites[p[1]].remaining_cargo
    elif p.size() == 3 and p[0] == "return_cache" and state.return_caches.has(p[1]) and state.records.expeditions.has(p[1]):
        store = state.return_caches[p[1]]
    else: return _fail("unknown_entity", "Unknown ledger account: " + path)
    if not store.has(key): return _fail("unknown_entity", "Missing existing account: " + path)
    return {"ok": true, "resource": rid, "external": false, "store": store, "key": key,
        "amount": store[key], "reserved": reserved, "capacity": cap, "path": path}

func _allowed(e: Dictionary, path: String, side: String) -> bool:
    var p = path.split("/")
    if not state.records.expeditions.has(e.owner_id): return false
    var expedition: Dictionary = state.records.expeditions[e.owner_id]
    var own = p.size() >= 3 and p[1] == e.owner_id
    match e.kind:
        "eva_load": return p[0] == "base" if side == "debits" else own and p[0] == "suit"
        "eva_return": return own and p[0] == "suit" if side == "debits" else p[0] in ["base", "loss"]
        "cargo_return": return own and p[0] == "cargo" if side == "debits" else p[0] == "base" or (own and p[0] == "return_cache")
        "cache_return": return own and p[0] == "return_cache" if side == "debits" else p[0] == "base"
        "salvage_collect":
            return p[0] == "site" and p[1] == expedition.site_id and state.records.sites[p[1]].reserved_by_expedition_id == e.owner_id if side == "debits" else own and p[0] == "cargo"
    return false

func _check_return_losses(e: Dictionary, accounts: Dictionary) -> Dictionary:
    for path in accounts:
        if path.begins_with("return_cache/") and e.kind == "cargo_return":
            var rid: String = accounts[path].slot.resource
            var base: Dictionary = state.records.resources[rid]
            var returned: float = e.debits.get("cargo/%s/%s" % [e.owner_id, rid], 0.0)
            var fit = minf(returned, base.capacity - base.amount) if base.capacity != null else returned
            if not _close(e.credits.get("base/" + rid, 0.0), fit) or not _close(e.credits[path], returned - fit):
                return _fail("invalid_value", "Cache credit must be precisely the cargo overflow.")
        if not path.begins_with("loss/"): continue
        if e.kind != "eva_return": return _fail("invalid_value", "Only suit returns permit loss.")
        var rid: String = accounts[path].slot.resource
        var base: Dictionary = state.records.resources[rid]
        var returned = 0.0
        for debit in e.debits:
            if accounts[debit].slot.resource == rid: returned += e.debits[debit]
        var fit = minf(returned, base.capacity - base.amount) if base.capacity != null else returned
        if not _close(e.credits.get("base/" + rid, 0.0), fit) or not _close(e.credits[path], returned - fit):
            return _fail("invalid_value", "Return loss must be precisely the overflow.")
    return _ok()

func _check_cargo_totals(writes: Array) -> Dictionary:
    for id in state.records.expeditions:
        var e: Dictionary = state.records.expeditions[id]
        var total = 0.0
        for rid in e.cargo:
            if not registry.has(rid) or registry[rid].unit != "count": return _fail("invalid_value", "Cargo must use declared item counts.")
            var amount: float = e.cargo[rid]
            for w in writes:
                if w.slot.path == "cargo/%s/%s" % [id, rid]: amount = w.amount
            if not Schema.whole(amount): return _fail("invalid_value", "Invalid cargo count.")
            total += amount
        var capacity = 0.0
        for cid in e.crew_ids:
            if not state.records.crew.has(cid): return _fail("unknown_entity", "Unknown expedition crew.")
            capacity += content.crew[state.records.crew[cid].definition_id].carry_capacity_count
        if total > capacity: return _fail("capacity_exceeded", "Expedition carry capacity exceeded.")
    return _ok()

func validate() -> Dictionary:
    if state.records.resources.size() != registry.size(): return _fail("invalid_state", "Missing base resources.")
    for id in state.records.buildings:
        var b: Dictionary = state.records.buildings[id]
        if not content.buildings.has(b.definition_id): return _fail("unknown_definition", "Unknown building definition.")
    for rid in state.records.resources:
        if not registry.has(rid): return _fail("unknown_definition", "Unknown base resource.")
        var b: Dictionary = state.records.resources[rid]
        if b.unit != registry[rid].unit or not Schema.number(b.amount) or not Schema.number(b.reserved) or b.amount < 0 or b.reserved < 0 or b.reserved > b.amount:
            return _fail("invalid_value", "Invalid base balance/unit.")
        if registry[rid].whole_valued and (not Schema.whole(b.amount) or not Schema.whole(b.reserved)):
            return _fail("invalid_value", "Invalid base count.")
        if registry[rid].capacity_policy == "accumulator":
            if b.capacity != null: return _fail("invalid_value", "Accumulator capacity must be null.")
        elif not Schema.number(b.capacity) or b.capacity < b.amount:
            return _fail("capacity_exceeded", "Invalid storage capacity.")
        elif registry[rid].whole_valued and not Schema.whole(b.capacity):
            return _fail("invalid_value", "Invalid count capacity.")
    var sum_energy = 0.0
    var sum_capacity = 0.0
    var ids = state.per_battery_energy.keys()
    ids.sort()
    for id in ids:
        if not state.records.buildings.has(id): return _fail("unknown_entity", "Missing battery building.")
        var q: Variant = state.per_battery_energy[id]
        var cap = battery_capacity(id)
        if not Schema.number(q) or q < 0 or q > cap: return _fail("invalid_value", "Invalid battery energy.")
        sum_energy += q
        sum_capacity += cap
    for id in state.records.buildings:
        var b: Dictionary = state.records.buildings[id]
        if content.buildings[b.definition_id].storage_capacity.get("energy_kwh", 0.0) > 0 and not state.per_battery_energy.has(id):
            return _fail("invalid_state", "Missing per-battery account.")
    if not _close(sum_energy, state.records.resources.energy_kwh.amount) or not _close(sum_energy, state.records.power.battery_stored_kwh) or not _close(sum_capacity, state.records.resources.energy_kwh.capacity) or not _close(sum_capacity, state.records.power.battery_capacity_kwh):
        return _fail("invalid_state", "Battery aggregate mismatch.")
    for eid in state.records.expeditions:
        var e: Dictionary = state.records.expeditions[eid]
        for cid in e.suit_stores:
            for rid in e.suit_stores[cid]:
                var s = _resolve("suit/%s/%s/%s" % [eid, cid, rid], false)
                if not s.ok: return s
                if not Schema.number(s.amount) or not Schema.number(s.capacity) or s.amount < 0 or s.amount > s.capacity: return _fail("invalid_value", "Invalid suit balance.")
    for prefix in ["site", "return_cache"]:
        var collection: Dictionary = state.records.sites if prefix == "site" else state.return_caches
        for id in collection:
            var balances: Dictionary = collection[id].remaining_cargo if prefix == "site" else collection[id]
            for rid in balances:
                if not registry.has(rid) or not Schema.number(balances[rid]) or balances[rid] < 0 or (registry[rid].whole_valued and not Schema.whole(balances[rid])):
                    return _fail("invalid_value", "Invalid remote balance.")
    return _check_cargo_totals([])

static func _close(a: float, b: float) -> bool:
    return absf(a - b) <= EPS * maxf(1.0, maxf(absf(a), absf(b)))

static func _ok() -> Dictionary:
    return {"ok": true, "code": "ok", "reason": ""}

static func _fail(code: String, reason: String) -> Dictionary:
    return Schema.failure(code, reason)
