# Task 01 synthetic simulation fixtures

> Reconciliation status: the accepted implementation baseline is now contract **2.0.0**, snapshot schema **2**, save schema **2**. These reference outputs still encode proposal defaults and 1.0.0 version labels. Regenerate them from a committed reference generator before treating them as contract-conformance fixtures. See `../../../SIMULATION_RECONCILIATION.md`; the generator source is not present yet.

**Status: proposal fixtures for review (revision 3).** They encode the working defaults in [`SIMULATION_DESIGN_PROPOSAL.md`](../../../SIMULATION_DESIGN_PROPOSAL.md) on top of shared contract 1.0.0. Where the contract is still being reconciled, the fixtures follow the proposal. Each script lists the decisions it depends on in `depends_on_decisions`; if reconciliation changes one of those decisions, the affected files must be regenerated.

**Every number here is synthetic.** The values were chosen so that balances are easy to check by hand. None of them is a physiological, equipment or planetary value; `sol_s = 1000` in particular is a placeholder, not the Martian sol. Do not copy any value into `data/` or `SCIENCE.md`.

No simulation code exists yet. Expected values come from a Python reference model of the proposed rules, which lives outside the repository. Section 6 gives closed-form checks that do not depend on that model.

The engine facts these fixtures rely on were checked headlessly with the local Godot 4.7.2 build:

- `FileAccess.get_sha256` reproduces every manifest hash.
- All 55 JSON files parse.
- `JSON.parse_string` returns every number as a float.
- `RandomNumberGenerator.seed = 42` gives `state = 708718527385777908`.

## Changes in revision 3

- **Suit and cargo balances** now live only in the expedition records (`suit_stores`, `cargo`), and the ledger is their only writer. Return-cache balances belong in `crew_tasks.state.return_caches`. The save no longer has a `ledger_accounts` key.
- **CO2 is an accumulator.** `co2_kg` has `capacity_policy: "accumulator"`, a snapshot `capacity` of `null`, and is never capped or discarded. Only a modeled removal process (the scrubber) takes it out of the cabin.
- **Event flushes are recorded per boundary and per tick.** `expect.flushes` replaces the old `events` field.
- **The power-loss script now charges the battery first.** The battery charges from surplus generation for four ticks, then the generator is disabled and the stored energy drains.
- **`rng.state` is pinned to the measured Godot value.** There are no wildcards left.

## 1. Layout

```text
definitions/
  resources.json                          resource registry, with capacity_policy (Task 01)
  science/fixture_science_synthetic.json  synthetic science/game config (Task 01)
  buildings/*.json                        6 building definitions (contract §7 shape; Task 02 owns real ones)
  crew/fixture_crew.json                  9 crew definitions (PROPOSED shape; Task 03 owns)
  crew/fixture_task_templates.json        job templates (PROPOSED shape; Task 03 owns)
  map/fixture_flat_16.json                16x16 open map (PROPOSED shape; Task 02 owns)
scenarios/   fixture_habitat, fixture_power_shortage (battery 0.002 kWh), fixture_salvage (+1 site)
init/        habitat_5crew, habitat_6crew, habitat_9crew, power_shortage_6crew, salvage_6crew
scripts/     7 command/step sequences with expected results
snapshots/   27 full expected snapshots
saves/       placement_mid_job_tick6.json (mid-job, pending command, accumulator 0.4)
stubs/       stub_world_fixture_flat_16.json (expected placement/route responses)
```

The crew, template and map files are shape proposals for Tasks 02 and 03, included only so that Task 01 can test without waiting. When those owners publish their own definitions, replace these files rather than extending them.

## 2. Manifest hashes

`init/*.json` and the save map each `res://` path to the SHA-256 of the file's exact bytes. `.gitattributes` forces LF line endings for `*.json`, so the hashes are stable across checkouts. **Editing any file under `definitions/` or `scenarios/` invalidates every manifest that lists it.** Regenerate the fixtures rather than editing hashes by hand.

## 3. Comparison rules

- **Floats:** `abs(actual - expected) <= 1e-8 + 1e-9 * abs(expected)` (contract §2).
- **Exact matches:** IDs, enums, counters, booleans, strings, `null` and array order.
- **Integers vs floats:** Godot's JSON parser returns every number as a float, so `4` equals `4.0`. Count resources must still be whole.
- **Forecasts:** `forecast_empty_s` is `null` unless `net_rate_per_s < 0`. A rate with absolute value below `1e-12` is reported as exactly `0.0` (D20).
- **Accumulator resources:** `capacity: null` means `capacity_policy: "accumulator"`. Such a resource has no storage cap and is never discarded.

## 4. Script format

```json
{"op": "submit", "command": {...}, "expect_response": {...full acceptance response...}}
{"op": "step", "repeat_before": 4, "expect": {
   "tick_index": 4, "revision": 4,
   "command_resolved": [["command_id", true, ""]],
   "flushes": [{"after": "boundary" | "tick", "tick_index": 0, "events": [...game_event records...]}],
   "resource_amounts": {"alloy": 6, ...},
   "snapshot": "res://.../snapshots/x.json"   (optional)
}}
{"op": "advance", "real_delta_s": 0.4, "expect": {...}}
{"op": "get_snapshot", "expect_snapshot": "res://..."}
{"op": "export_save", "expect_save": "res://..."}
{"op": "import_save_into_new_instance", "save": "res://...", "expect": {...}, "expect_snapshot": "res://..."}
```

- **`repeat_before: N`** means: call the op N times, then check `expect` after the last call. `flushes` and `command_resolved` cover only that last call.
- **`flushes`** lists, in order, every event flush the call made. Each entry is one command boundary or one completed tick, and `tick_index` is the clock value at that flush. Flushes with no events are omitted. Each public call emits at most one `state_changed`, after its last flush.
- **After `import_save_into_new_instance`**, every later expectation must hold for both the original instance and the restored one.

