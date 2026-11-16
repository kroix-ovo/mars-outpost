# Package 2 review: mission clock, scheduler and safe advancement

## Result

Implemented in `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`, branch `overhaul/living-colony-pr10`, on top of package 1 (PR #10 base `5d33c7b`). The v3 campaign facade now has a calendar, a persisted scheduled-boundary queue, strict fast-forward commands, bounded per-call work and an exact stable-interval replay that is checked against the one-second oracle.

This handoff was shortened at the user's direction on 2026-11-15 so the session could move to `docs/overhaul/RUSH_SUBMISSION.md`. **The full 180-day detailed-oracle chain was not run.** Everything else below was run; see *Evidence* for exactly what covers which horizon.

Nothing was committed, pushed, merged or deployed.

## Behaviour and how to exercise it

Headless harness (there is no campaign scene yet; scene and HUD wiring belong to packages 3 and 7):

```powershell
$godot = 'C:/Users/Symok/Downloads/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script tests/campaign/run_time.gd            # CAMPAIGN_TIME_PASS
& $godot --headless --path . --script tests/campaign/run_time.gd -- --quick # CAMPAIGN_TIME_QUICK_OK, skips only the day oracle
python tests/campaign/run_time_oracle.py --godot $godot --only week         # TIME_ORACLE_PASS
python tests/run_headless_checks.py --godot $godot --benchmark              # HEADLESS_PASS
```

- **Profile and pacing.** A config with `campaign_profile_path` (hash-verified, `data/campaign/time_profile.json`) starts paused and runs 120 simulated seconds per real second at 1x, with 5x and 20x multipliers through the existing `set_time_scale`. The facade applies that rate and reports `owns_time_pacing`; `SimulationBridge.paced_delta` then passes real seconds, so the legacy 60/120/240 wrapper pacing is not applied twice. Configs without the key keep fixture clock semantics.
- **Calendar.** `get_calendar()`: mission day, month (30 days), time of day, shipment cycle, next arrival (every 180 days), next order deadline (30 days earlier), effective rate, fast-forward record.
- **Scheduler.** `campaign.time.queue`, ordered by `(due_tick, phase, sequence)`. Built-ins: `day_start`, `shipment_order_deadline`, `shipment_arrival`. `register_boundary_handler` and `Scheduler.schedule` are the interface for later packages. Handlers may draw from the simulation RNG; draws happen only at boundaries or in ticks.
- **Fast-forward.** `request_fast_forward {target_elapsed_s}` and `cancel_fast_forward {}`, strict v3 payloads, revalidated on resolution, deduplicated across reload. Stop reason, detail and tick are in the snapshot: `target_reached`, `cancelled`, `paused`, `danger`, `deadline`, `shipment`, `scheduled`. `error` is reserved and not produced.
- **Oracle and replay.** `set_time_integration("detailed")` is the one-second oracle. In `auto`, a stable interval replays the ledger's recorded per-account operands tick by tick and must be confirmed by the real tick at its end, otherwise it is discarded. Results are bit-identical to detailed stepping in every scenario tested.
- **Hooks.** `register_time_hook` with `next_transition` / `detailed_interval` / `aggregate_interval`. A system without an aggregate model forces detailed stepping and is reported.
- **Capabilities.** `fast_forward: true`; `time_integration` reports power, life support, crew demand and ledger margins as `aggregate`, and crew activity as `detailed_fallback`.

Full interface text: `docs/overhaul/CAMPAIGN_CONTRACT.md`, section *Implemented time and scheduler (package 2)*.

## Public commands, schemas and content

- New commands: `request_fast_forward`, `cancel_fast_forward` (contract 3.0.0 only).
- New events: `fast_forward_started`, `fast_forward_stopped`, `calendar_day`, `calendar_month`, `shipment_order_deadline`, `shipment_due`.
- Snapshot: `campaign.schema_version` 2 with `campaign.time`. Checkpoint envelope unchanged (save version 3); config may carry `campaign_profile_path`.
- Migration policy: partition schema 1 without a `time` record is upgraded on import (`migrated_from: 1`). Other shapes are rejected with no partial replacement.
- Content: new `data/campaign/time_profile.json`. `data/campaign/content.json` unchanged, so foundation saves still match by hash.

## Changed paths

Modified: `scripts/simulation/simulation.gd` (overridable seams only), `scripts/world/sim_bridge.gd` (`paced_delta` guard), `scripts/campaign/campaign_simulation.gd`, `campaign_schema.gd`, `campaign_save.gd`, `campaign_save_store.gd`, `tests/run_headless_checks.py`, `tests/campaign/run_foundation.gd` (one assertion: `fast_forward` is now true), `docs/overhaul/CAMPAIGN_CONTRACT.md`, `docs/overhaul/README.md`.

New: `scripts/campaign/campaign_calendar.gd`, `campaign_scheduler.gd`, `campaign_commands.gd`, `campaign_time_hook.gd`, `campaign_time_hooks.gd`, `campaign_tape_ledger.gd`, `data/campaign/time_profile.json`, `tests/campaign/run_time.gd`, `time_harness.gd`, `run_time_oracle.gd`, `run_time_oracle.py`, `tools/make_time_fixtures.py`, `fixtures/` (six generated files), `README_TIME.md`.

## Evidence

Engine: Godot 4.7.2 console binary, native Windows, headless. Logs are under `build/` (ignored by git): `package2-baseline.log`, `package2-validation.log`, `package2-time-oracle.log`.

Baseline before any change: `HEADLESS_PASS`, including `CAMPAIGN_FOUNDATION_PASS checks=331`. No baseline failures.

After the change (full output in [02_TIME_AND_SCHEDULER_VALIDATION.txt](02_TIME_AND_SCHEDULER_VALIDATION.txt)):

- `python tests/run_headless_checks.py --godot $godot --benchmark`: `HEADLESS_PASS`. All legacy suites pass unchanged (`A1_PASS`, `A2_PASS`, `A3_PASS`, `BRIDGE_PASS`, `TUTORIAL_PASS`, `FRONTEND_PASS`, `CAMERA_CONTROLS_PASS`, both scene boots), plus `CAMPAIGN_FOUNDATION_PASS checks=331` and `CAMPAIGN_TIME_PASS checks=332` (423.5 s, of which the oracle day is 176 s).
- Stable day, full oracle: 86,400 detailed ticks in 175.8 s. Replay path: the same day in 58 ms with 16 real ticks and 14 intervals. Checkpoints, events and RNG identical.
- Bounded work: two days in 36 budgeted calls, at most 3 detailed ticks and 43,936 account-ticks per call, longest call 13.4 ms on a machine that was also running seven oracle processes.
- `python tests/campaign/run_time_oracle.py --godot $godot --workers 7 --only week`: `TIME_ORACLE_CHAIN_PASS week simulated_days=7 segments=7 matched=7`, `TIME_ORACLE_PASS`. 604,800 detailed ticks reproduce the replay checkpoints byte for byte, across battery saturation on day 2.
- Replay to day 200: 17,280,000 simulated seconds in 10.9 s, 2,828 real ticks, 2,619 intervals, 0 rejected, 2,428 calls.

Scenario comparisons (oracle and replay given the same commands; full checkpoint, event list and RNG compared exactly; declared tolerance abs 0 / rel 0, measured deviation 0 in every line):

| Scenario | Ticks | Replay: real ticks / intervals | Covers |
|---|---|---|---|
| battery_saturation | 3,000 | 11 / 2 | battery reaches capacity |
| reserve_exhaustion | 2,500 | 18 / 3 | food runs out at tick 501, danger stop, six shortage events |
| production_shortage_power | 3,000 | 27 / 25 | battery drains, partial power, danger stops |
| production_shortage_inputs | 2,000 | 32 / 18 | input-limited processes |
| storage_overflow | 2,000 | 22 / 17 | wastewater storage full, overflow loss |
| crew_travel_and_labor | 600 | 23 / 5 | detailed fallback until construction completes |
| expedition | 400 | 28 / 4 | EVA phases on detailed stepping |
| scheduled_rng_boundaries | 16,000 | 11 / 6 | seeded draws, same-tick ordering, scheduled stop |
| unmodeled_hook_fallback | 3,000 | 3,000 / 0 | forced detailed stepping, reported |
| registered_hook_flow | 5,000 | 3 / 1 | hook with a real ledger effect |
| ordinary_advance_20x | 6,000 | 12 / 10 | normal play, frame-splitting independence |

Also covered: calendar queries, pacing at 1x/5x/20x, the bridge guard, strict payload rejection, earlier and equal targets, a second request while active, cancel and no-op cancel, paused queue processing, pause stopping a fast-forward, save mid fast-forward restored into both modes, twelve malformed `time` records rejected with the runtime unchanged, an unregistered boundary kind rejected, and schema-1 migration at tick 0 and at a later tick.

Horizons:

- **Stable day:** full oracle, 86,400 real ticks against the replay path, inside `run_time.gd` (figures above).
- **Week:** replay path with oracle windows after every day and across battery saturation (inside `run_time.gd`), plus the full chained oracle from `run_time_oracle.py --only week` (result above).
- **First 180-day boundary:** replay path to day 200 inside `run_time.gd`. Fast-forward stops at the day-150 order deadline, the day-180 shipment boundary and the day-200 target; 200 day events, 6 month events, 1 shipment event; no rejected interval; an oracle window after the boundary matches. **The full detailed oracle for these 180 days was not run** (about 9 CPU-hours; the parallel run was stopped for the rush work). `python tests/campaign/run_time_oracle.py --godot $godot` runs it.

Sustainable-conditions boundary: the 180-day runs use `time_sustainable`, a synthetic fixture with declared stocks large enough for 180 days and no food production. It does not show that a habitat survives 180 days without agriculture.

Rendered checks: this package adds no UI and no scene uses the campaign facade yet, so there are no screenshots. `sim_bridge.gd` changed by one guarded branch; the bridge regression suite (`BRIDGE_PASS`) covers the legacy pacing path. The rendered pacing profiler was not rerun. No manual playtest.

## Limitations and remaining work

- Replay is linear in simulated ticks (roughly 2,000 times cheaper per tick than a detailed tick here), not O(1). 200 days took 8.5 to 11 s of compute across about 2,400 bounded calls.
- Crew travel, labor, expeditions and return-cache draining always use detailed stepping.
- A state that cycles at the last floating-point bit rather than settling would never qualify for replay and would stay on detailed stepping. None was seen.
- The fractional accumulator's last bit can depend on frame splitting when deltas are not exactly representable and a backlog is retained (same as v2). Fast-forward does not use the accumulator.
- Per-call work without a wall-clock budget is bounded by counts (8 detailed ticks, 50,000 account-ticks), measured at up to about 50 ms here while the machine was loaded. Interactive callers should use `advance_budgeted`.
- Stops for repair readiness, treatment capacity and tutorial milestones need their own packages. Cargo delivery at the shipment boundary is package 9; the `cargo` and `director` records are unchanged.
- No campaign scene, HUD control or browser check exists for fast-forward yet.

## Next

Package 3 (camp construction) is unblocked once this is reviewed. Note that `docs/overhaul/RUSH_SUBMISSION.md` currently replaces the package sequence for the submission build.
