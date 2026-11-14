# Task 01 — headless simulation design proposal (revision 3)

> Review outcome: see `SIMULATION_RECONCILIATION.md` and the authoritative contract 2.0.0 in `SHARED_SIMULATION_SPEC.md`. This proposal preserves the submitted revision-3 defaults for reference; its 1.0.0 examples and pending-decision tables are historical, not the implementation baseline.

**Status: proposal for review. Nothing here is implemented. It does not edit `SHARED_SIMULATION_SPEC.md` (contract 1.0.0) or any runtime file.**

Revision 3 applies the review of revision 2. These parts of revision 2 were accepted and are unchanged:

- one facade with explicit tick phases;
- working-copy transactions, to be measured before anything more complicated replaces them;
- one resource ledger;
- Task 01 stores authoritative state and Task 03 proposes changes;
- synthetic fixtures first.

The six review corrections and the private-state resolution are applied in §1.

Labels:

- **Existing**: already fixed by the contract, the PRD, or the task docs.
- **Proposed**: Task 01 internal design that needs no contract change.
- **Pending contract**: a working default that awaits your reconciliation. The fixtures follow it; implementation follows the contract as it stands until the contract changes.

Complete synthetic fixtures are in [`tests/simulation/fixtures/`](tests/simulation/fixtures/README.md). All numbers are synthetic and no science value is adopted.

---

## 1. Review corrections applied

| Review item | Revision 3 behavior |
|---|---|
| **State duplicated between `ledger_accounts` and expedition records** | `ledger_accounts` is removed from the state and from the save. Suit stores and cargo are authoritative in `expeditions[*].suit_stores` and `expeditions[*].cargo`; return-cache balances are authoritative in `crew_tasks.state.return_caches`. The ledger is the **only writer** of those fields. Task 03's full-record proposals must repeat the input values of those fields unchanged (Existing placeholder rule, §8). |
| **CO2 disappeared when "storage" filled** | `co2_kg` is an **accumulator resource**: the registry declares `capacity_policy: "accumulator"`, the ledger never caps its credits, and nothing discards it. Only a modeled removal process (a scrubber) removes cabin CO2. Accumulated CO2 drives the hazard evaluation in phase 7 (and `co2_high` alerts now). The snapshot reports `capacity: null`, which needs the contract change in D13. |
| **Power-loss arithmetic error** | The revision 1 example assumed an empty battery right after a tick that had charged it. The fixture now charges the battery from surplus for four ticks (0.002 → 0.003 kWh), then disables the generator and drains the stored energy tick by tick (§4.3). |
| **Events flushed only after the whole `advance` batch** | Committed command results and events are flushed after **each** command boundary and after **each** tick, as the contract requires. Each public call emits one final `state_changed`. The fixtures record this as `expect.flushes`. |
| **Unclear work-counter ownership** | Task 03 supplies `labor`; Task 01 applies it once to construction and repair counters. EVA travel and work progress get explicit rules (D17, §2.9). |
| **Every `core:*` effect retained forever** | Only **irreversible completion markers** are persisted. Repeated transactions such as return-cache drains and overflow use **tick-scoped** effect IDs, which are guarded within the tick and never persisted (D1). |
| **Adapter private-state updates undefined** | Proposals carry **validated full-record replacements** of the affected private records, committed atomically with the rest of the proposal. There is no dictionary merge (D2). |

---

## 2. Working defaults

### 2.1 Pending contract

