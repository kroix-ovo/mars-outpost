# A2 handoff — resource ledger and electrical power

Implement this plan in the next chat. This is a coding handoff, not a request to create another planning document. Complete implementation, run the checks, and publish a reviewable branch/PR. Keep the work within A2.

## Starting point

- Repository: `https://github.com/kroix-ovo/mars-outpost`.
- Task: Task 01, package A2. A1 is on `feat/simulation`, reviewed through commit **`8f077d0`**, in draft PR #1. Verify current Git/PR state before branching; do not assume A1 has merged.
- Base A2 on a branch containing `8f077d0` and this handoff. Use `feat/simulation-a2` in an isolated worktree if A1/Claude review is still active. Do not overwrite another contributor's checkout or changes. If A1 remains unmerged, make the A2 PR target `feat/simulation` so it shows only A2 changes; retarget to `main` after A1 merges.
- Engine: Godot 4.7.2 standard edition, GDScript. On the current machine the console executable is under the user's Downloads/Godot folder. Locate it locally; use `<godot-console>` placeholders in published instructions.
- Current runtime: initialization, detached snapshots, seven command schemas, FIFO/deduplicated core control commands, clock/pause/acceleration. Only `set_time_scale` and `set_building_enabled` execute. Ticks currently advance structural time only.
- Command history, pending queue and receive sequence now live in the **facade**, outside cloned `OutpostGameState`. Preserve that fix. Do not reintroduce full-history copies to implement ledger idempotence.

## Read first

1. `AGENTS.md`.
2. `SHARED_SIMULATION_SPEC.md`, especially sections 2–7, 9, 11–12 and 14.
3. `TASK_01_SIMULATION.md`, `SIMULATION_RECONCILIATION.md`, and `PRD.md`.
4. `scripts/simulation/{simulation,game_state,definitions,command_schemas}.gd`.
5. `tests/simulation/README.md` and `run_a1.gd`.
6. `tests/simulation/tools/README.md`, `closed_form_checks.py`, and the power-related portions of `reference_model.py`.
7. Fixture building/scenario definitions and `scripts/power_loss_and_restore.json` under `tests/simulation/fixtures/`.

The shared spec governs external interfaces. The Python model is a limited reference oracle, not runtime code to translate wholesale or authority over the spec. Fixture map/crew formats remain test stubs. All quantities in these fixtures are synthetic.

## Outcome and boundaries

Deliver an atomic resource ledger and deterministic electrical dispatch integrated into the existing one-second tick. A generator must serve priority loads, charge batteries with surplus, and stop on a control command; batteries must then cover the deficit until exhausted.

Implement storage/accumulator policies, unit validation, whole item counts, transfer accounting, explicit losses, exactly-once effects, and power/battery diagnostics. Include the minimal rate/forecast finalization needed to keep changed resource records accurate; broader production forecasting remains A4.

Do not implement metabolism, electrolysis/water/CO2 processing, crops, construction/crew jobs, EVA command behavior, hazards, research trees, save/load, world scenes, UI, or deployment. Those remain A3–A5 or Tasks 02/03. Leave their commands explicitly unavailable. Do not add a server, dependencies, or a generic subsystem framework. Do not alter `project.godot`.

## Step 1 — establish the regression baseline

Run these before edits, recording failures rather than assuming the branch is healthy:

```text
<godot-console> --headless --path . --script tests/simulation/run_a1.gd
<godot-console> --headless --path . --script tests/simulation/run_a1.gd -- --benchmark
python tests/simulation/tools/generate_fixtures.py --check
```

Require the explicit Godot success marker and exit code 0. A2 must preserve journal-independent tick cost, FIFO semantics, callback guards, pause/backlog behavior, and all eight initial snapshot matches.

## Step 2 — implement the ledger

Add `scripts/simulation/resource_ledger.gd`. Keep it a focused headless service operating on a caller-owned gameplay candidate; only the facade commits that candidate.

