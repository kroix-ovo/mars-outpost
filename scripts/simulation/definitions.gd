class_name OutpostDefinitions
extends RefCounted
## Hash-verified fixture loading. Production content formats await Tasks 02/03.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const LifeSupport = preload("res://scripts/systems/life_support_system.gd")
const CrewDemand = preload("res://scripts/systems/crew_demand_system.gd")
var _files: Dictionary = {}
var _error: Dictionary = {}

func load_config(config: Dictionary) -> Dictionary:
    _files = {}
    _error = {}
    if not Schema.exact_keys(config, ["campaign_id", "seed", "initial_crew_definition_ids", "map_id",
            "map_revision", "definition_manifest", "scenario_path", "science_config_path"]):
        return _fail("invalid_schema", "Initialization keys do not match the schema.")
    if not Schema.identifier(config.campaign_id) or not Schema.identifier(config.map_id) or not _seed(config.seed):
        return _fail("invalid_value", "Invalid campaign, map, or decimal seed.")
    if not Schema.whole(config.map_revision) or not config.initial_crew_definition_ids is Array:
        return _fail("invalid_value", "Invalid map revision or crew list.")
    var crew_ids: Array = config.initial_crew_definition_ids
    if crew_ids.size() < 5 or crew_ids.size() > 9:
        return _fail("invalid_value", "Initial crew size must be 5 through 9.")
    var seen = {}
    for id in crew_ids:
        if not Schema.identifier(id) or seen.has(id): return _fail("invalid_value", "Invalid or duplicate crew definition ID.")
        seen[id] = true
    if not config.definition_manifest is Dictionary or config.definition_manifest.is_empty():
        return _fail("invalid_schema", "A nonempty definition manifest is required.")
    for path in config.definition_manifest:
        var digest: Variant = config.definition_manifest[path]
        if not path is String or not path.begins_with("res://") or path.simplify_path() != path or not path.ends_with(".json"):
            return _fail("invalid_value", "Manifest paths must be normalized project JSON paths.")
        if not digest is String or digest.length() != 64 or not digest.is_valid_hex_number(false):
            return _fail("invalid_value", "Invalid SHA-256 digest.")
        if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != digest:
            return _fail("definition_mismatch", "Content hash mismatch: " + path)
        var parser = JSON.new()
        if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary or not _finite_tree(parser.data):
            return _fail("invalid_schema", "Invalid JSON definition: " + path)
        if not Schema.whole(parser.data.get("schema_version"), 1, 1):
            return _fail("invalid_schema", "Unsupported content schema: " + path)
        _files[path] = parser.data
    var scenario = _file(config.scenario_path)
    var science = _file(config.science_config_path)
    if not _error.is_empty(): return _error
    if not _keys(scenario, {"resource_registry_path": TYPE_STRING, "building_definition_paths": TYPE_ARRAY,
            "crew_definition_path": TYPE_STRING, "map_path": TYPE_STRING, "starting_buildings": TYPE_ARRAY,
            "starting_inventory": TYPE_DICTIONARY, "starting_storage_capacity": TYPE_DICTIONARY,
            "sites": TYPE_ARRAY, "scheduled_events": TYPE_ARRAY, "technology_unlocked_ids": TYPE_ARRAY}):
        return _fail("invalid_schema", "Incomplete scenario definition.")
    if not scenario.get("metadata") is Dictionary or not science.get("metadata") is Dictionary:
        return _fail("invalid_schema", "Scenario/science metadata must be objects.")
    if scenario.metadata.get("status") != "synthetic_test_fixture" or science.metadata.get("status") not in ["synthetic_test_fixture", "source_backed_reference_model"]:
        return _fail("module_unavailable", "Use an explicitly synthetic scenario and documented synthetic/reference science profile.")
    var science_checked = CrewDemand.validate_science(science)
    if not science_checked.ok: return science_checked
    if science.metadata.status == "source_backed_reference_model" and (not science.metadata.get("science_record_ids") is Array or science.metadata.science_record_ids.is_empty()):
        return _fail("invalid_schema", "Reference profile requires SCIENCE.md provenance IDs.")
    if not scenario.scheduled_events.is_empty(): return _fail("module_unavailable", "Scheduled event execution belongs to A5.")
    var registry = _file(scenario.resource_registry_path)
    var crew_file = _file(scenario.crew_definition_path)
    var map_file = _file(scenario.map_path)
    if not _error.is_empty(): return _error
    if not registry.get("resources") is Array or not crew_file.get("definitions") is Array:
        return _fail("invalid_schema", "Registry and crew definitions must contain arrays.")
    if map_file.get("id") != config.map_id or map_file.get("revision") != config.map_revision or not Schema.cell(map_file.get("base_airlock_cell")):
        return _fail("definition_mismatch", "Map identity, revision, or airlock is invalid.")
    if not Schema.cell(map_file.get("size_cells")) or map_file.size_cells[0] <= 0 or map_file.size_cells[1] <= 0 or not _inside(map_file.base_airlock_cell, map_file.size_cells):
        return _fail("invalid_value", "Invalid map size or airlock bounds.")
    var resources = {}
    for item in registry.resources:
        if not item is Dictionary or not _keys(item, {"id": TYPE_STRING, "unit": TYPE_STRING, "whole_valued": TYPE_BOOL, "capacity_policy": TYPE_STRING}):
            return _fail("invalid_schema", "Invalid resource definition.")
        if not Schema.identifier(item.id) or resources.has(item.id) or item.unit not in ["kg", "kwh", "kcal", "count"] or item.capacity_policy not in ["storage", "accumulator"] or item.whole_valued != (item.unit == "count"):
            return _fail("invalid_value", "Invalid resource identity, unit, or capacity policy.")
        resources[item.id] = item
    for id in ["oxygen_kg", "co2_kg", "raw_water_kg", "potable_water_kg", "wastewater_kg", "hydrogen_kg", "food_kcal", "energy_kwh", "alloy", "electronics"]:
        if not resources.has(id): return _fail("invalid_schema", "Missing core resource: " + id)
    if resources.co2_kg.capacity_policy != "accumulator" or resources.energy_kwh.capacity_policy != "storage":
        return _fail("invalid_value", "Invalid CO2 or electrical energy capacity policy.")
    if not _quantities(scenario.starting_inventory, resources) or not _quantities(scenario.starting_storage_capacity, resources):
        return _fail("invalid_value", "Invalid starting inventory/storage.")
    var buildings = {}
    for path in scenario.building_definition_paths:
        var definition = _file(path)
        if not _error.is_empty(): return _error
        if not _building(definition, resources) or buildings.has(definition.get("id")):
            return _fail("invalid_schema", "Invalid or duplicate building definition.")
        buildings[definition.id] = definition
    var capacities = scenario.starting_storage_capacity.duplicate(true)
    var energy = 0.0
    var occupied = {}
    for item in scenario.starting_buildings:
        if not item is Dictionary or not _keys(item, {"definition_id": TYPE_STRING, "cell": TYPE_ARRAY, "enabled": TYPE_BOOL}) or not Schema.cell(item.cell) or not _inside(item.cell, map_file.size_cells) or not Schema.whole(item.get("rotation_quarters"), 0, 3) or not _fraction(item.get("condition")) or not buildings.has(item.definition_id):
            return _fail("invalid_value", "Invalid initial building.")
        var definition: Dictionary = buildings[item.definition_id]
        var process_checked = LifeSupport.validate_process(definition)
        if not process_checked.ok: return process_checked
        for offset in definition.footprint_cells:
            var x = int(offset[0])
            var z = int(offset[1])
            for turn in int(item.rotation_quarters):
                var prior_x = x
                x = -z
                z = prior_x
            var occupied_cell = [x + int(item.cell[0]), z + int(item.cell[1])]
            if not _inside(occupied_cell, map_file.size_cells): return _fail("placement_blocked", "Initial footprint is outside map bounds.")
            var key = str(occupied_cell)
            if occupied.has(key): return _fail("placement_blocked", "Initial buildings overlap.")
            occupied[key] = true
        for id in definition.storage_capacity:
            capacities[id] = capacities.get(id, 0.0) + definition.storage_capacity[id]
        var stored: Variant = item.get("battery_stored_kwh", 0.0)
        if not _nonnegative(stored) or stored > definition.storage_capacity.get("energy_kwh", 0.0):
            return _fail("capacity_exceeded", "Invalid initial battery energy.")
        energy += stored
    if scenario.starting_storage_capacity.get("energy_kwh", 0.0) != 0 or scenario.starting_inventory.get("energy_kwh", 0.0) != 0:
        return _fail("invalid_value", "Starting electrical energy must be backed by batteries.")
    for id in scenario.starting_inventory:
        if resources[id].capacity_policy == "storage" and scenario.starting_inventory[id] > capacities.get(id, 0.0):
            return _fail("capacity_exceeded", "Starting inventory exceeds capacity: " + id)
    var crew = {}
    for definition in crew_file.definitions:
        if not definition is Dictionary or not _keys(definition, {"id": TYPE_STRING, "display_name": TYPE_STRING, "skills": TYPE_DICTIONARY}) or not Schema.identifier(definition.id) or crew.has(definition.id):
            return _fail("invalid_schema", "Invalid crew definition.")
        for skill in definition.skills:
            if not Schema.identifier(skill) or not _fraction(definition.skills[skill]): return _fail("invalid_value", "Invalid crew skill.")
        crew[definition.id] = definition
    for id in crew_ids:
        if not crew.has(id): return _fail("unknown_definition", "Unknown crew definition: " + id)
    var sites = {}
    for site in scenario.sites:
        if not site is Dictionary or not _keys(site, {"id": TYPE_STRING, "definition_id": TYPE_STRING, "cargo": TYPE_DICTIONARY}) or not Schema.identifier(site.id) or not Schema.cell(site.get("cell")) or not _inside(site.cell, map_file.size_cells) or sites.has(site.id) or not _quantities(site.cargo, resources):
            return _fail("invalid_schema", "Invalid site definition.")
        sites[site.id] = true
    if not science.get("time") is Dictionary or science.time.get("tick_s") != 1.0 or not _nonnegative(science.time.get("sol_s")) or science.time.sol_s == 0:
        return _fail("invalid_value", "Invalid fixture timestep/sol configuration.")
    return {"ok": true, "code": "ok", "reason": "", "scenario": scenario,
        "science": science, "registry": registry, "buildings": buildings, "crew": crew, "map": map_file}