| # | Working default |
|---|---|
| **D1 Effect retention** | **Persisted markers** (`committed_effects`, kept forever) are for irreversible one-time outcomes: `cmd:{command_id}:build_cost`, `core:{task_id}:commission`, `core:{task_id}:construction_refund`, `core:{task_id}:repair_complete`, `core:crop:{building_id}:{cycle_id}`, and `crew_tasks:{expedition_id}:{eva_load\|salvage_collect\|cargo_return\|eva_return}:0`.<br>**Tick-scoped effects** use IDs of the form `tick:{n}:<flow>:<owner>`. They are used for power, processes, metabolism, suit use, leakage, return-cache drains (`tick:{n}:return_cache:{expedition_id}:{resource_id}`) and capacity overflow (`tick:{n}:overflow:{building_id}`). The ledger accepts one only while executing tick `n`, and only once within that tick's transaction; an in-memory set that is discarded at commit enforces this. Because `tick_index` is saved and each tick commits once, the protection is bounded and nothing grows per second. |
| **D2 Private state** | `CrewTickProposal` and `CommandProposal` gain `private_record_replacements: {collection: {record_id: full_record}}`. `collection` is `completion_markers` or `private_counters`; `return_caches` is excluded because the ledger writes it. Each value replaces that record entirely. Removal requires an explicit `null`, and only where Task 03's schema for that collection allows it. Before commit, Task 01 applies the replacements to the candidate `crew_tasks` record and calls `crew_adapter.validate_state(candidate, candidate_core)`. Any failure rejects the whole proposal, together with its state updates and resource requests. |
| **D3 Save additions** | Core gains `power_summary` (last completed tick) and `alerts` (persistent conditions with `first_tick`). `core.resources` includes `energy_kwh` with its derived amount, which must equal the sum of `per_battery_energy` (a corruption check). There is no `ledger_accounts` key. |
| **D4 Construction template** | For `place_building`, Task 01 calls `crew_adapter.apply_command` to obtain the construction job template (`crew_required`, default priority). |
| **D5 Construction and repair counters** | Task 03 supplies `labor` entries `{task_id, crew_id, work_s}`. Task 01 sums them in crew-ID order and applies them once to `completed_work_s` (capped at the required work) and to `construction_progress` or repair condition. `task_updates` must repeat the input `completed_work_s`. Farming labor feeds Task 01's crop process (Existing). |
| **D8 Vocabularies** | `blocking_codes`: `constructing`, `disabled`, `destroyed`, `damaged`, `no_power`, `partial_power`, `input_limited:<id>`, `output_full:<id>`, `event_modifier:<id>`. Alert codes: `power_shortfall`, `battery_low`, `co2_high`, `low_oxygen`, `storage_full`, `expedition_low_margin`, `expedition_stranded`. |
| **D13 Accumulator resources** | The resource registry gains `capacity_policy: "storage" \| "accumulator"`. `ResourceBalance.capacity` becomes nullable and is `null` exactly for accumulators. An accumulator is never capped and never sent to a loss sink. A storage resource that fills keeps the existing explicit-loss rule (§2.2 Q-W). |
| **D17 EVA progress** | Task 03 owns expedition status, route and work fields, under the validation rules in §2.9. Task 01 writes the EVA task's `completed_work_s` as a mirror of `work_completed_s`. EVA tasks accept no `labor` entries. |
| **D24 Recall before salvage** | The expedition ends `completed` (the team is safely home); its task ends `cancelled`. |

### 2.2 Task 01 internal

| # | Working default |
|---|---|
| D6 | Working-copy transactions: clone `GameState` for each command and each tick. Benchmark at stage 3; switch to an undo log only if a tick exceeds about 2 ms. |
| D7 | Only the synthetic science config exists. Initialization refuses a science config that isn't marked `synthetic_test_fixture` while any parameter is missing or has no `SCIENCE.md` reference. |
| D9 | `power.served_kw` counts consumers only. `generated_kw` is available generation. |
| D10 | JSON integers are whole floats within ±2^53, cast to `int` (verified: Godot 4.7.2 parses every number as a float). Seed and RNG state travel as decimal strings. |
| D11 | Seeds are decimal values from `0` to `9223372036854775807`. |
| D12 | Failed and no-op commands do not increment `revision`. |
| D14 | Flush after every boundary and every tick; one final `state_changed` per public call. |
| D16 | Snapshots are cached per `revision`; every caller gets its own deep copy. |
| D18 | A crew member whose task ended is released at the next tick's intent phase. |
| D19 | A `command_result` event's `entity_ids` are the sorted runtime IDs among `building_id`, `crew_id`, `expedition_id`, `site_id` and `task_id`. Within a boundary, each command emits its result event, then its own events, in receive order. Tick events are sorted by `(entity_ids, type)`. |
| D20 | A rate with absolute value below `1e-12` is reported as `0.0`; forecasts exist only for negative rates. |
| D21 | Before the first tick, rates and power fields are zero and there are no alerts. |
| D22 | Journal entries store the normalized envelope; the canonical string is recomputed on load. |
| D23 | `start_eva` checks run in this order: site → crew → routes → reserve policy → suit capacity → base stock. |
| D26 | Synthetic config only: EVA crew draw no base water or food, and idle and working base rates are equal. |

