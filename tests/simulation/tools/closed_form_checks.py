#!/usr/bin/env python3
"""Independent closed-form checks of the generated fixtures.

This module deliberately does not import reference_model.py: it re-derives key
totals from the synthetic rates by hand-written formulas, so a mistake in the
reference model cannot silently define the expected values.

Usage: python tests/simulation/tools/closed_form_checks.py [fixtures_dir]
(generate_fixtures.py also runs these checks on every generation and --check.)
"""
import hashlib
import json
import os
import sys

TOL_ABS, TOL_REL = 1e-8, 1e-9
DEFAULT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures"))

# Synthetic per-tick rates restated here on purpose (see fixtures/README.md section 6).
O2_PER_CREW, WATER_PER_CREW, FOOD_PER_CREW = 0.001, 0.002, 1.0
CO2_PER_CREW, WASTE_PER_CREW = 0.001, 0.002
ELECTROLYZER = {"water": 0.009, "o2": 0.008, "h2": 0.001}
RECYCLER, SCRUBBER = 0.012, 0.006
CHARGE_PER_TICK = 1.0 / 3600 * 0.9          # 1.0 kW surplus, 0.9 charge efficiency
DRAIN_PER_TICK = 2.0 / 3600 / 0.9           # 2.0 kW load, 0.9 discharge efficiency
SUIT_O2 = 0.002


def close(a, b):
    return abs(a - b) <= TOL_ABS + TOL_REL * abs(b)


