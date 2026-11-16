# Campaign contract and integration boundaries

## Implemented foundation

Integration baseline: `5d33c7b` (PR #10), workspace `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`, branch `overhaul/living-colony-pr10`. Read `docs/TIME_AND_MISSION_HANDOFF.md` and `docs/MISSION_TASKS_AND_FRAME_PACING.md` before changing pacing or mission UI. The existing title/customizer/intro, task panel, placement cache and 8 ms budgeted backend are retained.

`scripts/campaign/campaign_simulation.gd` subclasses the existing transactional simulation. Initialize it with the same hash-verified config/world/crew-adapter inputs as the v2 facade. Its snapshot advertises `contract_version: "3.0.0"`, `snapshot_version: 3` and an added `campaign` partition. All existing handlers and the ledger remain authoritative.

V3 command envelopes retain `{contract_version, command_id, type, payload}`. The foundation accepts only the existing command shapes, requiring version 3.0.0 externally. Internally it translates their version to 2.0.0 before the existing dispatcher journals them. The internal journal therefore contains normalized v2 envelopes. Do not translate saved journals back to v3 or bypass their deduplication. Feature packages must add a v3 command validator/dispatch path for new commands; do not make the old validator accept arbitrary payloads.

Capabilities currently say `campaign_foundation: true`, `persistence: true`, `fast_forward: true` (package 2), `campaign_gameplay: false`, `medical: false`, and `repair_challenges: false`. Agriculture remains false. Package 2 also reports `owns_time_pacing`, `time_integration_mode` and a `time_integration` map naming each registered time system as `aggregate` or `detailed_fallback`. No feature may enable its capability until a production path and tests exist. The default scene/bridge still use the old facade; opt-in v3 scene integration belongs to package 3, and default launch changes at package 7.

`campaign_schema.gd` creates the initial partition:

- Calendar: 86,400-second day, 30-day month, 180-day supplies, 720-day campaign.
- Commander: first starting crew ID until package 4 adds selection.
- Camp level 0, zero research, no unlocked research.
- Empty zones, needs, schedules, medical episodes, maintenance, repairs, crops, upgrades and discoveries.
- Cargo: next arrival at 15,552,000 seconds, no deliveries or discretionary orders yet, empty unloading queue.
- Event director: first check at 86,400 seconds, empty cooldown/history.
- Tutorial: arrival stage, active, no completed steps.
- Standing orders: meals and sleep allowed during explicit fast-forward.

The partition is `schema_version: 2`: package 2 added the `time` record described under *Implemented time and scheduler*. Package 1 intentionally rejects populated future partitions. As each package implements a partition, replace that empty-only validation with its strict schema and tests. Add an explicit migration from the preceding empty partition if earlier development checkpoints must remain readable. Do not erase unrecognized state or invent values silently.

## Checkpoint API

- `export_save()` returns a detached full `mars-outpost-campaign` envelope with save version 3, including state, config/manifest, command journal, pending receive order, receipts, counters, fractional accumulator, adapter capability and exact RNG seed/state.
- `import_save(record)` validates off to the side, constructs the candidate adapter, then swaps all runtime state together. Failure changes nothing. Success emits one snapshot and replays no historical events/results/rewards.
- The supplied world must match the save's map. The wrapper must construct another world before importing a checkpoint for another map.
- Save during a tick/callback is rejected. Schedule autosaves at an outer boundary.
- Godot's exact engine version is retained and checked because RNG continuity is not promised across engine versions.
- Seed/state are decimal int64 strings. Floating-point values are represented in checkpoint JSON as `{"$f64":"<16 hex characters>"}` using Godot `encode_double` bytes. The codec restores their exact values/types; never parse them as decimal or replace the codec with a raw snapshot dump. `$f64` is reserved for this encoding.
- V2 checkpoints are not migrated by this implementation. Unsupported schemas/versions fail explicitly.

`campaign_save_store.gd` supports `manual`, `auto_0`, `auto_1`, `auto_2` under `user://campaign_saves`. It verifies a temporary write, preserves previous primary bytes in `.bak`, then replaces the primary by rename. Reads can recover a valid backup. Auto slots choose the oldest/missing slot. UI triggers, autosave timing, cross-map loading and browser host persistence belong to later integration packages. Native file behavior is covered by tests; web persistence is not yet verified.

## Ownership

| Concern | Sole authority |
|---|---|
| Inventories, debits, credits, overflow and refunds | Existing resource ledger, extended with declared accounts |
| Clock, seeded outcomes, commands, IDs, completion and save/load | Simulation facade |
| Logical placement, habitat topology, movement and route revisions | Headless world service from committed state |
| Work/meal/bed reservations and needs/medical outcomes | Simulation-owned campaign systems |
| Challenges | Simulation-owned session; UI sends input, never `success=true` |
| HUD, cameras, meshes and animations | Presentation derived from snapshots |

Health and fatigue remain on the existing crew record. New needs/episode records reference crew IDs; do not create second authoritative copies of those stats. Building condition remains on the building record. Repair records reference that building and hold attempt/cooldown state.

## Upcoming command families

Use these names as the integration vocabulary, adding strict payload definitions in the package that introduces them:

| Package | Commands and primary identifiers |
|---|---|
| 2 | `request_fast_forward(target_elapsed_s)`, `cancel_fast_forward()` |
| 3 | `place_wing`, `place_furnishing`, `connect_utility`, `commission_zone`, `set_zone_isolated` |
| 4 | `select_commander(crew_id)`, `move_commander`, `interact`, `set_schedule`, `set_role_priority`, `set_standing_orders` |
| 5 | `plant_crop(building_id,crop_id)`, `set_seed_propagation`, `assign_treatment`, `request_rescue` |
| 6 | `prepare_repair(building_id,crew_id)`, `repair_input(session_id,action,value)`, `set_challenge_accessibility` |
| 8 | `start_survey`, `accept_contract`, `resolve_event_choice`, `start_cross_training` |
| 9 | `start_research`, `install_upgrade(building_id,tier,specialization_id)`, `set_cargo_manifest` |
| 10 | `acknowledge_tutorial`, `skip_tutorial` |

New resource units, accounts, record fields, deterministic phase order and payload shapes must be documented and validated together. Preserve existing command ordering, rollback and retained receipt behavior. Never debit a meal or crop outside the ledger.

## Time integration contract

Package 2 retains the detailed one-second oracle and adds a scheduled-boundary abstraction. No feature may use frame delta or wall clock to advance survival. Each system reports its next transition and whether it can safely integrate a stable interval. Unsupported intervals use detailed stepping; never jump over unmodeled behavior. Expose unsupported/slow paths honestly until implemented.

PR #10 already provides `advance_budgeted(real_delta_s,max_work_usec)` and retained backlog in the base facade. Its wrapper uses 60/120/240 simulated seconds per real second for legacy normal/fast/fastest play. Reuse those protections. Apply the proposed 120x normal pace only to the new campaign, and avoid applying both wrapper pacing and a second campaign multiplier to the same elapsed time.

For a shared boundary: process received commands, calendar/deadlines, topology/availability, intent and reservations, power, production/crop transitions, metabolic demand, travel/labor/medical progress, incidents, completions and alerts. Document any intentional change from v2 ordering. Resolve instantaneous consequences before selecting the next interval. No same-boundary production may finance a debit that precedes it.

Fast-forward ends on danger, repair readiness, lack of treatment capacity, shipment/deadline, tutorial milestones or its requested target. Its stop reason is in the snapshot. Colony time is frozen during active repair challenges; challenge timers consume bounded active real-time input supplied by the wrapper, paused when unfocused. Seed all challenge generation and retain input sequence numbers.

Stable-interval integration must match detailed stepping within explicit absolute/relative tolerances for continuous quantities and exactly for discrete outcomes, IDs, event ordering and RNG draws. Where a nonlinear model prevents aggregation, use detailed stepping; do not loosen tests or call skipped work an optimization.

## Implemented time and scheduler (package 2)

Code: `scripts/campaign/campaign_simulation.gd` (run loop and replay), `campaign_calendar.gd`, `campaign_scheduler.gd`, `campaign_commands.gd`, `campaign_time_hook.gd`, `campaign_time_hooks.gd`, `campaign_tape_ledger.gd`. The v2 facade gained overridable seams only (`_validate_command`, `_command_supported`, `_apply_command`, `_new_ledger`, `_tick_candidate`/`_commit_tick`, `_extra_tick_phases`); its behaviour and tests are unchanged.

### Profile and pacing

A campaign config may add `campaign_profile_path`, which must be listed in `definition_manifest` (hash-verified). `data/campaign/time_profile.json` sets 120 simulated seconds per real second, multipliers 1/5/20 (the existing `set_time_scale` values; 0 is pause), a paused start and the per-call work budgets. The facade applies `real_delta x multiplier x base rate` itself and reports `owns_time_pacing: true`; `SimulationBridge.paced_delta` then passes real seconds, so the wrapper's legacy 60/120/240 pacing is never applied on top. Without the key the facade keeps fixture semantics: rate 1, running start, at most 120 ticks per call, wrapper pacing as before. A checkpoint carries its config, so it restores its own profile.

### Calendar and scheduled boundaries

`get_calendar()` derives mission day, month, day of month, time of day, shipment cycle, next arrival and next order deadline from the committed clock. Nothing calendar-derived is stored twice.

`campaign.time` is `{schema_version: 1, profile_id, base_rate, queue, next_sequence, fast_forward}`. `queue` holds pending boundaries `{id, due_tick, phase, sequence, kind, payload}`, strictly ordered by `(due_tick, phase, sequence)`. Every entry is strictly in the future: an advancing call always finishes the boundary it reaches before returning. Built-in kinds: `day_start` (phase 0, emits `calendar_day` and, on day 1 of a month, `calendar_month`), `shipment_order_deadline` (phase 10, 30 days before arrival, emits `shipment_order_deadline`) and `shipment_arrival` (phase 20, every 180 days, emits `shipment_due`). They reschedule themselves. Package 9 owns manifests and delivery; the `cargo` and `director` records are still the untouched foundation templates.

Feature packages register `register_boundary_handler(kind, handler, payload_validator)` before loading a checkpoint that uses the kind, and schedule with `Scheduler.schedule(time, due_tick, kind, payload, phase)` inside their own transaction (default phase 500; `schedule_boundary` exists for outer-boundary callers). A handler receives the working copy and the entry, may draw from `state.rng`, schedule more entries and return `{ok, events, stop}`. Each entry is one committed transaction; its events get IDs in firing order. A checkpoint naming an unregistered kind is rejected. Random outcomes are drawn only in these handlers or in ticks, never per rendered frame.

### Boundary order

At each whole tick: (1) received commands in receive order, (2) due scheduled boundaries, (3) fast-forward stop checks, repeated until no command is pending, then (4) the next interval. Inside a detailed tick the v2 phase order is unchanged (intent, power, life support, metabolic demand, crew progress), followed by registered hooks' `detailed_interval`, then diagnostics, alerts and events. Intentional change from v2: commands submitted from event callbacks now resolve at the boundary that was just reached, in the same call, rather than at the start of the next call. Their `resolved_tick` is the same; results no longer depend on how a wrapper splits frames.

### Commands

`request_fast_forward {target_elapsed_s}`: whole simulated seconds, 1 to 2^53-1; any other key, type or value is rejected at submission. On resolution the target must be later than the clock (`invalid_value`) and no fast-forward may be active (`invalid_state`). Success commits `{active, target_tick, started_tick, command_id}` and emits `fast_forward_started`. `cancel_fast_forward {}` stops an active one (`data.cancelled: true`) and is a successful no-op otherwise. Both are journaled as normalized 3.0.0 envelopes and deduplicate across reload like every other command.

A fast-forward advances toward its committed target on every `advance`/`advance_budgeted` call regardless of the real delta and of pause, and leaves the fractional accumulator untouched. It ends with `fast_forward.stop_reason`, `stop_detail` and `stopped_tick` in the snapshot plus one `fast_forward_stopped` event: `target_reached`, `cancelled`, `paused` (a `set_time_scale 0` command), `danger` (a detailed tick raised a new alert or a new unmet crew need), `deadline`, `shipment`, `scheduled` (a registered boundary asked) or `error`. Danger outranks a scheduled stop, which outranks the target. Repair readiness, treatment capacity and tutorial milestones are stop sources their packages add through boundary handlers or the danger check.

### Detailed oracle and stable-interval replay

The detailed one-second tick is the oracle: `set_time_integration("detailed")` uses nothing else, and `step(1.0)` is always one detailed tick. In `auto` mode a stable interval is replayed instead:

1. Every detailed tick records its **tape**: the per-account `(debits, credits)` sums the real ledger applied, in commit order.
2. An interval may start only after a detailed tick that left the discrete state unchanged, emitted no events and applied only per-tick effects on base resources and batteries.
3. Every hook must certify the interval and report its next transition. The interval ends a guard band (2 ticks) before the earliest predicted transition, the next scheduled boundary, the target, or the frame budget.
4. The kernel re-applies the ledger's own arithmetic, `amount - debits + credits`, per effect per tick for each changing account. It does not use a closed form: `n x rate` rounds differently from n additions and could move a saturation by one tick.
5. The **real** tick then runs as the last tick of the interval. The interval commits only if that tick reproduces the reference tape and discrete state exactly and emits nothing. Otherwise nothing is committed, the attempt halves, and a detailed tick leads.

Because the dynamics are piecewise linear with convex regions and both ends of the interval lie in the same region, the replayed interior equals detailed stepping bit for bit. Declared tolerance for continuous quantities is therefore abs 0 / rel 0; IDs, events, commands and RNG state are identical. Replay is linear in ticks with a small constant, not O(1).

Hook interface (`campaign_time_hook.gd`, registered with `register_time_hook`): `next_transition(context)`, `detailed_interval(candidate, ledger)` and `aggregate_interval(context)`. The defaults refuse aggregation, so an unmodeled system forces detailed stepping and appears as `detailed_fallback` in capabilities and by reason in `get_time_stats().fallback_reasons`. Built-ins: ledger margins (reserve exhaustion, storage and battery saturation), power (`battery_low`), life support (`low_oxygen`, `co2_high`), crew demand, and crew activity. Crew travel, labor, expeditions and return caches are **not** aggregated: they use detailed stepping until the crew is idle.

`get_time_stats()` reports detailed ticks, replayed intervals and ticks, rejected intervals, fallback reasons and the maximum work in one call. It is diagnostic and never saved, so oracle and replay checkpoints are identical.

### Frame work

`advance_budgeted(real_delta_s, max_work_usec)` keeps PR #10's rule: finish at least one unit, then yield once the wall-clock budget is spent. The campaign profile additionally caps each call at 8 detailed ticks and 50,000 replayed account-ticks; replay sizes itself to the remaining wall-clock budget. Unfinished time stays in the accumulator or in the committed fast-forward target. Different frame splitting gives identical results when the deltas are identical. The fractional accumulator is one binary64: with non-representable deltas and a retained backlog its last bit can depend on how additions interleave with whole-tick subtraction, as in v2.

### Persistence and migration

The checkpoint envelope is unchanged (save version 3). Accumulator, queue, sequence counter, fast-forward record, journal and RNG are saved; the replay reference is transient and a reload costs one detailed tick with identical results. `campaign.time` is validated strictly (fields, ordering, identities against the counter, calendar boundaries against the clock, fast-forward consistency, profile). Development-save policy: a foundation checkpoint with partition `schema_version: 1` and no `time` record is migrated on import by adding the default time record for its own tick; `import_save` reports `migrated_from: 1`. Any other shape or version is rejected. `data/campaign/content.json` did not change, so its hash still matches foundation saves.

## Content boundary

`data/campaign/content.json` is version 1 authored gameplay starting data. It is not a legacy building definition manifest and must not be passed directly into the v2 definition loader. Package 3 implements the campaign loader and verifies its hashes/definitions. Later packages extend fields with units, costs, prerequisites and modifier semantics. Until then, it is a catalog proposal and save compatibility fingerprint only.

The time profile is a separate hash-verified file selected by the campaign config. Changing content currently rejects old foundation saves by hash. A feature package that changes content must explicitly version/migrate its development saves or document the intentional reset; never pretend old saves remain supported.