**Q-W (decision needed):** what should happen when wastewater storage is full? Revision 3 keeps the contract's explicit, alerted loss sink (`tick:{n}:overflow`, `storage_full`). The CO2 principle from the review may also apply to wastewater, which would mean an accumulator or a blocked-recycling hazard. I recommend keeping explicit loss until a water-system model exists; you may prefer to rule it out now. No fixture reaches that state.

---

## 3. Architecture

### 3.1 Rules (Proposed)

1. **One facade, fixed phases, no framework.** `OutpostSimulation` (Existing API) is the only entry point, and the tick is a hand-written sequence of calls.
2. **Records keep the contract shapes; services are typed classes.**
3. **Working-copy atomicity** (D6).
4. **One ledger; one writer for every balance.** This includes the balance fields inside expedition records and return caches.
5. **No scene access** under `scripts/simulation/` or `scripts/systems/`.

### 3.2 Staged file introduction

A file is created when a test first needs its responsibility, or when a second caller needs code that lives elsewhere. Until then the code stays private inside an existing file.

| Stage | New files | Inline until extracted | Passing fixtures |
|---|---|---|---|
| **1 (A1 first test)** | `scripts/simulation/simulation.gd`, `scripts/simulation/game_state.gd`, `tests/simulation/run_tests.gd` | Definition loading and hash check, clock, result dictionaries, snapshot building | `init/habitat_6crew.json` initializes; snapshot equals `snapshots/habitat_6crew_tick0.json` (including `rng.state` `708718527385777908`); returned snapshots are detached; `step(0.5)` → `invalid_timestep`; scale 0 advances nothing. |
| **2 (A1 commands)** | `scripts/simulation/command_journal.gd` | `set_time_scale` and `set_building_enabled` handlers | Submission cases in `placement_and_save` (`duplicate`, `command_id_conflict`, `invalid_schema`); the first command of `power_loss_and_restore`. |
| **3 (A2–A3)** | `scripts/simulation/resource_ledger.gd`, `scripts/simulation/tick_runner.gd` | Power, process, demand and finalize as private functions; an empty crew stub in the test file | `habitat_{5,6,9}crew_balance`, `power_loss_and_restore`. |
| **4** | `tests/simulation/stub_world.gd`, `tests/simulation/stub_crew_adapter.gd`, `scripts/simulation/command_resolver.gd` (extracted when the facade passes three handlers) | Proposal validation | `placement_and_save` up to `export_save`. |
| **5** | `scripts/simulation/save_codec.gd` | — | All of `placement_and_save`. |
| **6** | `scripts/simulation/proposal_validator.gd` (extracted when both command resolution and phase 6 need it) | — | `eva_salvage_lifecycle`, `eva_recall`. |

Later extraction triggers:

- `scripts/systems/<phase>_system.gd`: a phase passes about 150 lines or gets tests of its own.
- `environment_system.gd`, `hazard_system.gd`: when A5 starts.
- `forecast_system.gd`: alerts pass about 100 lines.
- `snapshot_builder.gd`: when the save codec needs the same assembly.
- `definitions.gd`: definition validation passes about 150 lines.
- `canonical_json.gd`: a second user of canonical encoding appears.
- `records.gd`: record construction is duplicated across files.

### 3.3 `GameState` (Proposed)

