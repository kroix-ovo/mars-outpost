# Simulation verification

## A1 foundation

Run from the repository root using the team's Godot 4.7.2 standard console executable:

```powershell
& '<godot-console>' --headless --path . --script tests/simulation/run_a1.gd
```

Replace `<godot-console>` with the Godot 4.7.2 console executable on your machine. The runner returns exit code 0 with `A1_PASS checks=...` on success and exit code 1 for failed assertions. Compiler/runtime errors must also be treated as failures; require the explicit success marker. No editor, main scene, third-party test library, or rendered world is needed. Temporary malformed-content fixtures are written under ignored `.godot/` with process-specific names and removed after the run.

The A1 runtime under `scripts/simulation/` provides:

- Manifest/hash validation, atomic initialization, and detached initial snapshots matching all eight fixture configurations.
- Schema validation and numeric normalization for all seven command types.
- FIFO execution of `set_time_scale` and `set_building_enabled`, acceptance versus resolution, deduplication, and immutable cached results.
- A one-second fixed-step clock, 0/1/5/20 time scales, fractional accumulation, pause/resume, and retained backlog with a 120-tick call budget.
- Stable initial entity IDs, the seeded Godot RNG, command-result events, one final state notification per changing update call, and guards against callback-driven recursive updates.
- Validation of malformed initial content, invalid commands/deltas, failed resolutions, snapshot mutation, callback submission, and equivalent clock outcomes across frame schedules.
- A retained-journal regression check with 2,000 commands, including old result retries, failed-candidate isolation, a structural check that gameplay clones exclude journal metadata, and a deliberately loose timing guard against journal-sized tick copying.

To print a fuller journal-scaling benchmark (0, 250, 1,000, 2,000, and 20,000 retained commands), run:

```powershell
& '<godot-console>' --headless --path . --script tests/simulation/run_a1.gd -- --benchmark
```

`A1_BENCH` reports median milliseconds per runtime tick and total submission/resolution time for each batch. It exercises the current runtime, including A2 power when present. Timings depend on the machine. The default runner checks 0/250/2,000 retained commands and rejects a tick median above the larger of 2 ms or eight times its empty-journal baseline. It also rejects resolution cost per command above the larger of 2 ms or four times the 250-command baseline. These deliberately loose guards catch large scaling regressions; the structural and semantic checks remain necessary even when timing passes.

The facade retains command history/queue metadata separately from transactional gameplay state. Ticks never copy or change that history. Command resolution clones gameplay only, then updates the one journal entry after committing or discarding the candidate. Consequently rollback never needs to copy or undo the whole journal. Future persistence must serialize the facade metadata alongside gameplay; the save envelope remains unchanged.

**The current A1+A2 runtime executes electrical dispatch and resource accounting.** Chemical production, metabolism, crew work, hazards and persistence remain pending. Full 600-tick resource scenarios therefore do not match the reference model yet. This is a partial implementation of contract 2.0.0, not a playable outpost or complete conformance implementation.

`place_building`, `assign_task`, `cancel_task`, `start_eva`, and `recall_eva` reject at submission with `module_unavailable`; their IDs are not claimed. Save/load return the same explicit unavailable status. Supplied world/crew service references are reserved for subsequent integration and are not called by A1. No unavailable command is acknowledged as successful work.

Initialization currently supports the explicitly marked synthetic fixture content formats only. Production map/crew formats and adopted scientific data remain later integration work. It rejects production data explicitly rather than treating synthetic assumptions as real science.

## A2 accounting and electrical dispatch

```powershell
& '<godot-console>' --headless --path . --script tests/simulation/run_a2.gd
```

Require exit code 0, `A2_PASS checks=...`, and no compiler/runtime errors. The suite covers atomic multi-resource rejection, finite quantities, units, integer counts, capacities, reservations, uncapped CO2, identity conflicts/retries, suit/cargo/site/cache ownership and round trips, exact energy conversion, explicit losses, priority ties, multiple batteries, limits, generator controls, availability, modifier intervals, rollback after balance/RNG/receipt changes, pending commands, pause/acceleration/backlog, and 20,000 retained commands **plus** 20,000 retained effects. Remote accounts are isolated synthetic records; these tests do not implement EVA behavior or validate future adapter transitions.

