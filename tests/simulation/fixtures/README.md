# Task 01 synthetic simulation fixtures

**Status: generated reference fixtures for contract 2.0.0, snapshot schema 2, save schema 2** (the stored `crew_tasks` record is schema 1). Every JSON file here is produced by the committed generator in [`../tools/`](../tools/README.md):

```bash
python tests/simulation/tools/generate_fixtures.py --check
```

**Do not hand-edit these files.** Change the generator sources and regenerate. This README is the only hand-written file in the directory.

**What these files are, and what they are not.** No simulation runtime exists yet, and no fixture script has run against Godot GDScript. The expected values come from a Python reference model of the 2.0.0 rules. Independent closed-form checks (`closed_form_checks.py`) cross-check the key totals without using that model. Agreement between the two is evidence that the arithmetic is right; it is not runtime verification. Early A1 milestones need their own engine-run assertions.

**Every number is synthetic.** No value is physiological, equipment, or planetary data. `sol_s = 1000` is a placeholder, not the Martian sol. Zero EVA food and water draw is a synthetic simplification, not adopted physiology. Do not copy any value into `data/` or `SCIENCE.md`.

**Engine probes**, run with the local Godot 4.7.2 console build:

- All 85 JSON files parse with `JSON.parse_string`, which returns every number as a float.
- `FileAccess.get_sha256` reproduces all 144 manifest entries in the init configs and valid saves.
- `RandomNumberGenerator.seed = 42` gives `state = 708718527385777908`.

These probes test the engine. They are not gameplay tests.

## 1. Layout (85 files)

```text
definitions/   (11)  resources.json (capacity_policy per resource), science/, buildings/ (6),
                     crew/fixture_crew.json, crew/fixture_task_templates.json, map/fixture_flat_16.json
scenarios/     (5)   fixture_habitat, fixture_power_shortage, fixture_salvage,
                     fixture_salvage_full_store (alloy cap 8), fixture_storage_limits (wastewater 1.03, hydrogen 0.0025)
init/          (8)   habitat_5crew, habitat_6crew, habitat_6crew_alt (other campaign id), habitat_9crew,
                     power_shortage_6crew, salvage_6crew, salvage_full_store_6crew, storage_limits_6crew
scripts/       (12)  command/step sequences with expected results (section 4)
snapshots/     (40)  full expected snapshots (snapshot_version 2)
saves/         (4)   valid save_version 2 records
saves/invalid/ (4)   deliberately invalid saves for import-rejection checks
stubs/         (1)   expected stub world placement/route responses
```

Three of the definition files are **Task 01 test stubs**: the crew definition, task template, and map formats. Tasks 02 and 03 have not adopted them. The stub world's placement and route responses are not evidence that Task 02's placement contract is implemented.

## 2. Scripts and what they exercise

| Script | Init | Covers |
|---|---|---|
| `habitat_{5,6,9}crew_balance` | habitat | 600-tick balances; CO2 accumulation (9 crew); input-limited processes and idle power loss (5 crew) |
| `placement_and_save` | habitat_6crew | duplicate / conflict / `invalid_schema` / `unsupported_contract`; competing and unaffordable placements; labor applied once; mid-job save with a pending command and accumulator 0.4; restore into a new instance; commissioning |
| `power_loss_and_restore` | power_shortage_6crew | charge from surplus, then drain stored energy by power priority; partial power; recovery |
| `eva_salvage_lifecycle` | salvage_6crew | EVA check order (`capacity_exceeded`, `reserve_insufficient`); load, salvage, and return once; returned crew back at base immediately |
| `eva_recall` | salvage_6crew | recall while working, no-op recall while returning, `invalid_state` after completion; task `cancelled` without salvage |
| `storage_limits` | storage_limits_6crew | **wastewater overflow**: storage fills, obligatory metabolic waste is recorded as unrecoverable loss with `storage_full`; **hydrogen full**: electrolyzer throttles with `output_full` instead of dumping output |
| `eva_full_store_return_cache` | salvage_full_store_6crew | **full-store EVA return**: 2 of 4 alloy fit, 2 wait in `return_caches`; drained when a placement spends alloy; no persisted drain marker |
| `eva_stranded_recall_recovery` | salvage_6crew | **stranded recall recovery**: injected route loss strands the team on recall; a retry while blocked fails `route_unreachable`; after the route reopens, `stranded → returning` |
| `habitat_6crew_alt_setup` | habitat_6crew_alt | builds `saves/alt_campaign_rev5.json` (other campaign, revision 5) |
| `load_equal_revision_other_campaign` | habitat_6crew | **equal-revision load**: an instance at revision 5 imports another campaign's revision-5 save and must show the imported snapshot; four invalid saves are rejected first, leaving state unchanged |

