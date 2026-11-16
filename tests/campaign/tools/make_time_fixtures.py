"""Generate the package 2 time fixtures. Run from the repository root:

    python tests/campaign/tools/make_time_fixtures.py [--check]

Every value is synthetic test data derived from the Task 01 fixture habitat. The
scenarios only change starting stocks and capacities; definitions are reused by hash.
"""
import copy
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LEGACY = ROOT / "tests/simulation/fixtures"
OUT = ROOT / "tests/campaign/fixtures"
PROFILE = "res://data/campaign/time_profile.json"

# name: (description, inventory overrides, capacity overrides, battery kWh)
SCENARIOS = {
    "time_sustainable": (
        "Declared sustainable test conditions: stocks and capacities large enough for 180 mission days "
        "with no food production. This is a test boundary, not a claim that the habitat is self-sufficient.",
        {"food_kcal": 2.0e8, "potable_water_kg": 5.0e5, "oxygen_kg": 120.0},
        {"food_kcal": 4.0e8, "potable_water_kg": 1.0e6, "oxygen_kg": 1.0e6, "hydrogen_kg": 1.0e6}, 18.0),
    "time_battery_near_full": (
        "Sustainable stocks with a battery 0.1 kWh below capacity, so charge saturation happens within minutes.",
        {"food_kcal": 2.0e8, "potable_water_kg": 5.0e5},
        {"food_kcal": 4.0e8, "potable_water_kg": 1.0e6, "oxygen_kg": 1.0e6, "hydrogen_kg": 1.0e6}, 39.9),
    "time_food_exhaustion": (
        "Food reserve that six crew exhaust after 500 simulated seconds; exercises reserve exhaustion and the danger stop.",
        {"food_kcal": 3000.0, "potable_water_kg": 5.0e5},
        {"potable_water_kg": 1.0e6, "oxygen_kg": 1.0e6, "hydrogen_kg": 1.0e6}, 18.0),
}


def dump(data):
    return json.dumps(data, indent=2) + "\n"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build():
    files = {}
    habitat = json.loads((LEGACY / "scenarios/fixture_habitat.json").read_text())
    init = json.loads((LEGACY / "init/habitat_6crew.json").read_text())
    for name, (description, inventory, capacity, battery) in SCENARIOS.items():
        scenario = copy.deepcopy(habitat)
        scenario["id"] = "fixture_" + name
        scenario["description"] = description
        scenario["starting_inventory"].update(inventory)
        scenario["starting_storage_capacity"].update(capacity)
        for building in scenario["starting_buildings"]:
            if "battery_stored_kwh" in building:
                building["battery_stored_kwh"] = battery
        files[OUT / "scenarios" / f"fixture_{name}.json"] = dump(scenario)
    return files, init


def main():
    check = "--check" in sys.argv
    files, init = build()
    stale = []
    for path, text in files.items():
        if check:
            if not path.exists() or path.read_text() != text:
                stale.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, newline="\n")
    for name in SCENARIOS:
        config = copy.deepcopy(init)
        legacy_scenario = config["scenario_path"]
        scenario_res = f"res://tests/campaign/fixtures/scenarios/fixture_{name}.json"
        config["campaign_id"] = "fixture_campaign_" + name
        config["scenario_path"] = scenario_res
        config["campaign_profile_path"] = PROFILE
        manifest = {key: value for key, value in config["definition_manifest"].items() if key != legacy_scenario}
        manifest[scenario_res] = sha(OUT / "scenarios" / f"fixture_{name}.json") if not stale else ""
        manifest[PROFILE] = sha(ROOT / "data/campaign/time_profile.json")
        config["definition_manifest"] = dict(sorted(manifest.items()))
        path = OUT / "init" / f"{name}_6crew.json"
        text = dump(config)
        if check:
            if not path.exists() or path.read_text() != text:
                stale.append(path)
        else:
            path.write_text(text, newline="\n")
    if stale:
        raise SystemExit("STALE " + ", ".join(str(item) for item in stale))
    print("TIME_FIXTURES_OK files=%d" % (len(files) + len(SCENARIOS)))


if __name__ == "__main__":
    main()