```gdscript
class_name GameState
extends RefCounted

var campaign_id: String
var tick_index: int = 0
var time_scale: int = 1
var accumulator_s: float = 0.0
var revision: int = 0
var map: Dictionary
var definition_manifest: Dictionary

var rng := RandomNumberGenerator.new()
var rng_seed_text: String
var id_counters: Dictionary[String, int]

var next_receive_sequence: int = 1
var command_journal: Dictionary              # id -> {normalized, receive_sequence, status, result}
var pending_command_ids: Array[String] = []
var committed_effects: Dictionary            # persisted completion markers only (D1)

var resources: Dictionary                    # id -> {id, amount, net_rate_per_s}; energy derived
var per_battery_energy: Dictionary[String, float]
var buildings: Dictionary
var sites: Dictionary                        # remaining_cargo written only by the ledger
var active_events: Dictionary
var scheduled_events: Array[Dictionary]
var technology: Dictionary
var prepaid_build_costs: Dictionary
var crop_cycles: Dictionary
var power_summary: Dictionary
var alerts: Dictionary

var crew: Dictionary                         # Task 03 transitions, stored here
var tasks: Dictionary
var expeditions: Dictionary                  # suit_stores/cargo written only by the ledger
var crew_tasks_private: Dictionary           # return_caches (ledger), completion_markers, private_counters (D2)

func clone() -> GameState: ...
```

### 3.4 Clock and flushing (Existing rules)

```gdscript
func advance(real_delta_s: float) -> Dictionary:
    if not _initialized: return _fail("not_initialized", "")
    if not is_finite(real_delta_s) or real_delta_s < 0.0:
        return _fail("invalid_value", "real_delta_s must be finite and >= 0")
    var changed := _boundary()
    _flush_outbox()                                  # after the boundary
    _state.accumulator_s += real_delta_s * float(_state.time_scale)
    var ran := 0
    while _state.time_scale > 0 and _state.accumulator_s >= 1.0 and ran < 120:
        if ran > 0:
            changed = _boundary() or changed
            _flush_outbox()
            if _state.time_scale == 0: break
        var outcome := _tick_runner.run_one(_state)
        if not outcome.ok:
            _emit_state_if(changed)
            return outcome.result                    # accumulator retained
        _state = outcome.state
        _state.accumulator_s -= 1.0
        _outbox.append_array(outcome.events)
        _flush_outbox()                              # after each tick
        ran += 1
        changed = true
    _emit_state_if(changed)                          # once per public call
    return _ok()
```

`step(1.0)` does the same with one boundary and at most one tick. Events from a failed tick are discarded along with that tick's copy.

### 3.5 Commands (Existing two-stage model)

- **Submit** checks the schema and does not claim the ID on failure. It then normalizes the envelope, compares it against the journal (duplicate or conflict), and stores `{normalized, receive_sequence, status, result}`.
- **Resolve** runs each captured ID in receive order against a cloned working copy, which is committed only on success. The result is recorded whether or not the command succeeds; result events are queued, and the boundary flushes them (§3.4).
- Handlers re-validate everything, call the world service or adapter where the contract says, spend only through the ledger, and allocate IDs last (building before task; expedition before task).

### 3.6 Snapshots

A snapshot is assembled from `GameState` and returned as a per-revision cached deep copy. Because the balances live in the records themselves, nothing needs to be overlaid at build time. `energy_kwh.amount` is the battery sum. Accumulators report `capacity: null`.

### 3.7 Ledger (Proposed; `resource_ledger.gd`)

Every account path resolves to a field of an existing record:

| Path | Authoritative field | Capacity |
|---|---|---|
| `base/<id>` | `resources[id].amount` | Storage: scenario + commissioned buildings. Accumulator: none. |
| `base/energy_kwh` | `per_battery_energy` (dispatched across batteries by ID) | Sum of battery capacities |
| `suit/<expedition>/<crew>/<oxygen_kg\|battery_kwh>` | `expeditions[e].suit_stores[c][k]` | Crew definition suit capacity |
| `cargo/<expedition>/<id>` | `expeditions[e].cargo[id]` (key removed at zero) | Summed crew carry capacity |
| `return_cache/<expedition>/<id>` | `crew_tasks.state.return_caches[e][id]` | None (holding area) |
| `site/<site>/<id>` | `sites[s].remaining_cargo[id]` | Decrease only |
| `external/<kind>/<owner>` | Not stored; marks where a flow enters or leaves the modeled colony | — |