func _file(path: Variant) -> Dictionary:
    if not path is String or not _files.has(path):
        _error = _fail("definition_mismatch", "Referenced content is absent from the manifest.")
        return {}
    return _files[path]

static func _building(item: Dictionary, resources: Dictionary) -> bool:
    if not _keys(item, {"id": TYPE_STRING, "footprint_cells": TYPE_ARRAY, "entrance_cells": TYPE_ARRAY,
            "build_cost": TYPE_DICTIONARY, "storage_capacity": TYPE_DICTIONARY, "process": TYPE_DICTIONARY}): return false
    if not Schema.identifier(item.id) or item.footprint_cells.is_empty() or item.entrance_cells.is_empty(): return false
    var cells = {}
    for offset in item.footprint_cells:
        if not Schema.cell(offset) or cells.has(str(offset)): return false
        cells[str(offset)] = true
    for offset in item.entrance_cells:
        if not Schema.cell(offset) or cells.has(str(offset)): return false
    for field in ["construction_work_s", "power_generation_kw", "power_demand_kw", "battery_charge_limit_kw", "battery_discharge_limit_kw", "maintenance_work_s_per_s"]:
        if not _nonnegative(item.get(field)): return false
    for field in ["battery_charge_efficiency", "battery_discharge_efficiency"]:
        if not _fraction(item.get(field)) or item[field] == 0.0: return false
    for field in ["power_priority", "process_priority"]:
        if not Schema.whole(item.get(field)): return false
    return _quantities(item.build_cost, resources) and _quantities(item.storage_capacity, resources) and item.process.get("inputs_per_s") is Dictionary and item.process.get("outputs_per_s") is Dictionary and _quantities(item.process.inputs_per_s, resources, false) and _quantities(item.process.outputs_per_s, resources, false)