class Checker:
    def __init__(self, root):
        self.root = root
        self.problems = []

    def load(self, rel):
        with open(os.path.join(self.root, *rel.split("/")), encoding="utf-8") as f:
            return json.load(f)

    def eq(self, label, actual, expected):
        ok = close(actual, expected) if isinstance(expected, float) else actual == expected
        if not ok:
            self.problems.append(f"{label}: got {actual!r}, expected {expected!r}")

    def amount(self, snap, rid):
        return self.load(f"snapshots/{snap}.json")["resources"][rid]["amount"]

    def step_expect(self, script, tick):
        for st in self.load(f"scripts/{script}.json")["steps"]:
            if st["op"] in ("step", "advance") and st["expect"]["tick_index"] == tick:
                return st["expect"]
        self.problems.append(f"{script}: no step expectation at tick {tick}")
        return None

    def manifests(self):
        count = 0
        for sub in ("init", "saves"):
            base = os.path.join(self.root, sub)
            for name in sorted(os.listdir(base)):
                if not name.endswith(".json"):
                    continue
                man = self.load(f"{sub}/{name}")["definition_manifest"]
                for path, digest in man.items():
                    if digest == "0" * 64:
                        continue                      # deliberately corrupted invalid-save fixture
                    rel = path.replace("res://tests/simulation/fixtures/", "")
                    with open(os.path.join(self.root, *rel.split("/")), "rb") as f:
                        if hashlib.sha256(f.read()).hexdigest() != digest:
                            self.problems.append(f"{sub}/{name}: stale hash for {path}")
                    count += 1
        if count == 0:
            self.problems.append("no manifest entries checked")

    def habitat(self):
        n = 600
        # 6 crew: everything balanced except O2, potable, food, H2, energy.
        snap = "habitat_6crew_tick600"
        self.eq("6crew O2", self.amount(snap, "oxygen_kg"), 120 + (ELECTROLYZER["o2"] - 6 * O2_PER_CREW) * n)
        self.eq("6crew potable", self.amount(snap, "potable_water_kg"),
                500 + (RECYCLER - ELECTROLYZER["water"] - 6 * WATER_PER_CREW) * n)
        self.eq("6crew food", self.amount(snap, "food_kcal"), 100000 - 6 * FOOD_PER_CREW * n)
        self.eq("6crew H2", self.amount(snap, "hydrogen_kg"), ELECTROLYZER["h2"] * n)
        self.eq("6crew CO2", self.amount(snap, "co2_kg"), 0.5)
        self.eq("6crew energy", self.amount(snap, "energy_kwh"), 18 + CHARGE_PER_TICK * n)
        # 9 crew: CO2 accumulates (never capped), wastewater accumulates in storage.
        snap = "habitat_9crew_tick600"
        self.eq("9crew O2", self.amount(snap, "oxygen_kg"), 120 + (ELECTROLYZER["o2"] - 9 * O2_PER_CREW) * n)
        self.eq("9crew CO2", self.amount(snap, "co2_kg"), 0.5 + (9 * CO2_PER_CREW - SCRUBBER) * n)
        self.eq("9crew wastewater", self.amount(snap, "wastewater_kg"), 1.0 + (9 * WASTE_PER_CREW - RECYCLER) * n)
        self.eq("9crew CO2 capacity", self.load(f"snapshots/{snap}.json")["resources"]["co2_kg"]["capacity"], None)
        first = [a for a in self.load(f"snapshots/{snap}.json")["alerts"] if a["id"] == "co2_high"]
        # 0.5 + 0.003 * (k + 1) >= 1.0 first holds for interval k = 166
        self.eq("9crew co2_high first_tick", first[0]["first_tick"] if first else None, 166)
        # 5 crew: wastewater 1.0 - 0.002 k drops below 0.012 at interval 495, then recycler input-limited.
        snap = "habitat_5crew_tick600"
        self.eq("5crew potable", self.amount(snap, "potable_water_kg"),
                500 - (ELECTROLYZER["water"] + 5 * WATER_PER_CREW - RECYCLER) * 495
                - (ELECTROLYZER["water"] + 5 * WATER_PER_CREW - 5 * WASTE_PER_CREW) * 105)

    def power(self):
        sc = "power_loss_and_restore"
        e4 = self.step_expect(sc, 4)
        e8 = self.step_expect(sc, 8)
        e20 = self.step_expect(sc, 20)
        charged = 0.002 + 4 * CHARGE_PER_TICK
        if e4:
            self.eq("battery after charging", e4["resource_amounts"]["energy_kwh"], charged)
        if e8:
            self.eq("battery after 4 full drains", e8["resource_amounts"]["energy_kwh"], charged - 4 * DRAIN_PER_TICK)
        snap = self.load("snapshots/power_partial_tick9.json")
        deliverable = (charged - 4 * DRAIN_PER_TICK) * 0.9 * 3600
        self.eq("tick 9 served kW", snap["power"]["served_kw"], deliverable)
        self.eq("tick 9 recycler kW", snap["buildings"]["building_000004"]["power_served_kw"], deliverable - 1.5)
        if e20:
            self.eq("CO2 after 11 unpowered ticks", e20["resource_amounts"]["co2_kg"], 0.5 + 11 * 6 * CO2_PER_CREW)

    def eva(self):
        snap = self.load("snapshots/eva_returned_tick40.json")
        # load 0.24, 4 base crew for 40 ticks, 2 suits return 0.12 - 40 * 0.002 each
        self.eq("EVA base O2", snap["resources"]["oxygen_kg"]["amount"],
                120 - 0.24 + 40 * (ELECTROLYZER["o2"] - 4 * O2_PER_CREW) + 2 * (0.12 - 40 * SUIT_O2))
        self.eq("EVA alloy", snap["resources"]["alloy"]["amount"], 10)
        self.eq("EVA electronics", snap["resources"]["electronics"]["amount"], 4)
        self.eq("EVA site leftover", snap["sites"]["site_cargo_a"]["remaining_cargo"], {"alloy": 0, "electronics": 1})
        self.eq("EVA crew back at base", [c["location_kind"] for c in snap["crew"].values()], ["base"] * 6)

    def stranded(self):
        snap = self.load("snapshots/eva_stranded_tick16.json")
        e = snap["expeditions"]["expedition_000001"]
        self.eq("stranded status", e["status"], "stranded")
        self.eq("stranded work frozen", e["work_completed_s"], 5.0)
        self.eq("stranded margin", e["return_margin_s"], None)
        self.eq("stranded alert", [a["id"] for a in snap["alerts"] if a["code"] == "expedition_stranded"],
                ["expedition_stranded:expedition_000001"])
        snap = self.load("snapshots/eva_recovered_tick30.json")
        self.eq("recovered O2", snap["resources"]["oxygen_kg"]["amount"],
                120 - 0.24 + 30 * (ELECTROLYZER["o2"] - 4 * O2_PER_CREW) + 2 * (0.12 - 30 * SUIT_O2))
        self.eq("recovered task", snap["tasks"]["task_000001"]["status"], "cancelled")
        self.eq("recovered expedition", snap["expeditions"]["expedition_000001"]["status"], "completed")

    def storage(self):
        s3 = self.load("snapshots/storage_limits_tick3.json")
        s6 = self.load("snapshots/storage_limits_tick6.json")
        self.eq("wastewater capped at storage", s3["resources"]["wastewater_kg"]["amount"], 1.03)
        self.eq("wastewater stays capped", s6["resources"]["wastewater_kg"]["amount"], 1.03)
        self.eq("hydrogen capped", s6["resources"]["hydrogen_kg"]["amount"], 0.0025)
        self.eq("electrolyzer throttled at tick 3", s3["buildings"]["building_000003"]["operating_fraction"], 0.5)
        self.eq("electrolyzer code", s6["buildings"]["building_000003"]["blocking_codes"], ["output_full:hydrogen_kg"])
        alert = [a for a in s3["alerts"] if a["id"] == "storage_full:wastewater_kg"]
        self.eq("storage_full first_tick", alert[0]["first_tick"] if alert else None, 2)
        # O2: 3 ticks of electrolysis (1, 1, 0.5) then none; 6 crew consume throughout.
        self.eq("storage O2", s6["resources"]["oxygen_kg"]["amount"],
                120 + ELECTROLYZER["o2"] * 2.5 - 6 * 6 * O2_PER_CREW)
        # reference_external_flows covers the last public call only.
        e3 = self.step_expect("storage_limits", 3)
        e6 = self.step_expect("storage_limits", 6)
        key = "external/capacity_overflow_loss/wastewater_kg"
        if e3:   # 1.024 + 0.012 exceeds 1.03 by 0.006
            self.eq("wastewater lost in interval 2", e3["reference_external_flows"].get(key, 0.0),
                    1.0 + 3 * 6 * WASTE_PER_CREW - 1.03)
        if e6:
            self.eq("wastewater lost in interval 5", e6["reference_external_flows"].get(key, 0.0), 6 * WASTE_PER_CREW)

    def full_store(self):
        s40 = self.load("saves/eva_full_store_cache_tick40.json")
        self.eq("cache holds excess alloy", s40["subsystems"]["crew_tasks"]["state"]["return_caches"],
                {"expedition_000001": {"alloy": 2}})
        self.eq("alloy at cap", s40["core"]["resources"]["alloy"]["amount"], 8)
        s41 = self.load("saves/eva_full_store_drained_tick41.json")
        self.eq("cache drained", s41["subsystems"]["crew_tasks"]["state"]["return_caches"], {})
        self.eq("alloy refilled after spending 2", s41["core"]["resources"]["alloy"]["amount"], 8)
        markers = sorted(s41["core"]["committed_effects"])
        self.eq("no persisted drain marker", [m for m in markers if "return_cache" in m], [])

    def equal_revision(self):
        a = self.load("snapshots/habitat_6crew_tick5.json")
        b = self.load("snapshots/alt_campaign_rev5.json")
        self.eq("equal revisions", a["revision"], b["revision"])
        self.eq("different campaigns", a["campaign_id"] != b["campaign_id"], True)
        self.eq("different content", a["buildings"]["building_000004"]["enabled"]
                != b["buildings"]["building_000004"]["enabled"], True)

    def versions(self):
        for sub in ("snapshots", "saves", "scripts"):
            for name in sorted(os.listdir(os.path.join(self.root, sub))):
                if not name.endswith(".json"):
                    continue
                d = self.load(f"{sub}/{name}")
                if sub == "snapshots":
                    self.eq(f"{name} versions", (d["contract_version"], d["snapshot_version"]), ("2.0.0", 2))
                elif sub == "saves":
                    self.eq(f"{name} versions", (d["contract_version"], d["save_version"],
                                                 d["subsystems"]["crew_tasks"]["schema_version"]), ("2.0.0", 2, 1))
                else:
                    for st in d["steps"]:
                        if st["op"] == "submit" and st["command"]["command_id"] != "fixture:000098":
                            self.eq(f"{name} command version", st["command"]["contract_version"], "2.0.0")


def run(root=DEFAULT_DIR):
    c = Checker(root)
    for check in (c.manifests, c.habitat, c.power, c.eva, c.stranded, c.storage, c.full_store,
                  c.equal_revision, c.versions):
        try:
            check()
        except (KeyError, FileNotFoundError, IndexError, TypeError) as exc:
            c.problems.append(f"{check.__name__}: {type(exc).__name__}: {exc}")
    return c.problems


if __name__ == "__main__":
    probs = run(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR)
    if probs:
        print("\n".join(probs))
        sys.exit(1)
    print("closed-form checks passed")