The external kinds are `process`, `metabolism`, `generation`, `curtailment`, `idle_power_loss`, `battery_loss`, `leakage`, `vent_loss`, `capacity_overflow_loss` and `construction`. `capacity_overflow_loss` is never valid for an accumulator.

Application order:

1. Check the effect ID against the persisted marker or the current tick's scope (D1).
2. Validate units, finiteness and whole counts.
3. Transfer kinds must balance per resource; other kinds must name an external leg.
4. Check all debits against availability and all credits against capacity, skipping the capacity check for accumulators. Nothing is clamped.
5. Apply every leg.
6. Record the marker.

### 3.8 Tick phases (Existing)

`run_one` clones the state and runs the contract's eight phases:

1. Environment.
2. Intent: `plan_tick`, `dt_s = 0`.
3. Power dispatch.
4. Processes, in descending `process_priority`, then building ID.
5. Crew demand: base stores or the crew member's own suit; unmet needs.
6. Progress: `plan_tick`, `dt_s = 1`, then validate (§3.9) and commit.
7. Losses and hazards, using accumulated CO2; then `evaluate_hazards`.
8. Finalize: commission, `tick_index + 1`, `revision + 1`, rates, capacities, alerts, invariants, events.

### 3.9 EVA progress ownership (D17)

Task 03 proposes full expedition records in phase 6, and in `start_eva` and `recall_eva` command proposals. Task 01 rejects the whole proposal unless all of the following hold:

1. `suit_stores` and `cargo` equal their input values. Only linked resource requests change them.
2. At most one status transition per tick. Allowed transitions:
   - `outbound → working`, on arrival;
   - `working → returning`, when work is complete or after a recall command;
   - `outbound → returning`, after a recall command;
   - `returning → completed`, on arrival at base;
   - any non-terminal status `→ stranded`, when there is no route;
   - `→ failed`, under the data-driven exhaustion policy.

   Terminal statuses never change.
3. `route_progress_m` does not decrease on an unchanged `route_id`, increases by at most `min crew speed × dt`, and never exceeds `route_distance_m`. A new `route_id` is allowed only together with a recall or a working-to-returning transition. It must match `world_service.query_route` from the current position (Task 01 re-queries), and progress restarts at 0. Mid-segment backtracking is charged as the contract §10 rule describes.
4. `work_completed_s` increases only while the status was `working` at the start of the tick, by at most `dt`, capped at `work_required_s`.
5. Crew with unmet critical needs earn no work for that tick. Travel is still allowed, so that a team can come home.
6. `salvage_collect` is accepted only with `working → returning` after work completion. `cargo_return` and `eva_return` are accepted only with `returning → completed`. Each carries its persisted marker.
7. After commit, Task 01 sets `tasks[task_id].completed_work_s = work_completed_s`.

### 3.10 Save/load (`save_codec.gd`)

- **Export:** only at a boundary. Writes the core keys, including the D3 additions, and puts crew, tasks, expeditions (with authoritative balances) and private records under `subsystems.crew_tasks.state`.
- **Import:** builds a candidate state, checking in order: envelope and versions, manifest equality, integer casts, the energy-sum check, references and invariants, then `validate_state`. Only then does it swap state and call `restore_state`. The RNG is restored as `seed` then `state`.
- **Extension points:** a new core key (with a `save_version` bump); `register_subsystem(key, adapter)` at initialization; a future migration chain.

---

## 4. Integration examples (each backed by a fixture)

### 4.1 Placement (`scripts/placement_and_save.json`)

