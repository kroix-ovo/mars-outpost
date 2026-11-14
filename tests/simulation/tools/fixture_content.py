"""Static synthetic fixture content: definitions, scenarios, init configs.

Every quantity is synthetic and chosen for easy hand arithmetic. Nothing here is a
physiological, equipment, or planetary value. The crew, task-template, and map
formats are Task 01 test stubs until Tasks 02/03 adopt production formats.
"""

SYN = {"status": "synthetic_test_fixture"}
RES_ROOT = "res://tests/simulation/fixtures/"

RESOURCES = {
    "schema_version": 1,
    "id": "fixture_resource_registry",
    "metadata": SYN,
    "resources": [
        {"id": "alloy", "unit": "count", "whole_valued": True, "capacity_policy": "storage"},
        {"id": "co2_kg", "unit": "kg", "whole_valued": False, "capacity_policy": "accumulator"},
        {"id": "electronics", "unit": "count", "whole_valued": True, "capacity_policy": "storage"},
        {"id": "energy_kwh", "unit": "kwh", "whole_valued": False, "capacity_policy": "storage"},
        {"id": "food_kcal", "unit": "kcal", "whole_valued": False, "capacity_policy": "storage"},
        {"id": "hydrogen_kg", "unit": "kg", "whole_valued": False, "capacity_policy": "storage"},
        {"id": "oxygen_kg", "unit": "kg", "whole_valued": False, "capacity_policy": "storage"},
        {"id": "potable_water_kg", "unit": "kg", "whole_valued": False, "capacity_policy": "storage"},
        {"id": "raw_water_kg", "unit": "kg", "whole_valued": False, "capacity_policy": "storage"},
        {"id": "wastewater_kg", "unit": "kg", "whole_valued": False, "capacity_policy": "storage"},
    ],
}

SCIENCE = {
    "schema_version": 1,
    "id": "fixture_science_synthetic",
    "metadata": {
        "status": "synthetic_test_fixture",
        "warning": "Every value in this file is synthetic and chosen for easy arithmetic. None is a physiological, equipment, or planetary value. Do not copy into data/ or SCIENCE.md.",
    },
    "time": {"tick_s": 1.0, "sol_s": 1000.0},
    "crew_metabolism": {
        "time_basis": "per_simulated_second",
        "base_activity_rates_per_s": {
            "idle": {"oxygen_kg": 0.001, "potable_water_kg": 0.002, "food_kcal": 1.0},
            "working": {"oxygen_kg": 0.001, "potable_water_kg": 0.002, "food_kcal": 1.0},
        },
        "base_outputs_per_s": {"co2_kg": 0.001, "wastewater_kg": 0.002},
        "eva_suit_rates_per_s": {"oxygen_kg": 0.002, "battery_kwh": 0.0001},
        "eva_draws_base_water_and_food": False,
    },
    "eva_policy": {"reserve_fraction": 0.25},
    "losses": {"oxygen_leak_kg_per_s": 0.0},
    "alerts": {
        "low_oxygen_forecast_s": 600.0,
        "co2_high_kg": 1.0,
        "battery_low_fraction": 0.1,
        "expedition_low_margin_s": 10.0,
    },
}


def building(id_, name, *, cost, work, gen=0.0, demand=0.0, ppri=0, procpri=0,
             inputs=None, outputs=None, storage=None, batt=None):
    b = batt or {}
    return {
        "schema_version": 1,
        "id": id_,
        "display_name": name,
        "scene_path": None,
        "footprint_cells": [[0, 0]],
        "entrance_cells": [[0, 1]],
        "build_cost": cost,
        "construction_work_s": work,
        "power_generation_kw": gen,
        "power_demand_kw": demand,
        "power_priority": ppri,
        "process_priority": procpri,
        "process": {"inputs_per_s": inputs or {}, "outputs_per_s": outputs or {}},
        "storage_capacity": storage or {},
        "battery_charge_limit_kw": b.get("charge", 0.0),
        "battery_discharge_limit_kw": b.get("discharge", 0.0),
        "battery_charge_efficiency": b.get("ceff", 1.0),
        "battery_discharge_efficiency": b.get("deff", 1.0),
        "maintenance_work_s_per_s": 0.0,
        "unlocks_required": [],
        "metadata": SYN,
    }