- Define a small internal transaction record: stable effect ID, kind/owner, nonnegative debit and credit maps, explicit source/sink classification where applicable, and retention scope (one-time or current tick). Document the internal API in the simulation test README. Keep public command/snapshot schemas unchanged.
- Resolve account paths to their existing authoritative fields. Start with base resources and battery energy; support existing-record suit/cargo/site/return-cache transfers through isolated synthetic state tests without implementing EVA lifecycle or creating a duplicate account store. Unknown/missing accounts fail explicitly.
- Canonicalize suit `battery_kwh` to base `energy_kwh` for conservation/unit checks. Counts must remain integral; numeric values must be finite. Validate known resources, ownership, capacities, and available amounts (`amount - reserved`).
- Preflight the entire transaction, including combined/net effects on each account, before changing any balance. Invalid debit/credit, insufficient stock, bad unit/count, or overflow leaves every account unchanged. A deposit must not hide an otherwise unaffordable debit.
- Storage credits respect finite capacity; accumulator capacity is `null`. CO2 never disappears due to a fictional storage limit. Explicit permitted loss destinations are accounted for, never silently clamped. Metabolic wastewater overflow behavior itself belongs to A3.
- Transfers conserve each canonical resource. Production/conversion and external sources/sinks must be explicit trusted-system operations, not caller-supplied player rewards.
- Energy has one authoritative per-battery representation, with a checked aggregate `resources.energy_kwh.amount` and power summary. Never debit both the aggregate and individual batteries as separate reservoirs.
- Retry of a committed one-time effect with identical normalized content returns its cached result without reapplying. Same ID/different effect fails. Tick-scoped effects run once within their tick and retain no permanent per-second history.

**Retention/rollback design requirement:** keep campaign-long immutable effect receipts outside full gameplay clones, just like the command journal. Read existing receipts without copying the collection. Stage only the current command/tick's new receipts; merge them after gameplay commit, discard them on failure. Do not write a permanent receipt before the enclosing transaction commits. Keep current-tick duplicate guards bounded. This remains an internal representation choice; future A5 must export the existing spec's `core.committed_effects` envelope.

## Step 3 — implement power dispatch

Add `scripts/systems/power_system.gd`. Use the loaded definitions and active building records; no rendered scene access.

1. Select eligible commissioned, enabled, non-destroyed equipment. Respect condition/availability and active modifiers. Condition-adjust generator output once; do not multiply a future process efficiency by condition twice. Reject or explicitly report unsupported modifier inputs rather than silently ignoring them.
2. Sort consumers by descending `power_priority`, then stable building ID. Serve generation first, then battery discharge, permitting partial service.
3. Dispatch batteries by stable ID, with per-battery stored energy, capacity, rate limits, and efficiencies. A battery cannot charge and discharge in one tick. Disabled/non-operational batteries must not supply power; do not silently erase their retained stored energy or capacity.
4. Charge from excess generation, then record curtailment. Do not redistribute an allocation a second time because a later process is input-limited; that later idle-loss policy belongs to process integration.
5. Update requested/served building power, blocking information appropriate to the power phase, and aggregate power/energy diagnostics. Requested/served kW count consumers, not charging. Do not pretend that served electricity means an unimplemented chemical process ran.

Use these equations with `dt_s = 1.0`:

```text
grid_energy_kwh       = power_kw * dt_s / 3600
discharge_stored_loss = delivered_grid_energy_kwh / discharge_efficiency
charge_stored_gain   = grid_input_energy_kwh * charge_efficiency
conversion_loss      = input_energy - useful_output_energy
```

Discharge rate limits apply to grid output; charge limits apply to grid input. Direct suit-energy transfers use the separate spec-defined no-conversion-loss transfer rule, not electrical dispatch limits. Never mix kW with kWh or silently discard a negative residual.

## Step 4 — integrate atomic ticks