1. **Tick 0 submissions.** Valid placement `000001`, same-cell `000002`, unaffordable `000003`, and a queued duplicate of `000001`. Two more are rejected at submission: a conflicting reuse of an ID, and a schema failure.
2. **Boundary.** `000001` spends 2 alloy under the persisted `cmd:fixture:000001:build_cost` and creates `building_000006` and `task_000001`. `000002` fails with `placement_blocked`; `000003` fails with `insufficient_resources`. One boundary flush carries `event_000001..3`.
3. **Construction.** `crew_000003` is assigned. Each later tick, Task 03 supplies 1.0 work_s of labor and Task 01 applies it once (D5).
4. **Completion.** Interval 10 reaches 10/10. Phase 8 records the persisted `core:task_000001:commission` and emits `building_commissioned` and then `task_completed` in that tick's flush (`placement_commissioned_tick11.json`). The crew member is released at interval 11.

### 4.2 EVA (`scripts/eva_salvage_lifecycle.json`, `scripts/eva_recall.json`)

1. **Two rejected launches.** 0.25 kg passes the reserve policy but fails with `capacity_exceeded`; 0.10 kg fails with `reserve_insufficient`.
2. **Valid launch.** 0.12 kg O2 and 0.006 kWh per crew member. Task 01 creates the expedition record with zero suit stores, then applies one `eva_load` transfer that writes `suit_stores` directly (persisted `crew_tasks:expedition_000001:eva_load:0`).
3. **During the EVA.** Phase 5 debits each crew member's `suit_stores` every tick. Phase 6 validates Task 03's progress (§3.9).
4. **Timeline.** Arrival at tick 10; salvage at tick 30 (alloy 4, electronics 2); home at tick 40, with cargo and remaining suit stores transferred once.
5. **Recall.** A recall at tick 15 returns the team without salvage, arriving at tick 25 with the task `cancelled`. A second recall while returning is a successful no-op. A recall after completion fails with `invalid_state`.

### 4.3 Power loss (`scripts/power_loss_and_restore.json`)

| After tick | Battery kWh | Served | Notes |
|---|---|---|---|
| 4 | 0.003 | 2.0 kW from generation; +1.0 kW charging | Four ticks of +0.00025 from a 0.002 start |
| 5–8 | 0.003 → 0.000531 | 2.0 kW from the battery | Generator disabled at the tick-4 boundary; −0.000617 per tick |
| 9 | 0 | 1.72 kW: scrubber 0.5, electrolyzer 1.0, recycler 0.22 (`partial_power`) | The last stored energy, allocated by power priority |
| 10–20 | 0 | 0 | All loads `no_power`; O2 −0.006 per tick; **CO2 +0.006 per tick (accumulates to 0.566)** |
| 21 | 0.00025 | 2.0 kW from generation | Generator re-enabled at the tick-20 boundary |

When a process gets zero power, no transaction is applied, so water is untouched while the electrolyzer is off.

### 4.4 Save and restore (`saves/placement_mid_job_tick6.json`)

The save is taken at the tick-6 boundary. It holds task progress 5/10, accumulator 0.4, a pending recycler-disable command, the journal, one persisted marker, the prepaid cost record, and `rng.state` `708718527385777908`. It is restored into a fresh instance, which must reproduce `snapshots/placement_mid_job_tick6.json` with no flushes. The original and restored instances then run `advance(0.6)` plus five `advance(1.0)` calls and must match `placement_after_tick12.json`. The reference model confirms this equivalence. A retry of `000001` after loading still returns its cached result.

---

## 5. Ownership of every deduction and reward