## 3. Comparison rules

- **Floats:** match within `1e-8 + 1e-9 * abs(expected)`.
- **Exact matches:** IDs, enums, counters, booleans, strings, `null`, and array order.
- **Integers:** Godot parses all JSON numbers as floats, so `4` equals `4.0`. Count resources must still be whole.
- **Capacity:** `capacity: null` appears exactly for `capacity_policy: "accumulator"` (`co2_kg`). It means accumulation, not unlimited usable storage.
- **Rates and forecasts:** rates with absolute value below `1e-12` are reported as `0.0`; balances are never rounded. `forecast_empty_s` is `null` unless the rate is negative.
- **RNG:** `rng.state` is exact (no wildcard).
- **`reference_external_flows`** is diagnostic output from the reference model: totals of flows entering or leaving the modeled colony during the last call (losses, curtailment, metabolism, removal). The runtime is not required to expose it. A harness may compare it only if the runtime offers an equivalent debug view.

## 4. Script format (schema 2)

```json
{"op": "submit", "command": {...}, "expect_response": {...full acceptance response...}}
{"op": "step", "repeat": 9, "expect": {
   "tick_index": 10, "revision": 11, "state_changed_emissions": 1,
   "command_resolved": [["command_id", true, ""]],
   "flushes": [{"after": "boundary" | "tick", "tick_index": 0, "events": [...game_event records...]}],
   "resource_amounts": {...}, "reference_external_flows": {...},
   "snapshot": "res://.../snapshots/x.json"   (optional)
}}
{"op": "advance", "real_delta_s": 1.0, "repeat": 3, "expect": {...}}
{"op": "get_snapshot", "expect_snapshot": "res://..."}
{"op": "export_save", "expect_save": "res://..."}
{"op": "import_save" | "import_save_into_new_instance", "save": "res://...",
 "expect": {"ok", "code", "reason", "state_changed_emissions", "flushes": []}, "expect_snapshot": "res://..."}
{"op": "stub_world_set_injected_blocked_cells", "cells": [[x, z], ...]}
```

- **`repeat: N`** means: perform the op N times. `expect` applies after the last call, and `flushes`, `command_resolved`, `state_changed_emissions` and `reference_external_flows` cover that last call only.
- **`flushes`** lists the event flushes in order: one entry per command boundary or completed tick that emitted events, with `tick_index` set to the clock value at the flush. Event `tick_index` is the interval that produced the event.
- **`state_changed_emissions`** is `1` when the public call changed state, else `0`.
- **`import_save_into_new_instance`** initializes a fresh simulation from the script's init config first. Later expectations must also hold for an uninterrupted instance; the generator asserts that continuity for `placement_and_save`.
- **`stub_world_set_injected_blocked_cells`** is a harness-only fault injection into the stub world service, used to simulate a route becoming unavailable. It is not a contract operation.

## 5. Stub policies used to compute expectations

**`stub_world_fixture_flat_16`** stands in for Task 02's world service:

- **Placement:** valid when all cells are in bounds, there is no footprint overlap, and an entrance is reachable from airlock `[2,8]` after the new footprint is added.
- **Routing:** four-neighbor BFS, neighbor order `+X, +Z, -X, -Z`; footprints and injected cells block routes.
- **Waypoints:** every cell center, `[x+0.5, 0, z+0.5]`.
- **Route ID:** `route_id = "route_" + sha256(compact sorted-key JSON {blocked_cells, from_cell, map_id, map_revision, to_cell})[:16]`.

**`stub_crew_policy_v2`** stands in for Task 03's crew adapter:

- **Proposals:** every proposal carries `private_record_replacements: {completion_markers: {}, private_counters: {}}`. This stub never replaces private records.
- **Construction:** the template comes from `apply_command(place_building)` (`crew_required` 1, priority 50). `assign_task` makes the crew `working` immediately; each working crew member without unmet needs contributes 1.0 work_s per tick, which Task 01 applies once. Crew on a finished non-EVA task are released at the next intent phase.
- **EVA speed:** the minimum crew speed (1 m/s).
- **EVA reserve:** `load − rate × (outbound + work + return) ≥ reserve_fraction × load`, for both oxygen and battery.
- **EVA return margin:** minimum suit endurance minus the time to return from the current position; `null` when stranded or when no route exists.
- **EVA transitions:** at most one status transition per tick, at tick end.
- **Salvage:** taken in resource-ID order, up to the summed carry capacity (3 per crew).
- **Return:** on arrival, cargo moves to base up to capacity and the rest goes to `return_caches`; suit stores move to base and any excess vents. Crew switch to base immediately. The task ends `completed` if salvage was collected, otherwise `cancelled`.
- **Recall:**
  - Recall while outbound or working with a valid route switches to returning.
  - Recall with no route sets `stranded`, which raises the critical `expedition_stranded` alert.
  - Recall while stranded and still without a route fails with `route_unreachable`, without changing state.
  - Recall while stranded with a valid route switches to returning.
- **Not modeled:** fatigue, stress, and health do not change.

## 6. Closed-form expectations (checked by `closed_form_checks.py`)

Per 1 s tick, with the generator on and no limits reached:

| Flow | Amount |
|---|---|
| Generation and load | 3.0 kW generated; scrubber 0.5 kW (priority 200), electrolyzer 1.0 kW (100), recycler 0.5 kW (50) |
| Battery | charge +1.0/3600 × 0.9 = **+0.00025 kWh**; a 2.0 kW drain is −2.0/3600/0.9 = **−0.000617284 kWh** |
| Electrolyzer | −0.009 potable, +0.008 O2, +0.001 H2 |
| Recycler | −0.012 wastewater, +0.012 potable |
| Scrubber | −0.006 CO2 |
| Each base crew member | −0.001 O2, −0.002 potable, −1 kcal; +0.001 CO2, +0.002 wastewater |
| Each EVA crew member | −0.002 suit O2, −0.0001 suit kWh |

Results checked by the script (n = completed ticks; starting O2 120, potable 500, food 100000, CO2 0.5, wastewater 1.0, battery 18 kWh):

- **6 crew, n = 600:** O2 121.2, potable 494.6, food 96400, H2 0.6, CO2 0.5, energy 18.15.
- **9 crew, n = 600:** O2 119.4, CO2 2.3 (accumulated, capacity `null`), wastewater 4.6. `co2_high` first fires in interval 166.
- **5 crew, n = 600:** potable `500 − 0.007 × 495 − 0.009 × 105 = 495.59`.
- **Power loss:**
  - The battery charges `0.002 + 4 × 0.00025 = 0.003` kWh, then drains four times to 0.000530864.
  - At tick 9 it can serve only `0.000530864 × 0.9 × 3600 = 1.72` kW, so the recycler gets 0.22 kW.
  - CO2 reaches `0.5 + 11 × 0.006 = 0.566` at tick 20.
- **EVA:** base O2 at tick 40 = `120 − 0.24 + 40 × 0.004 + 2 × 0.04 = 120.00`. Alloy reaches 10, electronics 4, and 1 electronics remains at the site.
- **Storage limits:**
  - Wastewater is capped at 1.03. Interval 2 loses `1.0 + 3 × 0.012 − 1.03 = 0.006` kg; each later interval loses 0.012 kg.
  - `storage_full` first fires in interval 2.
  - Hydrogen is capped at 0.0025 after fractions 1, 1, 0.5, so O2 at tick 6 = `120 + 0.008 × 2.5 − 6 × 0.006`.
- **Full-store return:** `return_caches = {expedition_000001: {alloy: 2}}` at tick 40, with alloy at 8. At tick 41 the cache is empty, alloy is 8 again after the placement spent 2, and no `return_cache` marker is persisted.
- **Stranded recovery:** work is frozen at 5 s while stranded. Base O2 at tick 30 = `120 − 0.24 + 30 × 0.004 + 2 × (0.12 − 30 × 0.002)`. The task ends `cancelled` and the expedition `completed`.
- **Equal-revision load:** the two campaigns have equal revisions but different `campaign_id` and different building state.
