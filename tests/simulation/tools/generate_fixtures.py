#!/usr/bin/env python3
"""Generate the synthetic Task 01 fixtures for contract 2.0.0.

Usage (from the repository root, Python 3.10+ standard library only):

    python tests/simulation/tools/generate_fixtures.py          # rewrite tests/simulation/fixtures/*.json
    python tests/simulation/tools/generate_fixtures.py --check  # fail if committed fixtures are stale

Output is deterministic: identical sources always produce byte-identical files.
--check regenerates into a temporary directory, compares every JSON file
byte-for-byte (missing, extra, or changed files fail), and then runs the
independent closed-form checks in closed_form_checks.py against the result.
The generator never writes or deletes non-JSON files (README.md is hand-written).
"""
import argparse
import copy
import hashlib
import json
import os
import shutil
import sys
import tempfile

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
FIXTURES_DIR = os.path.normpath(os.path.join(TOOLS_DIR, "..", "fixtures"))
sys.path.insert(0, TOOLS_DIR)

import closed_form_checks  # noqa: E402
import fixture_content as C  # noqa: E402
from reference_model import CONTRACT_VERSION, ReferenceModel  # noqa: E402

RES = C.RES_ROOT


class Writer:
    def __init__(self, root):
        self.root = root
        self.written = set()

    def write(self, rel, obj):
        path = os.path.join(self.root, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        assert rel not in self.written, f"written twice: {rel}"
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(obj, indent=2) + "\n")
        self.written.add(rel)
        return RES + rel

    def sha(self, rel):
        with open(os.path.join(self.root, *rel.split("/")), "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()


def env(cid, typ, payload):
    return {"contract_version": CONTRACT_VERSION, "command_id": cid, "type": typ, "payload": payload}


class Script:
    """Records a fixture script while driving the reference model."""

    def __init__(self, gen, sid, desc, cfg_name, depends):
        self.g = gen
        self.cfg_name = cfg_name
        self.m = gen.model(cfg_name)
        self.doc = {"schema_version": 2, "id": sid, "contract_version": CONTRACT_VERSION, "description": desc,
                    "metadata": {"status": "synthetic_test_fixture"}, "depends_on": depends,
                    "init_config": RES + f"init/{cfg_name}.json",
                    "world_service": "stub_world_fixture_flat_16", "crew_adapter": "stub_crew_policy_v2",
                    "steps": []}

    def _add(self, st, note):
        if note:
            st["note"] = note
        self.doc["steps"].append(st)

    def submit(self, cmd, note=None):
        self._add({"op": "submit", "command": cmd, "expect_response": self.m.submit(cmd)}, note)

    def _expect(self, snap):
        m = self.m
        e = {"tick_index": m.s["tick_index"], "revision": m.s["revision"],
             "state_changed_emissions": 1 if m.state_changed else 0,
             "command_resolved": m.resolved, "flushes": m.flushes,
             "resource_amounts": {rid: m.base_amount(rid) for rid in sorted(m.registry)},
             "reference_external_flows": dict(sorted(m.call_flows.items()))}
        if snap:
            e["snapshot"] = self.g.w.write(f"snapshots/{snap}.json", m.snapshot())
        return copy.deepcopy(e)

    def step(self, n=1, note=None, snap=None):
        for _ in range(n):
            self.m.step()
        st = {"op": "step"}
        if n > 1:
            st["repeat"] = n
        st["expect"] = self._expect(snap)
        self._add(st, note)

    def advance(self, real, note=None, snap=None, repeat=1):
        for _ in range(repeat):
            self.m.advance(real)
        st = {"op": "advance", "real_delta_s": real}
        if repeat > 1:
            st["repeat"] = repeat
        st["expect"] = self._expect(snap)
        self._add(st, note)

    def snapshot(self, name, note=None):
        self._add({"op": "get_snapshot", "expect_snapshot": self.g.w.write(f"snapshots/{name}.json", self.m.snapshot())},
                  note)

    def snapshot_ref(self, name, note=None):
        self._add({"op": "get_snapshot", "expect_snapshot": RES + f"snapshots/{name}.json"}, note)

    def save(self, name, note=None):
        rec = self.m.export_save()
        self._add({"op": "export_save", "expect_save": self.g.w.write(f"saves/{name}.json", rec)}, note)
        return rec

    def import_save(self, rec, path, new_instance, snap_ref, note=None):
        if new_instance:
            self.m = self.g.model(self.cfg_name)
        self.m._begin()
        res = self.m.import_save(rec)
        op = "import_save_into_new_instance" if new_instance else "import_save"
        self._add({"op": op, "save": path,
                   "expect": dict(res, state_changed_emissions=1 if res["ok"] else 0, flushes=[]),
                   "expect_snapshot": RES + f"snapshots/{snap_ref}.json"}, note)
        return res

    def inject_blocked(self, cells, note=None):
        self.m.world_injected_blocked = {tuple(c) for c in cells}
        self._add({"op": "stub_world_set_injected_blocked_cells", "cells": cells}, note)

    def finish(self):
        self.g.w.write(f"scripts/{self.doc['id']}.json", self.doc)


class Generator:
    def __init__(self, root):
        self.w = Writer(root)
        self.cfgs = {}

    def content_for(self, scenario_id):
        sc = C.SCENARIOS[scenario_id]
        return {"scenario": sc, "science": C.SCIENCE, "buildings": C.BUILDINGS, "crew": C.crew_defs(),
                "templates": C.TASK_TEMPLATES, "map": C.MAP, "registry": C.RESOURCES}

    def model(self, cfg_name):
        cfg = self.cfgs[cfg_name]
        sid = cfg["scenario_path"].rsplit("/", 1)[1][:-len(".json")]
        return ReferenceModel(copy.deepcopy(cfg), copy.deepcopy(self.content_for(sid)))

    # ------------------------------------------------------------------ content
    def write_content(self):
        w = self.w
        shared = {
            "definitions/resources.json": C.RESOURCES,
            "definitions/science/fixture_science_synthetic.json": C.SCIENCE,
            "definitions/map/fixture_flat_16.json": C.MAP,
            "definitions/crew/fixture_crew.json": C.crew_defs(),
            "definitions/crew/fixture_task_templates.json": C.TASK_TEMPLATES,
        }
        for k, v in C.BUILDINGS.items():
            shared[f"definitions/buildings/{k}.json"] = v
        for rel, obj in shared.items():
            w.write(rel, obj)
        for k, v in C.SCENARIOS.items():
            w.write(f"scenarios/{k}.json", v)
        crew_ids = [d["id"] for d in C.crew_defs()["definitions"]]
        for name, (sid, n, campaign) in C.INIT_CONFIGS.items():
            rels = sorted(list(shared) + [f"scenarios/{sid}.json"])
            cfg = {
                "campaign_id": campaign or f"fixture_{name}",
                "seed": "42",
                "initial_crew_definition_ids": crew_ids[:n],
                "map_id": C.MAP["id"], "map_revision": C.MAP["revision"],
                "scenario_path": RES + f"scenarios/{sid}.json",
                "science_config_path": RES + "definitions/science/fixture_science_synthetic.json",
                "definition_manifest": {RES + r: w.sha(r) for r in rels},
            }
            w.write(f"init/{name}.json", cfg)
            self.cfgs[name] = cfg
            w.write(f"snapshots/{name}_tick0.json", self.model(name).snapshot())

    # ------------------------------------------------------------------ scripts
    def habitat_balance(self, name):
        s = Script(self, f"{name}_balance", f"Run {name} for 600 ticks with no commands.", name,
                   ["synthetic metabolism and process rates", "power priority dispatch", "accumulator CO2"])
        s.snapshot_ref(f"{name}_tick0", "Before the first tick: rates, power fields, and alerts are zero/empty.")
        s.step(1, snap=f"{name}_tick1")
        s.step(9)
        s.step(90, snap=f"{name}_tick100")
        s.step(500, snap=f"{name}_tick600")
        s.finish()

    def placement_and_save(self):
        s = Script(self, "placement_and_save",
                   "Placement, competing and unaffordable placements, dedupe, labor, mid-job save with a pending "
                   "command and fractional accumulator, restore into a new instance, commissioning.",
                   "habitat_6crew", ["construction template via apply_command", "Task 01 applies labor once",
                                     "persisted completion markers", "save schema 2"])
        place = env("fixture:000001", "place_building",
                    {"definition_id": "fixture_electrolyzer", "cell": [7, 5], "rotation_quarters": 0})
        s.submit(place)
        s.submit(env("fixture:000002", "place_building",
                     {"definition_id": "fixture_electrolyzer", "cell": [7, 5], "rotation_quarters": 0}),
                 "Same cell: accepted at submit, placement_blocked at resolution.")
        s.submit(env("fixture:000003", "place_building",
                     {"definition_id": "fixture_storage_module", "cell": [13, 12], "rotation_quarters": 0}),
                 "Costs 10 alloy; only 4 remain after fixture:000001 resolves.")
        s.submit(place, "Retry while queued: duplicate=true, status=queued, not enqueued again.")
        s.submit(env("fixture:000001", "place_building",
                     {"definition_id": "fixture_electrolyzer", "cell": [8, 5], "rotation_quarters": 0}),
                 "Same id, different content: command_id_conflict.")
        s.submit({"contract_version": CONTRACT_VERSION, "command_id": "fixture:000099", "type": "place_building",
                  "payload": {"definition_id": "fixture_electrolyzer", "cell": [7, 5]}},
                 "Missing rotation_quarters: invalid_schema; the id is not claimed.")
        s.submit(dict(place, contract_version="1.0.0", command_id="fixture:000098"),
                 "Old contract version: unsupported_contract.")
        s.step(1, "One boundary flush: three command_result events in receive order; then interval 0.")
        s.submit(place, "Retry after resolution: cached result; no second spend.")
        s.submit(env("fixture:000004", "assign_task",
                     {"task_id": "task_000001", "crew_ids": ["crew_000003"], "priority": 50}))
        s.step(1, "command_result entity_ids include the crew_ids element.")
        s.step(4, "Work 5.0 / 10.0.")
        s.advance(0.4, "Empty boundary; accumulator 0.4; no tick; no state change.")
        s.submit(env("fixture:000005", "set_building_enabled", {"building_id": "building_000004", "enabled": False}),
                 "Left pending in the save.")
        s.snapshot("placement_mid_job_tick6")
        rec = s.save("placement_mid_job_tick6", "Boundary save: pending command, accumulator 0.4, task 5/10.")
        uninterrupted = copy.deepcopy(s.m)
        s.import_save(rec, RES + "saves/placement_mid_job_tick6.json", True, "placement_mid_job_tick6",
                      "Fresh instance from habitat_6crew; later expectations hold for both instances.")
        s.advance(0.6, "Boundary resolves fixture:000005; accumulator reaches 1.0; one tick.")
        s.advance(1.0, repeat=3)
        s.advance(1.0, "Work 10/10: commissioned at end of interval 10.", snap="placement_commissioned_tick11")
        s.advance(1.0, "crew_000003 released at intent; second electrolyzer produces.", snap="placement_after_tick12")
        s.submit(place, "Retry after load: cached result.")
        # Save continuity: the uninterrupted instance must reach the identical state.
        for real in (0.6, 1.0, 1.0, 1.0, 1.0, 1.0):
            uninterrupted.advance(real)
        uninterrupted.submit(place)
        assert json.dumps([uninterrupted.snapshot(), uninterrupted.export_save()], sort_keys=True) == \
            json.dumps([s.m.snapshot(), s.m.export_save()], sort_keys=True), "save/load continuity broken"
        s.finish()

    def power_loss(self):
        s = Script(self, "power_loss_and_restore",
                   "Charge from surplus, disable the generator, drain stored energy by power priority, recover.",
                   "power_shortage_6crew", ["battery dispatch", "accumulator CO2", "blocking/alert vocabulary"])
        s.step(4, "Battery 0.002 -> 0.003 kWh from 1.0 kW surplus.", snap="power_charged_tick4")
        s.submit(env("fixture:000001", "set_building_enabled", {"building_id": "building_000001", "enabled": False}))
        s.step(1, "Battery serves all 2.0 kW.")
        s.step(3)
        s.step(1, "1.72 kW left: scrubber and electrolyzer full, recycler partial.", snap="power_partial_tick9")
        s.step(1, "Nothing powered; CO2 accumulates.", snap="power_none_tick10")
        s.step(10)
        s.submit(env("fixture:000002", "set_building_enabled", {"building_id": "building_000001", "enabled": True}))
        s.step(1, "Generator back; surplus charges the battery.", snap="power_restored_tick21")
        s.finish()

    def eva_cmd(self, cid, o2, bat=0.006, crew=("crew_000001", "crew_000002")):
        return env(cid, "start_eva", {"site_id": "site_cargo_a", "crew_ids": list(crew), "work_duration_s": 20,
                                      "oxygen_kg_per_crew": o2, "battery_kwh_per_crew": bat})

    def eva_lifecycle(self):
        s = Script(self, "eva_salvage_lifecycle", "Two rejected launches, a valid EVA, salvage, return.",
                   "salvage_6crew", ["EVA check order", "suit/cargo balances in expedition records",
                                     "returned crew switch to base immediately"])
        s.submit(self.eva_cmd("fixture:000001", 0.25), "Passes reserve policy, exceeds 0.2 kg suit capacity.")
        s.submit(self.eva_cmd("fixture:000002", 0.10), "0.10 - 40 * 0.002 = 0.02 < 0.25 * 0.10.")
        s.submit(self.eva_cmd("fixture:000003", 0.12))
        s.step(1, "Launch: 0.24 kg O2 and 0.012 kWh leave base once.", snap="eva_outbound_tick1")
        s.step(9, "Arrive at site.", snap="eva_working_tick10")
        s.step(5, snap="eva_working_tick15")
        s.step(15, "Salvage alloy 4, electronics 2 (carry 6); returning.", snap="eva_returning_tick30")
        s.step(10, "Home: cargo and suit stores return once.", snap="eva_returned_tick40")
        s.submit(self.eva_cmd("fixture:000003", 0.12), "Retry after completion: cached result.")
        s.finish()

    def eva_recall(self):
        s = Script(self, "eva_recall", "Recall during work; no-op recall; recall after completion.",
                   "salvage_6crew", ["recall semantics", "recalled task cancelled without salvage"])
        s.submit(self.eva_cmd("fixture:000001", 0.12))
        s.step(15)
        s.submit(env("fixture:000002", "recall_eva", {"expedition_id": "expedition_000001"}))
        s.step(1, "Returning from the site; no salvage.")
        s.submit(env("fixture:000003", "recall_eva", {"expedition_id": "expedition_000001"}), "Already returning.")
        s.step(1, "No-op recall: revision increases only for the tick.")
        s.step(7)
        s.step(1, "Home at end of interval 24; task cancelled.", snap="eva_recalled_returned_tick25")
        s.submit(env("fixture:000004", "recall_eva", {"expedition_id": "expedition_000001"}))
        s.step(1, "Completed expedition rejects recall: invalid_state.")
        s.finish()

    def storage_limits(self):
        s = Script(self, "storage_limits",
                   "Wastewater storage fills: obligatory metabolic waste overflows as explicit loss with storage_full; "
                   "hydrogen storage fills: the electrolyzer throttles (output_full) instead of dumping output.",
                   "storage_limits_6crew", ["finite wastewater storage with recorded overflow",
                                            "process outputs remain capacity-limited"])
        s.submit(env("fixture:000001", "set_building_enabled", {"building_id": "building_000004", "enabled": False}),
                 "Recycler off so wastewater accumulates.")
        s.step(1)
        s.step(1)
        s.step(1, "Wastewater reaches 1.03 (0.006 lost); hydrogen output halves (output_full).",
               snap="storage_limits_tick3")
        s.step(3, "All 0.012 kg/tick wastewater lost; electrolyzer stopped; O2 still consumed.",
               snap="storage_limits_tick6")
        s.finish()

    def eva_full_store(self):
        s = Script(self, "eva_full_store_return_cache",
                   "Returned cargo exceeds alloy storage: the excess waits in the return cache and drains when "
                   "capacity opens.", "salvage_full_store_6crew", ["return cache written only by the ledger",
                                                                   "tick-scoped drain effects are not persisted"])
        s.submit(self.eva_cmd("fixture:000001", 0.12))
        s.step(40, "Home: 2 of 4 alloy fit (cap 8); 2 wait in return_caches.", snap="eva_full_store_tick40")
        s.save("eva_full_store_cache_tick40", "return_caches.expedition_000001.alloy = 2.")
        s.submit(env("fixture:000002", "place_building",
                     {"definition_id": "fixture_electrolyzer", "cell": [7, 5], "rotation_quarters": 0}),
                 "Spends 2 alloy, opening capacity.")
        s.step(1, "Phase 8 drains the cache: alloy back to 8; cache removed.", snap="eva_full_store_tick41")
        s.save("eva_full_store_drained_tick41", "Empty return_caches; no persisted drain marker.")
        s.finish()

    def eva_stranded(self):
        s = Script(self, "eva_stranded_recall_recovery",
                   "Stub-world fault injection removes the route home; recall strands the team; a retry while blocked "
                   "fails; after the route reopens, recall recovers stranded -> returning.",
                   "salvage_6crew", ["stranded -> returning on valid recall", "expedition_stranded alert",
                                     "stub fault injection is harness-only"])
        wall = [[7, z] for z in range(16)]
        s.submit(self.eva_cmd("fixture:000001", 0.12))
        s.step(15)
        s.inject_blocked(wall, "Harness-only: the stub world treats column x=7 as blocked.")
        s.submit(env("fixture:000002", "recall_eva", {"expedition_id": "expedition_000001"}))
        s.step(1, "No route home: stranded, recall_requested, critical alert; no teleport, no refund.",
               snap="eva_stranded_tick16")
        s.submit(env("fixture:000003", "recall_eva", {"expedition_id": "expedition_000001"}))
        s.step(1, "Retry while still blocked: route_unreachable; still stranded.")
        s.step(3)
        s.inject_blocked([], "Route reopens.")
        s.submit(env("fixture:000004", "recall_eva", {"expedition_id": "expedition_000001"}))
        s.step(1, "Valid recall: stranded -> returning from the site.", snap="eva_recovering_tick21")
        s.step(9, "Home at end of interval 29; task cancelled (no salvage).", snap="eva_recovered_tick30")
        s.finish()

    def equal_revision_load(self):
        alt = Script(self, "habitat_6crew_alt_setup",
                     "Builds the other-campaign save used by load_equal_revision_other_campaign.",
                     "habitat_6crew_alt", ["save schema 2"])
        alt.submit(env("alt:000001", "set_building_enabled", {"building_id": "building_000004", "enabled": False}))
        alt.step(4, snap="alt_campaign_rev5")
        alt_rec = alt.save("alt_campaign_rev5")
        alt.finish()

        s = Script(self, "load_equal_revision_other_campaign",
                   "Import a different campaign's save whose revision equals the current revision; the snapshot cache "
                   "must not return the old campaign. Invalid saves leave the current state untouched.",
                   "habitat_6crew", ["snapshot cache invalidation on import", "import validation"])
        s.step(5, snap="habitat_6crew_tick5")
        s.snapshot_ref("habitat_6crew_tick5", "Prime any snapshot cache.")
        assert s.m.s["revision"] == alt_rec["core"]["revision"]
        assert s.m.s["campaign_id"] != alt_rec["campaign_id"]
        bad = {}
        v = copy.deepcopy(alt_rec)
        v["save_version"] = 3
        bad["wrong_save_version"] = v
        v = copy.deepcopy(alt_rec)
        v["core"]["resources"]["energy_kwh"]["amount"] += 1.0
        bad["energy_aggregate_mismatch"] = v
        v = copy.deepcopy(alt_rec)
        first = sorted(v["definition_manifest"])[0]
        v["definition_manifest"][first] = "0" * 64
        bad["manifest_mismatch"] = v
        v = copy.deepcopy(alt_rec)
        v["subsystems"]["crew_tasks"]["schema_version"] = 2
        bad["crew_tasks_schema_mismatch"] = v
        for name, rec in bad.items():
            path = self.w.write(f"saves/invalid/{name}.json", rec)
            res = s.import_save(rec, path, False, "habitat_6crew_tick5", "Rejected; nothing changes.")
            assert not res["ok"], name
        s.import_save(alt_rec, RES + "saves/alt_campaign_rev5.json", False, "alt_campaign_rev5",
                      "Same revision (5), different campaign: snapshot must be the imported campaign's.")
        s.step(1, "Continues the imported campaign.", snap="alt_campaign_after_load_tick5")
        s.finish()

    def stubs(self):
        m = self.model("salvage_6crew")
        cases = [("fixture_electrolyzer", [7, 5]), ("fixture_electrolyzer", [7, 3]), ("fixture_electrolyzer", [15, 15])]
        routes = [([2, 8], [12, 8]), ([12, 8], [2, 8]), ([2, 8], [3, 3]), ([2, 8], [2, 8])]
        self.w.write("stubs/stub_world_fixture_flat_16.json", {
            "schema_version": 2, "id": "stub_world_fixture_flat_16", "owner": "task_01_test_stub",
            "metadata": {"status": "synthetic_test_fixture",
                         "note": "Stub behavior only; not evidence that Task 02's placement contract is implemented."},
            "placement_cases": [{"snapshot": "salvage_6crew_tick0",
                                 "request": {"definition_id": d, "cell": c, "rotation_quarters": 0},
                                 "response": m.validate_placement(d, c, 0)} for d, c in cases],
            "route_cases": [{"snapshot": "salvage_6crew_tick0", "request": {"from_cell": a, "to_cell": b},
                             "response": m.query_route(a, b)} for a, b in routes],
        })

    def run(self):
        self.write_content()
        for name in ("habitat_5crew", "habitat_6crew", "habitat_9crew"):
            self.habitat_balance(name)
        self.placement_and_save()
        self.power_loss()
        self.eva_lifecycle()
        self.eva_recall()
        self.storage_limits()
        self.eva_full_store()
        self.eva_stranded()
        self.equal_revision_load()
        self.stubs()
        return self.w.written


def json_files(root):
    out = set()
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith(".json"):
                out.add(os.path.relpath(os.path.join(dirpath, f), root).replace(os.sep, "/"))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="fail if committed fixtures differ from a fresh generation")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        written = Generator(tmp).run()
        assert written == json_files(tmp)
        problems = closed_form_checks.run(tmp)
        if problems:
            print("closed-form checks failed on freshly generated fixtures:")
            print("\n".join("  " + p for p in problems))
            return 1
        if args.check:
            have = json_files(FIXTURES_DIR) if os.path.isdir(FIXTURES_DIR) else set()
            stale = []
            stale += [f"missing: {r}" for r in sorted(written - have)]
            stale += [f"extra (not generated): {r}" for r in sorted(have - written)]
            for r in sorted(written & have):
                with open(os.path.join(tmp, *r.split("/")), "rb") as a, open(os.path.join(FIXTURES_DIR, *r.split("/")), "rb") as b:
                    if a.read() != b.read():
                        stale.append(f"changed: {r}")
            if stale:
                print(f"{len(stale)} stale fixture file(s); run without --check to regenerate:")
                print("\n".join("  " + p for p in stale))
                return 1
            print(f"ok: {len(written)} fixture files are up to date; closed-form checks passed")
            return 0
        for r in sorted(json_files(FIXTURES_DIR) - written) if os.path.isdir(FIXTURES_DIR) else []:
            os.remove(os.path.join(FIXTURES_DIR, *r.split("/")))
        for r in sorted(written):
            dst = os.path.join(FIXTURES_DIR, *r.split("/"))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(os.path.join(tmp, *r.split("/")), dst)
        for dirpath, dirs, files in sorted(os.walk(FIXTURES_DIR), reverse=True):
            if not dirs and not files:
                os.rmdir(dirpath)
        print(f"wrote {len(written)} fixture files to {os.path.relpath(FIXTURES_DIR)}; closed-form checks passed")
        return 0


if __name__ == "__main__":
    sys.exit(main())