| Flow | Phase | Owner | Effect ID | Retention |
|---|---|---|---|---|
| Build cost | `place_building` | resolver | `cmd:{command_id}:build_cost` | persisted |
| Construction refund | `cancel_task` | resolver | `core:{task_id}:construction_refund` | persisted |
| Commission | 8 | tick runner | `core:{task_id}:commission` | persisted |
| Repair completion | 8 | tick runner | `core:{task_id}:repair_complete` | persisted |
| Crop yield | 4 | process | `core:crop:{building_id}:{cycle_id}` | persisted |
| Generation, charge, discharge, curtailment | 3 | power | `tick:{n}:power` | tick-scoped |
| Process inputs and outputs, idle loss | 4 | process | `tick:{n}:process:{building_id}` | tick-scoped |
| Base metabolism (CO2 accumulates) | 5 | crew demand | `tick:{n}:metabolism:{crew_id}` | tick-scoped; sole creator |
| Suit O2 and battery use | 5 | crew demand | `tick:{n}:metabolism:{crew_id}`, `tick:{n}:suit_power:{crew_id}` | tick-scoped |
| Suit loading | `start_eva` | Task 03 proposes, resolver commits | `crew_tasks:{e}:eva_load:0` | persisted |
| Salvage site → cargo | 6 | validator | `crew_tasks:{e}:salvage_collect:0` | persisted |
| Cargo → base | 6 | validator | `crew_tasks:{e}:cargo_return:0` | persisted |
| Suit stores → base | 6 | validator | `crew_tasks:{e}:eva_return:0` | persisted |
| Return-cache drain | 8 | tick runner | `tick:{n}:return_cache:{e}:{id}` | tick-scoped |
| Leakage | 7 | hazards | `tick:{n}:leakage` | tick-scoped |
| Storage-resource overflow | 8 | tick runner | `tick:{n}:overflow:{building_id}` | tick-scoped (never for an accumulator) |
| Construction and repair work | 6 | Task 01, from labor | record field | one application per tick |
| EVA travel and work | 6 | Task 03 record, validated by §3.9 | record field | one transition per tick |

---

## 6. Fixtures

See [`tests/simulation/fixtures/README.md`](tests/simulation/fixtures/README.md). The set contains:

- 3 scenarios;
- 5 init configs (5, 6 and 9 crew);
- 7 scripts;
- 27 full snapshots;
- 1 save record;
- stub world responses.

Verification so far:

- The Python reference model, kept outside the repository, produced the expected values. Closed-form totals were checked by hand. Save continuity (uninterrupted vs restored) gives identical snapshots and saves.
- Local Godot 4.7.2 parsed all 55 JSON files, and `FileAccess.get_sha256` reproduced every manifest hash.
- The Godot checks also confirmed numeric JSON parsing and the seed-42 RNG state.

No simulation GDScript exists, so the scripts themselves have not run in Godot.

## 7. Assumptions

1. Godot 4.7.2 behavior was verified for typed `Dictionary[K, V]`, `JSON.stringify(data, "", true, true)` (sorted keys, full precision), float-only JSON numbers, `FileAccess.get_sha256`, and `RandomNumberGenerator` seed/state.
2. Scale is at most 9 crew and about 100 buildings, so per-transaction cloning should be affordable (benchmark at stage 3).
3. Adapters and the world service are deterministic and pure (Existing).
4. One shared power and resource network (Existing v1).

## 8. Questions for contract reconciliation

1. Accept D1, D2, D3, D4, D5, D8, D13, D17 and D24 (§2.1), or name the changes needed so the fixtures can be regenerated.
2. **Q-W:** should overflowing wastewater stay an explicit alerted loss, or should it never be discarded, like CO2?
3. D13 makes `capacity` nullable. Do you prefer that, or a separate `capacity_policy` field in `ResourceBalance` with a numeric placeholder?
4. Will Tasks 02 and 03 accept the proposed map, crew-definition and task-template shapes, and the `route_id` hashing scheme?
5. May Task 01 create `data/scenarios/` and `data/science/` once real values exist?
6. Should the Python reference generator be committed (for example under `tests/simulation/tools/`) so that fixtures can be regenerated after reconciliation?

### Note required by `AGENTS.md`

Deep research would materially improve the oxygen, water and CO2 backend before A3 adopts real parameters. That covers crew consumption and output by activity, electrolysis and water-recovery ratios, suit budgets, habitat leakage, cabin CO2 thresholds, and the sol length. As you noted, it does not block A1 with labeled synthetic inputs. I have not started it.
