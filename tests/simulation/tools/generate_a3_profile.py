"""Normalize documented A3 reference inputs and size the three game modules.

No network or third-party libraries. Original synthetic oracle fixtures untouched.
After regeneration, refresh the authored scenario manifest with the world tool.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def encode(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def outputs():
    source = read("data/science/a3_reference_inputs.json")
    day = source["earth_day_s"]
    if day != 86400 or source["sol_s"] <= day:
        raise ValueError("Reference Earth-day and sol time bases were changed without review")
    rates = {k: v / day for k, v in source["per_crew_earth_day"].items()}
    demand = {k: rates[k] for k in ("oxygen_kg", "potable_water_kg", "food_kcal")}
    a = source["atmosphere"]
    threshold = a["instantaneous_warning_pa"] * a["volume_m3"] * a["co2_molar_mass_kg_mol"] / (a["molar_gas_constant_j_mol_k"] * a["temperature_k"])
    science = {
        "schema_version": 1, "id": "a3_reference_science",
        "metadata": {"status": "source_backed_reference_model", "science_record_ids": source["science_record_ids"],
                     "warning": "NASA reference crew; documented game equipment/atmosphere assumptions. Instantaneous CO2 alert, not one-hour compliance. No reference EVA model."},
        "time": {"tick_s": 1.0, "sol_s": source["sol_s"]},
        "crew_metabolism": {"time_basis": "per_simulated_second", "base_activity_rates_per_s": {"idle": demand, "working": demand},
                            "base_outputs_per_s": {"co2_kg": rates["co2_kg"], "wastewater_kg": rates["wastewater_kg"]},
                            "eva_suit_rates_per_s": {"oxygen_kg": 0.0, "battery_kwh": 0.0}, "eva_draws_base_water_and_food": False, "eva_supported": False},
        "eva_policy": {"reserve_fraction": 0.25},
        "losses": {"oxygen_leak_kg_per_s": 0.0},
        "alerts": {"low_oxygen_forecast_s": 3600.0, "co2_high_kg": threshold, "battery_low_fraction": 0.1, "expedition_low_margin_s": 10.0},
        "atmosphere": a,
    }
    result = {"data/science/a3_reference_science.json": encode(science)}
    design = source["equipment_design"]
    size = design["crew_count"] * design["throughput_margin"]
    oxygen = rates["oxygen_kg"] * size
    waste = rates["wastewater_kg"] * size
    processes = {
        "water_electrolyzer_mk1": ({"potable_water_kg": oxygen * 9 / 8}, {"oxygen_kg": oxygen, "hydrogen_kg": oxygen / 8}),
        "water_recycler_mk1": ({"wastewater_kg": waste}, {"potable_water_kg": waste * design["recycler_recovery"]}),
        "co2_scrubber_mk1": ({"co2_kg": rates["co2_kg"] * size}, {}),
    }
    for id, (inputs, outputs_map) in processes.items():
        path = f"data/buildings/{id}.json"
        definition = read(path)
        definition["process"] = {"inputs_per_s": inputs, "outputs_per_s": outputs_map}
        definition["metadata"]["balance_status"] = "documented_game_abstraction"
        definition["metadata"]["balance_note"] = "A3 six-reference-crew throughput sizing with 20% margin; power/cost/storage remain game abstractions. See SCIENCE.md A3-DESIGN-MARGIN, A3-ELECTROLYSIS and A3-RECOVERY."
        result[path] = encode(definition)
    return result


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
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    if stale:
        raise SystemExit("Stale A3 profile/throughput: " + ", ".join(stale))
    print("A3_PROFILE_PASS" if args.check else "Generated A3 reference profile and documented game throughput")


if __name__ == "__main__":
    main()
