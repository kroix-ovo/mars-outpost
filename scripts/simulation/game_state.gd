class_name OutpostGameState
extends RefCounted
## Transactional gameplay state. The facade owns the retained command journal.

var records: Dictionary = {}
var accumulator_s: float = 0.0
var counters: Dictionary = {"building": 0, "crew": 0, "task": 0, "expedition": 0, "event": 0}
var rng = RandomNumberGenerator.new()
var per_battery_energy: Dictionary = {}
# Save-only authoritative fields, not additional public snapshot keys.
var return_caches: Dictionary = {}
var power_flows: Dictionary = {}
var life_support_flows: Dictionary = {}
var crew_demand: Dictionary = {"requested": {}, "provided": {}, "unmet_needs": {}, "flows": {}, "wastewater_overflow_kg": 0.0}

func allocate(kind: String) -> String:
    counters[kind] += 1
    return "%s_%06d" % [kind, counters[kind]]

func clone() -> OutpostGameState:
    var copy = get_script().new()
    copy.records = records.duplicate(true)
    copy.accumulator_s = accumulator_s
    copy.counters = counters.duplicate(true)
    copy.per_battery_energy = per_battery_energy.duplicate(true)
    copy.return_caches = return_caches.duplicate(true)
    copy.power_flows = power_flows.duplicate(true)
    copy.life_support_flows = life_support_flows.duplicate(true)
    copy.crew_demand = crew_demand.duplicate(true)
    copy.rng.seed = rng.seed
    copy.rng.state = rng.state
    return copy

func snapshot() -> Dictionary:
    var result = records.duplicate(true)
    result.rng = {"seed": str(rng.seed), "state": str(rng.state)}
    return result

func populate(config: Dictionary, content: Dictionary) -> void:
    var scenario: Dictionary = content.scenario
    rng.seed = int(config.seed)
    records = {"contract_version": "2.0.0", "snapshot_version": 2,
        "campaign_id": config.campaign_id, "revision": 0,
        "clock": {"tick_index": 0, "elapsed_s": 0.0, "time_scale": 1},
        "map": {"id": config.map_id, "revision": int(config.map_revision)},
        "resources": {}, "power": {"generated_kw": 0.0, "requested_kw": 0.0,
            "served_kw": 0.0, "battery_stored_kwh": 0.0, "battery_capacity_kwh": 0.0},
        "buildings": {}, "crew": {}, "tasks": {}, "expeditions": {}, "sites": {},
        "technology": {"unlocked_ids": scenario.technology_unlocked_ids.duplicate()},
        "active_events": {}, "alerts": []}
    for item in scenario.starting_buildings:
        var id = allocate("building")
        records.buildings[id] = {"id": id, "definition_id": item.definition_id,
            "cell": [int(item.cell[0]), int(item.cell[1])], "rotation_quarters": int(item.rotation_quarters),
            "lifecycle": "commissioned", "enabled": item.enabled, "condition": float(item.condition),
            "construction_task_id": null, "construction_progress": 1.0,
            "power_requested_kw": 0.0, "power_served_kw": 0.0, "operating_fraction": 0.0, "blocking_codes": []}
        var capacity = float(content.buildings[item.definition_id].storage_capacity.get("energy_kwh", 0.0))
        if capacity > 0:
            per_battery_energy[id] = float(item.get("battery_stored_kwh", 0.0))
            records.power.battery_stored_kwh += per_battery_energy[id]
            records.power.battery_capacity_kwh += capacity
    for resource in content.registry.resources:
        var capacity: Variant = float(scenario.starting_storage_capacity.get(resource.id, 0.0))
        for item in scenario.starting_buildings:
            capacity += float(content.buildings[item.definition_id].storage_capacity.get(resource.id, 0.0))
        if resource.capacity_policy == "accumulator": capacity = null
        var amount = float(scenario.starting_inventory.get(resource.id, 0.0))
        if resource.id == "energy_kwh":
            capacity = records.power.battery_capacity_kwh
            amount = records.power.battery_stored_kwh
        records.resources[resource.id] = {"id": resource.id, "unit": resource.unit,
            "amount": amount, "capacity": capacity, "reserved": 0.0,
            "net_rate_per_s": 0.0, "forecast_empty_s": null}
    var airlock: Array = content.map.base_airlock_cell
    for definition_id in config.initial_crew_definition_ids:
        var id = allocate("crew")
        var definition: Dictionary = content.crew[definition_id]
        records.crew[id] = {"id": id, "definition_id": definition_id, "display_name": definition.display_name,
            "status": "idle", "location_kind": "base", "position_m": [airlock[0] + 0.5, 0.0, airlock[1] + 0.5],
            "task_id": null, "expedition_id": null, "health": 1.0, "fatigue": 0.0, "stress": 0.0,
            "radiation_dose_msv": 0.0, "skills": definition.skills.duplicate(true)}
    for item in scenario.sites:
        records.sites[item.id] = {"id": item.id, "definition_id": item.definition_id,
            "cell": [int(item.cell[0]), int(item.cell[1])], "reserved_by_expedition_id": null,
            "remaining_cargo": item.cargo.duplicate(true)}