BUILDINGS = {
    "fixture_generator": building("fixture_generator", "Fixture Generator",
                                  cost={"alloy": 1}, work=5.0, gen=3.0),
    "fixture_battery": building("fixture_battery", "Fixture Battery",
                                cost={"alloy": 1, "electronics": 1}, work=5.0,
                                storage={"energy_kwh": 40.0},
                                batt={"charge": 2.0, "discharge": 2.0, "ceff": 0.9, "deff": 0.9}),
    "fixture_electrolyzer": building("fixture_electrolyzer", "Fixture Electrolyzer",
                                     cost={"alloy": 2}, work=10.0, demand=1.0, ppri=100, procpri=100,
                                     inputs={"potable_water_kg": 0.009},
                                     outputs={"oxygen_kg": 0.008, "hydrogen_kg": 0.001}),
    "fixture_water_recycler": building("fixture_water_recycler", "Fixture Water Recycler",
                                       cost={"alloy": 2}, work=10.0, demand=0.5, ppri=50, procpri=200,
                                       inputs={"wastewater_kg": 0.012},
                                       outputs={"potable_water_kg": 0.012}),
    "fixture_co2_scrubber": building("fixture_co2_scrubber", "Fixture CO2 Scrubber",
                                     cost={"alloy": 2}, work=10.0, demand=0.5, ppri=200, procpri=300,
                                     inputs={"co2_kg": 0.006}),
    "fixture_storage_module": building("fixture_storage_module", "Fixture Storage Module",
                                       cost={"alloy": 10, "electronics": 2}, work=20.0,
                                       storage={"oxygen_kg": 100.0}),
}

CREW_SKILL_ROWS = [
    ("a", "engineering", "geology"), ("b", "botany", "medicine"), ("c", "engineering", "piloting"),
    ("d", "geology", "engineering"), ("e", "medicine", "botany"), ("f", "piloting", "geology"),
    ("g", "botany", "engineering"), ("h", "geology", "medicine"), ("i", "engineering", "botany"),
]
SKILLS = ["botany", "engineering", "geology", "medicine", "piloting"]


def crew_defs():
    out = []
    for letter, primary, secondary in CREW_SKILL_ROWS:
        skills = {s: 0.2 for s in SKILLS}
        skills[primary] = 0.8
        skills[secondary] = 0.5
        out.append({
            "id": f"fixture_crew_{letter}",
            "display_name": f"Fixture Crew {letter.upper()}",
            "primary_skill": primary,
            "secondary_skill": secondary,
            "skills": skills,
            "movement_speed_m_per_s": 1.0,
            "suit_capacity": {"oxygen_kg": 0.2, "battery_kwh": 0.01},
            "carry_capacity_count": 3,
            "metadata": SYN,
        })
    return {"schema_version": 1, "id": "fixture_crew", "owner": "task_03_proposal",
            "metadata": SYN, "definitions": out}


TASK_TEMPLATES = {
    "schema_version": 1,
    "id": "fixture_task_templates",
    "owner": "task_03_proposal",
    "metadata": SYN,
    "templates": {
        "construct": {"crew_required": 1, "default_priority": 50, "labor_rate_work_s_per_crew_s": 1.0},
        "eva": {"crew_required": "from_command", "default_priority": 50},
    },
}

MAP = {
    "schema_version": 1,
    "id": "fixture_flat_16",
    "revision": 1,
    "owner": "task_02_proposal",
    "metadata": SYN,
    "size_cells": [16, 16],
    "default_cell": {"passable": True, "buildable": True, "height_m": 0.0},
    "cell_overrides": [],
    "base_airlock_cell": [2, 8],
}

HABITAT_BUILDINGS = [
    {"definition_id": "fixture_generator", "cell": [3, 3], "rotation_quarters": 0, "enabled": True, "condition": 1.0},
    {"definition_id": "fixture_battery", "cell": [5, 3], "rotation_quarters": 0, "enabled": True, "condition": 1.0,
     "battery_stored_kwh": 18.0},
    {"definition_id": "fixture_electrolyzer", "cell": [7, 3], "rotation_quarters": 0, "enabled": True, "condition": 1.0},
    {"definition_id": "fixture_water_recycler", "cell": [9, 3], "rotation_quarters": 0, "enabled": True, "condition": 1.0},
    {"definition_id": "fixture_co2_scrubber", "cell": [11, 3], "rotation_quarters": 0, "enabled": True, "condition": 1.0},
]