Each running one-second tick executes power in phase 3, then rates/forecasts, power alerts and invariants in phase 8. The phase boundaries for future processes/crew/hazards are visible in `_tick()`. A failed tick leaves the committed gameplay/RNG and journals untouched, discards candidate receipts, emits no speculative signals, and retains accumulated time for retry. Earlier committed command-boundary results remain committed. Snapshots do no simulation work; paused ticks do no dispatch. No public facade, command, snapshot, or project configuration schema changed.

Generators apply condition once. Consumers receive generation first, then grid output from batteries in stable ID order, by descending priority and stable consumer ID. Positive condition permits battery operation with rated limits; condition zero blocks it. Partial positive battery condition does not reduce storage capacity, charge/discharge limits or efficiencies. Disabled/condition-zero batteries retain their stored energy and capacity. A battery never charges and discharges in one interval. Charge limits refer to grid input and discharge limits to grid output. Aggregate energy and power storage totals are checked against the authoritative per-battery balances. Battery charging is excluded from requested/served consumer kW.

Power service updates consumer requested/served kW and power blocking codes. Consumer `operating_fraction` remains **zero** because A3/A4 processes have not run; generation may report its condition/modifier fraction. A2 never grants oxygen, water, hydrogen, CO2 removal or food. It records allocated consumer energy as `sink/load/energy_kwh`; future process integration will partition that allocation into useful work and idle/thermal loss without redispatching it. Power shortfall and battery-low alerts retain their first occurrence while active. Initial diagnostics remain zero until the first completed tick; command boundaries preserve last-tick diagnostics.

The shared contract defines active-event modifiers but does not name their targets. A2's narrow internal convention supports `{target: "power_generation", factor: finite_nonnegative_number}` as a global generation multiplier. Active modifiers apply in sorted event ID and authored array order for `starts_tick <= interval_tick < ends_tick`; unsupported active targets fail the tick explicitly. Event scheduling/activation and hazards remain A5. This does not introduce a new public schema or implement general technology modifiers.

### Internal ledger API and retention

`OutpostResourceLedger.new(candidate, loaded_definitions, retained_receipts, interval_tick)` operates only on its caller-owned gameplay candidate. Call `apply_transfer(effect)` for restricted transfers or `apply_system(effect)` from trusted Task 01 systems. Never forward player envelopes or unchecked adapter requests into the trusted entry point. Both return an operation result, with `applied_tick` and detached `flows` on success. `validate()` checks current balance invariants. `battery_capacity(id)` supplies the checked commissioned battery capacity for power planning. No external code writes balances after initialization.

An internal effect has exactly these fields:

```gdscript
{
    "effect_id": "crew_tasks:expedition_000001:load:0",
    "kind": "eva_load", "owner_id": "expedition_000001",
    "scope": "one_time", # or "tick", with ID tick:<interval_tick>:<flow>:<owner>
    "debits": {"base/oxygen_kg": 0.1},
    "credits": {"suit/expedition_000001/crew_000001/oxygen_kg": 0.1}
}
```

Maps contain nonnegative finite quantities in registry units; count quantities use safe whole integers. Numeric normalization and sorted dictionary serialization form the identity comparison. Preflight checks each full debit against pre-transaction available stock, then combined final balances/capacities. A simultaneous deposit cannot fund an unaffordable debit. No balance changes on rejection.

Accounts resolve directly to existing authoritative fields:

| Path | Authoritative field |
|---|---|
| `base/<resource>` | `records.resources[resource].amount` |
| `battery/<building>/energy_kwh` | `per_battery_energy[building]`, trusted power operations only |
| `suit/<expedition>/<crew>/<oxygen_kg or battery_kwh>` | `records.expeditions[expedition].suit_stores[crew]` |
| `cargo/<expedition>/<resource>` | `records.expeditions[expedition].cargo` |
| `site/<site>/<resource>` | `records.sites[site].remaining_cargo` |
| `return_cache/<expedition>/<resource>` | save-only `return_caches[expedition]` |

Unknown owners, unknown resources and missing slots fail; the ledger never creates a duplicate account store or implicitly creates remote records. Future lifecycle code must prepare authorized zero-valued slots before linked transfers. Suit capacity comes from the crew definition; cargo supports item counts with aggregate crew carry capacity. Suit `battery_kwh` canonicalizes to `energy_kwh`. Aggregate base energy transfers expand by stable battery ID with no electrical conversion loss or rate limit, including disabled storage. Mixing aggregate and per-battery energy paths in one effect is rejected. Both aggregate and per-battery base operations honor the aggregate reservation.