## 5. Stub policies used to compute expectations

The scripts depend on two test stubs. Task 01 will provide them under `tests/simulation/` at stage 4 of the proposal; neither exists yet.

**`stub_world_fixture_flat_16`** stands in for Task 02's world service:

- **Placement:** valid if every footprint and entrance cell is in bounds, no footprint cell overlaps an existing non-destroyed footprint, and at least one entrance is reachable from the airlock `[2,8]` after the new footprint is added.
- **Routing:** four-neighbor BFS, neighbor order `+X, +Z, -X, -Z`, 1 m edges. Building footprints block routes. Waypoints are every cell center on the path, `[x+0.5, 0, z+0.5]`.
- **Route ID:** `route_id = "route_" + first 16 hex characters of sha256(compact sorted-key JSON {blocked_cells (sorted), from_cell, map_id, map_revision, to_cell})`. This is a proposal for Task 02.

**`stub_crew_policy_v1`** stands in for Task 03's crew adapter:

- **Assignment:** `assign_task` makes the assigned crew `working` immediately (in-base travel is instantaneous) and the task `active`.
- **Labor:** each assigned crew member who is `working`, at base and without unmet needs contributes `1.0` work_s per tick. Task 01 applies that labor once to the construction counter (D5).
- **Release:** a crew member whose task is terminal is released at the next tick's intent phase (D18).
- **Templates:** construction uses `crew_required` 1 and priority 50 (D4).
- **EVA timing:** the team moves at the minimum crew speed (1 m/s). Outbound and return each take 10 ticks on the 10 m route, and work takes `work_duration_s` ticks. At most one status transition per tick, at tick end. These proposals must pass Task 01's EVA progress checks (D17).
- **EVA reserve check:** `load − rate × (outbound + work + return) >= reserve_fraction × load` for both oxygen and battery. This check runs before the ledger checks suit capacity (D23).
- **Return margin:** `return_margin_s` = minimum suit endurance across the crew minus the time to return to base from the current position.
- **Salvage:** at work completion, the team takes site cargo in resource-ID order, up to the summed crew carry capacity (3 per crew).
- **Return:** cargo and unused suit stores move to base once. The task ends `completed` if salvage happened, or `cancelled` after a recall before salvage (D24).
- **Not modeled:** fatigue, stress and health do not change.

## 6. Closed-form checks (independent of the reference model)

Per 1 s tick, with the generator on and no limits reached:

| Flow | Amount |
|---|---|
| Generation | 3.0 kW |
| Load | scrubber 0.5 kW (priority 200) + electrolyzer 1.0 kW (100) + recycler 0.5 kW (50) = 2.0 kW |
| Battery charge | 1.0 kW surplus × 1/3600 h × 0.9 = **+0.00025 kWh** |
| Battery discharge for 2.0 kW | stored −(2.0 / 3600) / 0.9 = **−0.000617284 kWh** |
| Electrolyzer | −0.009 potable, +0.008 O2, +0.001 H2 |
| Recycler | −0.012 wastewater, +0.012 potable |
| Scrubber | −0.006 cabin CO2 (modeled removal process) |
| Each base crew member | −0.001 O2, −0.002 potable, −1 kcal; +0.001 CO2, +0.002 wastewater |
| Each EVA crew member | −0.002 suit O2, −0.0001 suit kWh (no base draw) |

Starting values: O2 120, potable 500, food 100000, CO2 0.5, wastewater 1.0, battery 18 kWh. Here n is the number of completed ticks.

**6 crew.** O2 `120 + 0.002n`, potable `500 − 0.009n`, food `100000 − 6n`, H2 `0.001n`, energy `18 + 0.00025n`; CO2 and wastewater stay constant. At n = 600 that gives O2 121.2, potable 494.6, food 96400, H2 0.6, CO2 0.5, wastewater 1.0 and energy 18.15.

**9 crew.** CO2 accumulates at 0.003 per tick, and `co2_high` (≥ 1.0 kg) first fires in interval 166. At n = 600: O2 119.4, potable 491.0, **CO2 2.3** (nothing discarded), wastewater 4.6.

**5 crew.** CO2 and wastewater hit the input-limited point at interval 495. From then on, the scrubber and recycler run at an operating fraction of 0.8333 with `input_limited:*` codes, and the unused allocated power is recorded as idle loss. Potable water at n = 600: `500 − 0.007 × 495 − 0.009 × 105 = 495.59`.

**Power loss** (`power_loss_and_restore`):

| After tick | What happens | Battery (kWh) | CO2 |
|---|---|---|---|
| 1–4 | Generator on; battery charges | `0.002 + 4 × 0.00025 = 0.003` | 0.5 |
| 4 (boundary) | Generator disabled | — | — |
| 5–8 | Battery serves all 2.0 kW | `0.003 − 4 × 0.000617284 = 0.000530864` | 0.5 |
| 9 | Battery can deliver only `0.000530864 × 0.9 × 3600 = 1.72` kW: scrubber 0.5, electrolyzer 1.0, recycler 0.22 (`partial_power`, fraction 0.44); then empty | 0 | 0.5 |
| 10–20 | Nothing powered; O2 −0.006 per tick | 0 | **+0.006 per tick**, reaching 0.566 at tick 20 |
| 20 (boundary) | Generator re-enabled | — | — |
| 21 | Battery charging again | +0.00025 | — |

**EVA.** Base O2 at tick 40 = `120 − 0.24 (load) + 40 × 0.004 (net, 4 base crew) + 2 × 0.04 (returned) = 120.00`. Alloy goes 6 → 10 and electronics 2 → 4; 1 electronics remains at the site.
