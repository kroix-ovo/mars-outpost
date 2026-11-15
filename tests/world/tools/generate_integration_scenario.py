"""Build synthetic authored-map inputs, separate from the reference oracle.

Run from any directory with --check to verify manifest freshness. The A3 profile
combines reference crew physiology with documented game equipment assumptions.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIX = "tests/world/fixtures/"
SIM = "tests/simulation/fixtures/"


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def outputs():
    demo = read(FIX + "landing_plain_demo_snapshot.json")
    scenario = read(SIM + "scenarios/fixture_salvage.json")
    definitions = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "data/buildings").glob("*.json"))
    scenario.update(
        id="synthetic_landing_plain_integration",
        description="Authored integration prototype with A3 reference crew demand and documented game equipment sizing.",
        metadata={"status": "synthetic_test_fixture", "warning": "Reference physiology plus game equipment and labor assumptions, not a flight-certified habitat. Construction and repairs are playable; EVA is disabled until suit science is configured. Agriculture and campaign saves are pending."},
        crew_definition_path="res://data/crew/outpost_roster.json",
        task_template_path="res://data/crew/task_templates.json",
        building_definition_paths=["res://" + p for p in definitions],
        map_path="res://data/maps/landing_plain.json",
        starting_buildings=[],
        sites=[],
    )
    scenario["starting_storage_capacity"]["potable_water_kg"] = 1100.0
    for rid, record in demo["resources"].items():
        if rid != "energy_kwh":
            scenario["starting_inventory"][rid] = record["amount"]
    for building in demo["buildings"].values():
        if building["lifecycle"] != "commissioned":
            continue
        item = {k: building[k] for k in ("definition_id", "cell", "rotation_quarters", "enabled", "condition")}
        if building["definition_id"] == "battery_bank_mk1":
            item["battery_stored_kwh"] = demo["power"]["battery_stored_kwh"]
        scenario["starting_buildings"].append(item)
    for site in demo["sites"].values():
        scenario["sites"].append({"id": site["id"], "definition_id": site["definition_id"], "cell": site["cell"], "cargo": site["remaining_cargo"]})
    scenario["site_definitions"] = {s["definition_id"]: {"metadata": {"status": "synthetic_test_fixture"}} for s in scenario["sites"]}
    scenario_path = FIX + "landing_plain_scenario.json"
    scenario_bytes = encoded(scenario)
    config = read(SIM + "init/salvage_6crew.json")
    config.update(campaign_id="reference_landing_plain_life_support", map_id="landing_plain", map_revision=1,
                  scenario_path="res://" + scenario_path, science_config_path="res://data/science/a3_reference_science.json",
                  initial_crew_definition_ids=[d["id"] for d in read("data/crew/outpost_roster.json")["definitions"][:6]])
    paths = definitions + ["data/maps/landing_plain.json", scenario["resource_registry_path"][6:],
                           scenario["crew_definition_path"][6:], scenario["task_template_path"][6:],
                           config["science_config_path"][6:], "data/science/a3_reference_inputs.json"]
    config["definition_manifest"] = {"res://" + p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted(paths)}
    config["definition_manifest"]["res://" + scenario_path] = hashlib.sha256(scenario_bytes).hexdigest()
    return {scenario_path: scenario_bytes, FIX + "landing_plain_init.json": encoded(config)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for relative, data in outputs().items():
        target = ROOT / relative
        if args.check:
            if not target.exists() or target.read_bytes() != data:
                stale.append(relative)
        else:
            target.write_bytes(data)
    if stale:
        raise SystemExit("Stale authored integration inputs: " + ", ".join(stale))
    print("AUTHORED_FIXTURES_PASS" if args.check else "Generated synthetic authored-map scenario/config")


if __name__ == "__main__":
    main()