Transfer kinds are `eva_load`, `eva_return`, `salvage_collect`, `cargo_return`, and internal `cache_return`. Each restricts direction and owner; collection also requires the expedition's reserved site. Canonical resources must balance. Only suit returns can credit `loss/oxygen_kg` or `loss/energy_kwh`, precisely for unavoidable overflow after filling available storage. Cargo overflow must credit its owner's existing return cache, precisely for the amount that cannot fit. A2 verifies accounting/ownership, while the future facade/adapter integration must additionally authorize effect IDs and expedition transitions before invoking these operations.

Trusted kinds are `power_dispatch`, `production`, `conversion`, `external_source`, and `external_sink`. They must still balance each canonical resource using explicit `source/<classification>/<resource>` debits and `sink/<classification>/<resource>` credits. Source classifications: `generation`, `production`, `environment`, `conversion`; sink classifications: `load`, `battery_loss`, `curtailment`, `conversion`, `environment`. They are internal boundary flows, not stored inventories. Conversion callers must explicitly classify consumed/produced resources; the ledger does not invent chemistry. System-specific authorization/stoichiometry remains the trusted system's responsibility. `flows` records each named source/sink and permitted return loss; last committed power flows live in save-only `power_flows` without expanding the snapshot.

The ledger reads retained immutable receipts **by reference**, stages new one-time receipts in `staged`, and keeps current-interval duplicates in `tick_guards`. A successful retry returns the cached detached result; conflicting normalized content fails. A transaction error creates no receipt. After all enclosing gameplay checks pass, the facade swaps the candidate and merges only `staged` into `_committed_effects`. On failure it discards the ledger/candidate. Current-tick guards end with that ledger's transaction lifetime; old tick IDs cannot execute in a later interval. Campaign-retained receipts live outside gameplay clones alongside the command journal. A5 must serialize the receipts under the existing `core.committed_effects` envelope and the save-only gameplay fields under their owning partitions.

### Reproducible A2 example and local measurements

The runner initializes `init/power_shortage_6crew.json`, runs four ticks, disables `building_000001`, runs through battery exhaustion, then restores the generator. It compares only the power/battery fields of `power_loss_and_restore` fixtures. Independently derived expectations: 3 kW generation minus 2 kW load charges at `1 / 3600 * 0.9 = 0.00025 kWh/tick`; four ticks take energy from 0.002 to 0.003 kWh. Each fully served shutdown tick consumes `2 / 3600 / 0.9 kWh`; after four such ticks the next interval serves 1.72 kW, split 0.5/1.0/0.22 by priority. The subsequent interval has no battery power. All quantities are synthetic.

Before A2 edits, local A1 ticks measured about 0.091–0.097 ms across 0–20,000 retained commands. A2's combined history runs measured about 0.37–0.55 ms/tick with empty histories and about 0.36–0.40 ms/tick with 20,000 commands plus 20,000 effects; measured command submission/resolution cost was about 0.07–0.09 ms/command. The clean-copy run measured 0.402/0.399 ms per tick with empty/large histories. These are local console measurements on this synthetic state, not universal performance promises or evidence for larger future colonies.

Final local verification on 2026-11-14: A1 `A1_PASS checks=14289`, A1 large-journal benchmark `A1_PASS checks=36555`, A2 `A2_PASS checks=41144`, all with exit code 0 in both the worktree and a fresh project copy without imported cache. Fixture freshness passed for all 85 JSON files, independent closed-form checks passed, and `git diff --check` passed. The baseline before edits also passed (A1 14283 checks; full benchmark 36545 checks).

For a clean-cache reproduction, copy tracked files and the current A2 source to a fresh temporary project directory excluding `.git` and `.godot`; run A1, its `--benchmark` variant, and A2 there with the same `<godot-console>` commands. No editor import or `.godot` cache is required. Also run fixture freshness and `git diff --check` in the source worktree.

## Reference tooling

```powershell
python tests/simulation/tools/generate_fixtures.py --check
python tests/simulation/tools/closed_form_checks.py
```

These verify reproducible expectations and independent arithmetic. See [tools/README.md](tools/README.md) and [fixtures/README.md](fixtures/README.md). Runtime checks compare all eight tick-zero snapshots and the A2 power/battery sequence only. Later work packages must execute the remaining reference scenarios and add independent invariants; the Python model must not become the runtime implementation.