- Extend `_tick()` without changing its fixed timestep or public facade API. Keep the future spec phase order visible: A2 executes electrical dispatch in phase 3 and appropriate finalization in phase 8; unimplemented phases must not fabricate activity.
- Run power and ledger operations on a gameplay working copy, validating all results and invariants before swapping it into the facade. On failure preserve gameplay, RNG, accumulator, pending commands, historical receipts, and emitted-event history. Discard speculative events/receipts. Previously committed command-boundary actions remain committed.
- Set last-tick energy rate from the actual committed amount delta and calculate its constant-rate depletion forecast. Preserve the existing initial-zero diagnostic convention, snapshot shapes, revision rules, and paused behavior.
- Snapshot reads never trigger ledger work. Clock-driven dispatch, battery discharge/charging, and resource rate updates do not run while paused. Legitimate command-driven transfers may still commit at paused command boundaries, as the shared spec requires; do not put a global pause prohibition inside the ledger.
- Keep all balance changes behind the ledger, including battery dispatch. Expose only the necessary internal per-battery operation; do not let `power_system.gd` become a second independent balance writer.

## Step 5 — add meaningful Godot checks

Create `tests/simulation/run_a2.gd` and focused supporting fixtures/helpers as needed. Keep new fixtures separate from the generated reference directory unless changed through its generator.

| Area | Required cases |
|---|---|
| Atomicity | Invalid multi-resource transaction leaves all balances unchanged; no receipt/event escapes a failed enclosing tick |
| Bounds/units | Negative/NaN/Infinity, unknown account/resource, fractional count, capacity overflow, reserved stock, accumulator credit |
| Identity | Identical retry applies once; conflicting effect ID fails; tick guards clear only at the correct boundary |
| Energy | Exact `/3600` conversion, charge/discharge efficiencies, explicit losses, summed battery equality |
| Dispatch | Stable priority ties, multiple batteries, empty/full/partially charged storage, rate-limited discharge, surplus curtailment, generator toggle, unavailable equipment |
| Transfers | Existing suit/cargo/cache account round trips; energy alias mapping; allowed return loss only where contract permits |
| Rollback | Force a failure after a candidate balance change; check balances, RNG, receipts, signals, and accumulator stay valid |
| Time | Pause, 1x/5x/20x, partitioned frames, retained backlog, equal completed ticks produce equal power state |
| Scale | Large command journal AND large retained effect history do not make per-tick/per-command copying grow with history |

Use the existing power fixture's **power/battery fields only** as an A2 integration oracle. It includes A3 chemistry and metabolism, so full resource snapshots are not an A2 acceptance requirement. Independently verify the power sequence:

- Synthetic generation 3 kW, load 2 kW, efficiency 0.9: charge `0.00025 kWh/tick`.
- Four ticks take the small battery from `0.002` to `0.003 kWh`.
- After generator shutdown, each fully served 2 kW tick uses `(2 / 3600) / 0.9 kWh`.
- After four such discharges, the next tick can deliver 1.72 kW: scrubber 0.5, electrolyzer 1.0, recycler 0.22 by priority.
- These are electrical loads only in A2. Do not award oxygen, clean water, or CO2 removal yet.

If the shared behavior is ambiguous, inspect owning code/spec and make a narrow documented decision. Do not change public schemas or silently rewrite generated expected values to make tests pass. Tell the user before undertaking deep research to advance the backend, as `AGENTS.md` requires. A2's accounting/energy math does not require adopting real physiology values.

## Step 6 — finish and hand off

Run A1, its large-journal benchmark, A2, the fixture freshness check, and `git diff --check`. Repeat the headless runtime checks from a clean project copy without `.godot` cache. Record measured timings as local A2 results, not universal performance promises.

Update the simulation README and Task 01 status to distinguish implemented power/accounting from pending life support/crew/persistence. Commit and push the A2 branch and create a draft PR against the correct base. Report changed behavior, test results, remaining limitations, and the PR link. Do not merge an unreviewed A1/A2 PR merely to simplify branching.

Claude may independently review A1/A2 or extend the reference oracle in a separate worktree. This chat owns the A2 runtime math and implementation; do not launch agents or have another agent edit the same runtime files concurrently unless explicitly authorized.