STORAGE = {"alloy": 50, "electronics": 50, "food_kcal": 200000.0, "hydrogen_kg": 10.0,
           "oxygen_kg": 200.0, "potable_water_kg": 1000.0, "raw_water_kg": 100.0, "wastewater_kg": 50.0}
INVENTORY = {"alloy": 6, "co2_kg": 0.5, "electronics": 2, "food_kcal": 100000.0, "hydrogen_kg": 0.0,
             "oxygen_kg": 120.0, "potable_water_kg": 500.0, "raw_water_kg": 0.0, "wastewater_kg": 1.0}

BUILDING_PATHS = [RES_ROOT + f"definitions/buildings/{k}.json" for k in sorted(BUILDINGS)]


def scenario(id_, *, battery_kwh=18.0, sites=None, desc="", storage=None, inventory=None):
    blds = []
    for b in HABITAT_BUILDINGS:
        b = dict(b)
        if "battery_stored_kwh" in b:
            b["battery_stored_kwh"] = battery_kwh
        blds.append(b)
    return {
        "schema_version": 1,
        "id": id_,
        "description": desc,
        "metadata": SYN,
        "resource_registry_path": RES_ROOT + "definitions/resources.json",
        "building_definition_paths": BUILDING_PATHS,
        "crew_definition_path": RES_ROOT + "definitions/crew/fixture_crew.json",
        "task_template_path": RES_ROOT + "definitions/crew/fixture_task_templates.json",
        "map_path": RES_ROOT + "definitions/map/fixture_flat_16.json",
        "starting_storage_capacity": dict(STORAGE, **(storage or {})),
        "starting_inventory": dict(INVENTORY, **(inventory or {})),
        "starting_buildings": blds,
        "site_definitions": {"fixture_cargo_cache": {"display_name": "Fixture Cargo Cache", "metadata": SYN}},
        "sites": sites or [],
        "scheduled_events": [],
        "technology_unlocked_ids": [],
    }


SALVAGE_SITES = [{"id": "site_cargo_a", "definition_id": "fixture_cargo_cache", "cell": [12, 8],
                  "cargo": {"alloy": 4, "electronics": 3}}]

SCENARIOS = {
    "fixture_habitat": scenario("fixture_habitat",
                                desc="Functioning habitat: generator, battery, electrolyzer, water recycler, CO2 scrubber."),
    "fixture_power_shortage": scenario("fixture_power_shortage", battery_kwh=0.002,
                                       desc="Habitat with a nearly empty battery; scripts disable the generator."),
    "fixture_salvage": scenario("fixture_salvage", sites=SALVAGE_SITES,
                                desc="Habitat plus one salvage site 10 m east of the airlock."),
    "fixture_salvage_full_store": scenario(
        "fixture_salvage_full_store", sites=SALVAGE_SITES, storage={"alloy": 8},
        desc="Salvage scenario with alloy storage capped at 8 so returned cargo must use the return cache."),
    "fixture_storage_limits": scenario(
        "fixture_storage_limits", storage={"wastewater_kg": 1.03, "hydrogen_kg": 0.0025},
        desc="Habitat with nearly full wastewater and hydrogen storage: metabolic overflow and output_full throttling."),
}

# Init configs: name -> (scenario id, crew count, campaign id override)
INIT_CONFIGS = {
    "habitat_5crew": ("fixture_habitat", 5, None),
    "habitat_6crew": ("fixture_habitat", 6, None),
    "habitat_6crew_alt": ("fixture_habitat", 6, "fixture_habitat_6crew_alt"),
    "habitat_9crew": ("fixture_habitat", 9, None),
    "power_shortage_6crew": ("fixture_power_shortage", 6, None),
    "salvage_6crew": ("fixture_salvage", 6, None),
    "salvage_full_store_6crew": ("fixture_salvage_full_store", 6, None),
    "storage_limits_6crew": ("fixture_storage_limits", 6, None),
}