static func _quantities(values: Dictionary, resources: Dictionary, enforce_counts: bool = true) -> bool:
    for id in values:
        if not resources.has(id) or not _nonnegative(values[id]): return false
        if enforce_counts and resources[id].whole_valued and not Schema.whole(values[id]): return false
    return true

static func _keys(value: Dictionary, schema: Dictionary) -> bool:
    for key in schema:
        if not value.has(key) or typeof(value[key]) != schema[key]: return false
    return true

static func _finite_tree(value: Variant) -> bool:
    if value is float: return is_finite(value)
    if value is Dictionary:
        for item in value.values():
            if not _finite_tree(item): return false
    if value is Array:
        for item in value:
            if not _finite_tree(item): return false
    return true

static func _seed(value: Variant) -> bool:
    if not value is String or value.is_empty() or value.length() > 19: return false
    for index in value.length():
        if value[index] < "0" or value[index] > "9": return false
    return (value == "0" or not value.begins_with("0")) and (value.length() < 19 or value <= "9223372036854775807")

static func _nonnegative(value: Variant) -> bool:
    return Schema.number(value) and value >= 0.0

static func _fraction(value: Variant) -> bool:
    return _nonnegative(value) and value <= 1.0

static func _inside(cell: Array, size: Array) -> bool:
    return cell[0] >= 0 and cell[1] >= 0 and cell[0] < size[0] and cell[1] < size[1]

static func _fail(code: String, reason: String) -> Dictionary:
    return Schema.failure(code, reason)
