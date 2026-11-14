# Mars Outpost — shared simulation contract

**Contract version: 1.0.0. Status: implementation baseline; runtime not yet implemented.**

All three tasks implement this contract. It makes the design choices left open in `PRD.md` section 6. Where an older planning document differs, this contract governs interfaces and simulation behavior. It does not override the user's product requirements or reinstate the research report's scope limits.

Examples use synthetic quantities to demonstrate interfaces, not adopted NASA performance values. Actual science parameters require entries in `SCIENCE.md`. Engine target: the team's selected Godot 4.7.2 standard/GDScript edition; Task 02 owns project/export configuration.

## 1. Ownership and dependency rules

| Owner | Implements | Must not do |
|---|---|---|
| Task 01 | Clock, command dispatcher, state, resource ledger, power/production, environmental effects, forecasts, persistence | Depend on visible scenes or implement crew scheduling/path presentation |
| Task 02 | Building definitions, immutable map data, placement/routing queries, building/world scenes, main-scene integration | Spend resources or move authoritative crew through rendered transforms |
| Task 03 | Crew/task/EVA state transitions, labor contributions, UI/crew scenes and save adapter | Directly alter resource balances, run a second clock, or deduct metabolism separately |

Task 01 owns `scripts/simulation/` and `scripts/systems/`. Task 02 owns `scripts/world/` and `data/buildings/`. Task 03 owns `scripts/crew/` and `scripts/tasks/`. Each owner implements its own harness/tests. One integrator (Task 02) wires the runtime and scenes together. Do not add a server, network protocol, generic plugin framework, or new library to satisfy this contract.

Tasks 02/03 develop against fixture snapshots and stub services until Task 01's facade exists. Fixtures must match the shapes below. A stub must reject unsupported operations explicitly, rather than return false success.

## 2. Types, units, IDs, and definitions

- Public records are JSON-compatible dictionaries, arrays, strings, booleans, finite numbers, and explicit `null`. No Node, Resource, Callable, Vector, or other engine object appears inside a record. GDScript implementations may use typed internal classes.
- Fields are `snake_case`. IDs are case-sensitive strings. Required keys are always present; nullable fields use `null`, never an empty string sentinel.
- Quantities use kilograms (`kg`), energy uses `kwh`, power uses `kw`, distances use meters (`m`), durations use simulated seconds (`s`), angles use integer quarter turns. Food inventory uses `food_kcal`; materials use whole item counts. Every resource has one immutable declared unit.
- World coordinates are `[x, y, z]` in meters, with Y up. Simulation navigation uses integer `[x, z]` cells, one meter per cell, anchored at world origin. Crew position is derived from authoritative route progress, not scene physics.
- A sol is a configured number of simulated seconds recorded in `SCIENCE.md`. Per-day science inputs must declare their source time basis and be converted once during definition loading. Runtime rates are per simulated second. Never divide a per-Earth-day value by a Martian-sol duration implicitly.
- All numeric inputs must be finite and within declared bounds. Reject negative amounts/durations and unknown enum values. No NaN/Infinity or arbitrary unvalidated keys.
- Runtime IDs are allocated by Task 01: `building_000001`, `crew_000001`, `task_000001`, `expedition_000001`, `event_000001`. Each type has a saved monotonically increasing counter. IDs are never recycled. Definition IDs such as `water_electrolyzer_mk1` and map site IDs are authored, not allocated per tick.
- `command_id` is caller-generated and globally unique within a campaign, such as `ui_session_01:000001`. It does not consume simulation RNG. `campaign_id` identifies the save lineage; callers discard pending UI command IDs when loading a different lineage or older checkpoint.
- Dictionary iteration order is not simulation order. Sort entity/definition IDs lexicographically wherever the order can affect a result. Sequence counters and tick indices must remain exact integers within JSON's safe integer range; reject overflow.
- Cross-platform numeric replay compares floats with absolute tolerance `1e-8` plus relative tolerance `1e-9`. IDs/enums/counters must match exactly. Bit-identical floating-point replay across different engine/platform builds is not promised.

Definitions are immutable after campaign initialization. Store a manifest of content hashes for the map, buildings, crew definitions, event/technology definitions, and science configuration. Save loading requires the same manifest in v1; hot-reloading balance values into a running campaign is unsupported.

## 3. Public simulation facade

Task 01 exposes `scripts/simulation/simulation.gd` with class name `OutpostSimulation`, usable without a rendered scene. An integration Node may forward its signals.

```gdscript
initialize(config: Dictionary, world_service: RefCounted,
    crew_adapter: RefCounted) -> Dictionary
submit_command(command: Dictionary) -> Dictionary
process_pending_commands() -> void
advance(real_delta_s: float) -> Dictionary
step(delta_sim_seconds: float) -> Dictionary
get_snapshot() -> Dictionary
export_save() -> Dictionary
import_save(save_record: Dictionary) -> Dictionary

signal state_changed(snapshot: Dictionary)
signal command_resolved(command_id: String, success: bool, reason: String)
signal game_event(event: Dictionary)
```

The return value for operations other than submission/snapshots/save export is `{ok: bool, code: String, reason: String}`. Codes are stable machine values; `reason` is explanatory text. Success uses `code="ok"`, `reason=""`.

Initialization config requires `campaign_id`, `seed` (decimal string), `initial_crew_definition_ids` (5–9 entries), `map_id`, `map_revision`, and `definition_manifest`. Initial inventories/buildings/sites and science configuration are loaded from the validated scenario definitions referenced by that manifest. Initialization is atomic; a failure leaves the runtime uninitialized. Registrations occur once before play; no module replacement during a tick.

Content paths in the manifest are project-relative resource paths (`res://...`), with SHA-256 file-content hashes as values. Config also requires `scenario_path` and `science_config_path`, both present in the manifest. Task 01 owns these content files under `data/` and publishes a synthetic fixture scenario first. Task 02 supplies the map service initialized for `map_id`/revision. Task 03 receives its crew definitions from manifest-listed files under `data/crew/`. Source/configuration files are loaded during initialization, never from arbitrary save-supplied filesystem paths.

Returned snapshots/records are deep copies. Caller mutation must not affect simulation state. Adapters receive a read-only view by convention and return proposed changes; only the facade commits authoritative state. No adapter retains a mutable reference to live state.

The richer `step` result makes invalid timestep calls reportable; callers following the earlier PRD may ignore the result. No gameplay code outside the facade invokes subsystem ticks independently.

## 4. Time, command boundaries, and pause

### Fixed step

- One simulation tick is **1.0 simulated second**, a game implementation parameter.
- Tick index starts at 0; elapsed time equals `tick_index * 1.0`. An interval updates state from tick N to N+1.
- Allowed time scales: `0`, `1`, `5`, `20`. Zero is pause. These are wall-time multipliers, not changes to the simulation timestep.
- `advance(real_delta_s)` validates nonnegative finite delta, processes one command boundary, then adds `real_delta_s * time_scale` to a saved accumulator. It runs whole one-second ticks while available.
- Cap execution at 120 ticks per `advance` call to avoid locking the main thread. Keep all remaining accumulated time; never silently discard elapsed simulation time. A zero-delta call can drain running backlog.
- `step(1.0)` processes one command boundary and then one tick if running. Other delta values fail with `invalid_timestep`. While paused it processes the boundary but advances no time. Direct stepping does not modify the wall-time accumulator; use it for headless runs, not interleaved with `advance` during normal play.
- Pausing preserves any accumulator/backlog but does not drain it. Resuming continues it. Every executed tick increments tick index once, regardless of render frequency.

### Command boundary

`process_pending_commands()` resolves the queue captured at entry, in assigned receive-sequence order. It runs even while paused and does not itself advance time. Integration calls `advance` every frame, including during pause. Headless clients may explicitly call `process_pending_commands`.

Commands submitted by callbacks during a boundary/tick wait for the next boundary; never recurse into the dispatcher. `advance` also processes a boundary before each subsequent tick in a batch. Flush committed command results and events after their boundary/tick; emit one final `state_changed` snapshot per public advance/step/control call if state changed.

All seven v1 command types may resolve while paused. Placement can spend materials and create a construction job, and EVA launch can transfer suit reserves, but construction, travel, production, metabolism, and hazards do not advance until time runs. Already accepted commands retain FIFO order when a pause/resume command is encountered.

## 5. Commands and responses

### Envelope

```json
{
  "contract_version": "1.0.0",
  "command_id": "ui_session_01:000001",
  "type": "set_building_enabled",
  "payload": {"building_id": "building_000001", "enabled": false}
}
```

Submission performs envelope/schema validation and checks handler availability. It does not promise that gameplay preconditions will still hold at resolution. Accepted submissions only change queue/journal metadata, not colony resources/entities.

```json
{
  "accepted": true,
  "command_id": "ui_session_01:000001",
  "reason": "",
  "code": "ok",
  "receive_sequence": 1,
  "status": "queued",
  "duplicate": false,
  "result": null
}
```

Rejected submissions return the same keys with `accepted=false`, `receive_sequence=null`, `status="rejected"`, and a nonempty code/reason. They do not alter the gameplay state or enqueue a command and emit no resolution signal. Validation failures do not claim the command ID.

At resolution, validate all gameplay preconditions against the latest committed state. Apply effects atomically or apply none. An accepted command resolves exactly once with a persisted result:

```json
{
  "success": true,
  "code": "ok",
  "reason": "",
  "resolved_tick": 0,
  "data": {"building_id": "building_000002", "task_id": "task_000001"}
}
```

Resolution emits `command_resolved(id, success, reason)` and a `game_event` with `type="command_result"` whose `data` contains this full result plus `command_id`. Consumers use the code, not parsed reason text. Completion of a command means its immediate action occurred; it does **not** mean its construction job or expedition has finished.

### Deduplication

Persist each accepted ID, its normalized envelope, receive sequence, status, and result for the campaign. A retry with the same ID and identical normalized content returns the original entry with `duplicate=true`, never enqueues again, and never re-emits a result. A completed retry includes `status="resolved"` and its cached result. Reusing an accepted ID for different content fails with `command_id_conflict`. Canonical normalization sorts object keys and applies the command schema's numeric types; array order remains meaningful. Keep this journal in v1 rather than evicting entries and accidentally permitting repeated rewards.

### Exact payloads

All fields below are required. No command accepts caller-supplied resource rewards, building costs, path lengths, or generation rates.

| Type | Payload | Resolution effect / owner |
|---|---|---|
| `place_building` | `{definition_id: String, cell: [int,int], rotation_quarters: int}`; rotation 0–3 | Task 02 validates map placement. Task 01 atomically spends definition costs, allocates building + construction task IDs, creates an unfinished building, and reserves its footprint. Task 03 handles subsequent labor. Result data: `{building_id, task_id}`. |
| `set_building_enabled` | `{building_id: String, enabled: bool}` | Task 01 changes the operating preference; it does not override damage, commissioning, resources, or power availability. Result: `{building_id}`. |
| `assign_task` | `{task_id: String, crew_ids: Array[String], priority: int}`; unique nonempty crew IDs, priority 0–100, higher first | Task 03 atomically assigns eligible idle crew up to the task's required count. Busy crew must first be released via cancellation; reject partial assignment. Result: `{task_id, crew_ids}`. |
| `cancel_task` | `{task_id: String}` | Task 03 releases crew/reservations and marks a cancellable task cancelled. Expedition-owned tasks reject this command; use recall. A construction cancellation removes its unfinished building/footprint and returns prepaid materials once. No partial labor refunds or salvage rewards. Result: `{task_id}`. |
| `start_eva` | `{site_id: String, crew_ids: Array[String], work_duration_s: number, oxygen_kg_per_crew: number, battery_kwh_per_crew: number}` | Task 03 validates site/crew/routes, carry capacities and return policy. Task 01 transfers the requested total suit oxygen and electrical energy from base stores atomically. Create expedition and its owned task; reserve exclusive site access. Result: `{expedition_id, task_id}`. |
| `recall_eva` | `{expedition_id: String}` | Task 03 changes an outbound/working team to returning using its current position. Already-returning recall is a successful no-op; completed/failed expedition rejects. Result: `{expedition_id}`. |
| `set_time_scale` | `{time_scale: int}`; 0/1/5/20 | Task 01 changes clock scale. Result: `{time_scale}`. |

Automatic task creation: placement creates construction tasks; operating farm buildings expose farming tasks; damaged repairable buildings expose repair tasks; EVA launch creates an expedition-owned task. Task IDs are persisted; these jobs must not be regenerated each frame. Task 03 defines job templates, and Task 01's lifecycle integration requests them. No separate free-form `create_task` command exists in v1.

### Error codes

Use `not_initialized`, `invalid_schema`, `invalid_value`, `unsupported_contract`, `unsupported_command`, `module_unavailable`, `command_id_conflict`, `unknown_entity`, `unknown_definition`, `invalid_state`, `insufficient_resources`, `capacity_exceeded`, `placement_blocked`, `route_unreachable`, `crew_unavailable`, `reserve_insufficient`, `not_cancellable`, `invalid_timestep`, `definition_mismatch`, `incompatible_save`, `invalid_save`, or `internal_error`. A failure includes contextual IDs in the result's `data` where available. Internal exceptions must not leave partial command effects.

## 6. Authoritative state and snapshot shapes

Snapshots have this exact top-level shape; empty collections remain present:

```json
{
  "contract_version": "1.0.0",
  "snapshot_version": 1,
  "campaign_id": "campaign_demo_01",
  "revision": 0,
  "clock": {"tick_index": 0, "elapsed_s": 0.0, "time_scale": 1},
  "rng": {"seed": "42", "state": "42"},
  "map": {"id": "landing_plain", "revision": 1},
  "resources": {},
  "power": {"generated_kw": 0.0, "requested_kw": 0.0, "served_kw": 0.0,
    "battery_stored_kwh": 0.0, "battery_capacity_kwh": 0.0},
  "buildings": {},
  "crew": {},
  "tasks": {},
  "expeditions": {},
  "sites": {},
  "technology": {"unlocked_ids": []},
  "active_events": {},
  "alerts": []
}
```

The empty collections illustrate structure, not a valid initialized colony. `revision` increases once per state-changing command and once per completed tick; no-op commands do not increase it. Resource/power rates describe the last completed tick and must be marked stale in UI if a later command changed operating conditions. Queues, fractional accumulator, transaction journals, and RNG implementation metadata belong in saves, not presentation snapshots. Snapshot RNG fields are decimal strings, preserving 64-bit values through JSON.

### Record schemas

Every map below is keyed by the record's `id`; `id` must agree with its key. Fields ending `?` below are **nullable but still required**. This notation is documentation, not a JSON field name. Additional runtime fields require a contract revision; definition metadata may use the designated `metadata` object.

```text
ResourceBalance (resources[resource_id]):
  id: String, unit: "kg" | "kwh" | "kcal" | "count"
  amount: number, capacity: number, reserved: number
  net_rate_per_s: number, forecast_empty_s: number?

Building (buildings[building_id]):
  id, definition_id: String
  cell: [int,int], rotation_quarters: int
  lifecycle: "constructing" | "commissioned" | "destroyed"
  enabled: bool, condition: number [0,1]
  construction_task_id: String?, construction_progress: number [0,1]
  power_requested_kw: number, power_served_kw: number
  operating_fraction: number [0,1]
  blocking_codes: Array[String]

Crew (crew[crew_id]):
  id, definition_id, display_name: String
  status: "idle" | "working" | "travelling" | "eva" | "incapacitated" | "dead"
  location_kind: "base" | "eva", position_m: [number,number,number]
  task_id: String?, expedition_id: String?
  health: number [0,1], fatigue: number [0,1], stress: number [0,1]
  radiation_dose_msv: number
  skills: Dictionary[String, number [0,1]]

Task (tasks[task_id]):
  id: String, kind: "construct" | "repair" | "farm" | "eva"
  target_id: String, status: "queued" | "active" | "blocked" | "completed" | "cancelled" | "failed"
  priority: int [0,100], crew_required: int, assigned_crew_ids: Array[String]
  required_work_s: number, completed_work_s: number
  blocked_code: String?, expedition_id: String?

Expedition (expeditions[expedition_id]):
  id, site_id, task_id: String, crew_ids: Array[String]
  status: "outbound" | "working" | "returning" | "stranded" | "completed" | "failed"
  route_id: String, route_waypoints_m: Array[[number,number,number]]
  route_distance_m: number, route_progress_m: number
  work_required_s: number, work_completed_s: number
  suit_stores: Dictionary[crew_id, {oxygen_kg: number, battery_kwh: number}]
  cargo: Dictionary[resource_id, number], return_margin_s: number?
  recall_requested: bool

Site (sites[site_id]):
  id, definition_id: String, cell: [int,int]
  reserved_by_expedition_id: String?, remaining_cargo: Dictionary[resource_id, number]

ActiveEvent (active_events[event_id]):
  id, definition_id: String, starts_tick: int, ends_tick: int
  modifiers: Array[{target: String, factor: number}]

Alert (alerts array, sorted by id):
  id, code, message: String
  severity: "info" | "warning" | "critical"
  entity_ids: Array[String], first_tick: int
```

`reserved` means unavailable for spending, not a second stockpile: available = amount − reserved. V1 building costs are spent immediately; they do not also become resource reservations. Keep their refundable prepaid amounts in authoritative save-only construction records. Suit oxygen and expedition cargo are outside base `resources` until transferred. Battery energy in `power` is a summary of the same `energy_kwh` ledger account, never an additional reservoir.

Capacity-limited construction refunds fail cancellation atomically with `capacity_exceeded`; the original job/building remains until the player makes room. This avoids deleting materials or creating an undocumented extra reservoir. V1 does not expose general player resource reservations, so `reserved` remains zero unless a documented Task 01 subsystem explicitly owns a reservation.

`forecast_empty_s` is available stock / negative net rate only when depletion is occurring; otherwise `null`. It is a constant-rate estimate, not a guarantee. `return_margin_s` is the minimum remaining oxygen/battery endurance across expedition crew minus predicted return travel duration; `null` when no valid return route/forecast is available.

## 7. Resource definitions, buildings, and production

Task 01's resource registry starts with `oxygen_kg`, `co2_kg`, `raw_water_kg`, `potable_water_kg`, `wastewater_kg`, `hydrogen_kg`, `food_kcal`, `energy_kwh`, `alloy`, and `electronics`. The suffix is descriptive; the registry's declared unit is authoritative. `alloy`/`electronics` are count resources and must remain whole-valued. Adding a resource is additive content only if all transactions and UI already support its declared unit; otherwise revise the contract.

`co2_kg` represents modeled cabin CO2 inventory, not a breathable-gas store. Air hazard evaluation requires configured pressurized volume/atmosphere assumptions in the scenario; a full oxygen tank never overrides CO2 danger. Storage capacity is not a health threshold. `oxygen_kg` is the simplified accessible base oxygen reserve; pressure/air mixing beyond this abstraction is future model work, not implied flight fidelity.

### Building definition (Task 02 authors; Task 01 validates)

```json
{
  "schema_version": 1,
  "id": "fixture_electrolyzer",
  "display_name": "Fixture Electrolyzer",
  "scene_path": "res://scenes/buildings/fixture_electrolyzer.tscn",
  "footprint_cells": [[0,0]],
  "entrance_cells": [[0,1]],
  "build_cost": {"alloy": 2},
  "construction_work_s": 10.0,
  "power_generation_kw": 0.0,
  "power_demand_kw": 1.0,
  "power_priority": 100,
  "process_priority": 100,
  "process": {
    "inputs_per_s": {"potable_water_kg": 0.009},
    "outputs_per_s": {"oxygen_kg": 0.008, "hydrogen_kg": 0.001}
  },
  "storage_capacity": {},
  "battery_charge_limit_kw": 0.0,
  "battery_discharge_limit_kw": 0.0,
  "battery_charge_efficiency": 1.0,
  "battery_discharge_efficiency": 1.0,
  "maintenance_work_s_per_s": 0.0,
  "unlocks_required": [],
  "metadata": {"status": "synthetic_test_fixture"}
}
```

This example demonstrates stoichiometric bookkeeping with synthetic throughput/power; it is not equipment performance data. `scene_path` is optional for headless fixture definitions (use `null`); presentation must handle missing assets with placeholders. All other fields above are required. Footprints are unique integer offsets; entrances must be outside the occupied footprint. Rotate offsets with `(x,z) -> (-z,x)` per positive quarter turn.

V1 has one process per building; more complicated equipment uses several definitions/components in a future contract revision. Input/output quantities must be nonnegative. Efficiency values are in `(0,1]`. A v1 battery uses storage `{energy_kwh: capacity}`. Storage is supplied only by commissioned, non-destroyed buildings plus scenario starting storage; destruction removes capacity and records overflow as explicit loss. Disabling a building does not erase its storage.

### Accounting and competition

Task 01 alone commits resource transactions. Each transaction has a stable `effect_id`, nonnegative debit/credit maps, and an optional explicit external source/sink classification. A repeated committed effect ID returns its cached result without reapplying. Multi-resource effects are atomic. Debits cannot exceed available stock and credits cannot exceed capacity unless the transaction explicitly names a waste/loss sink; never silently clamp away mass or energy. Transfer debits and credits represent the same quantity, not production.

Continuous processes run in descending `process_priority`, then building ID. Determine a common operating fraction from power, condition, available inputs, and output capacity; apply all scaled inputs/outputs together. Full oxygen storage therefore throttles electrolysis instead of consuming water without useful output. Generated outputs become available to later processes in the same tick. This intentionally ordered approximation must be identical in headless and rendered play.

Power is allocated before process resource limiting. V1 may therefore reserve electrical load for a process that is subsequently input-limited; account unused allocated energy as explicit idle/thermal loss. Do not invent extra battery energy by reallocating it a second time. Later optimization may improve this policy through a contract revision.

### Electrical power

At tick start, commissioned/enabled generators supply their rated output adjusted by condition and active environmental modifiers. Sort enabled consumers by descending `power_priority`, then building ID. Serve demand from current generation, then battery discharge, allowing partial power. A process scales linearly with its served fraction in v1; damaged/destroyed/non-commissioned equipment cannot bypass availability checks.

For dt seconds, `energy_kwh = power_kw * dt / 3600`. Discharge limits apply to energy delivered to the grid; stored reduction is delivered energy / discharge efficiency. Charge limits apply to grid energy input; stored increase is input energy * charge efficiency. Aggregate battery accounts dispatch individual batteries by stable ID, respecting their capacities/limits/efficiencies; persist per-battery stored energy and expose its sum as the ledger's `energy_kwh` amount. A battery never charges and discharges in the same tick. Excess generation charges batteries, then is explicitly curtailed.

Suit battery launch transfers stored electrical energy out of batteries by stable ID without a grid conversion loss; it is a declared gameplay simplification. Returning suit energy is accepted up to current capacity; excess is an explicit loss. Never draw batteries both via generic ledger debit and per-battery dispatch: one ledger operation updates both views.

V1 assumes a single shared base electrical/resource distribution network for commissioned buildings. Corridors and utility lines can visualize it. Separate power grids, pressure zones, and pipe routing require a later extension; UI must not imply they are already simulated.

## 8. Crew, work, and EVA contributions

Task 03 provides a `RefCounted` crew adapter with these methods:

```text
initialize(config, snapshot) -> OperationResult
plan_tick(snapshot, dt_s, context) -> CrewTickProposal
evaluate_hazards(snapshot, hazards) -> CrewTickProposal
apply_command(command, snapshot) -> CommandProposal
export_state() -> {schema_version: 1, state: Dictionary}
validate_state(record, candidate_core_state) -> OperationResult
restore_state(record) -> void
```

`plan_tick`, `evaluate_hazards`, and `apply_command` are pure queries and return detached proposals. They must not mutate the adapter or snapshot. Proposals contain `crew_updates`, `task_updates`, `expedition_updates` (maps of full candidate records), `labor` (array of `{task_id, crew_id, work_s}`), `resource_requests` (array of `{effect_id, kind, debits, credits, owner_id}`), and `events` (array of event drafts). `CommandProposal` also has `{ok, code, reason, result_data}`. State updates and linked resource requests commit together or none; Task 01 validates all referenced IDs, transitions, and resource effects before commit. State retained by the adapter is configuration/derived cache only; any authoritative private extension state must participate in its validated save record.

`context` is `{phase: "intent" | "progress", tick_index: int, unmet_needs: Dictionary[crew_id, Array[String]]}`. Unmet-need codes are `oxygen`, `water`, `food`, and `suit_energy`; the intent call receives an empty map. Hazard input is an array of `{crew_id, code, dose_msv, exposure_s}` with codes defined by the validated scenario hazard configuration. The hazard proposal may update crew/tasks/expeditions and emit events, but may not request resources or labor.

Crew resource-request kinds are restricted to `eva_load`, `eva_return`, and `cargo_return`. Debits/credits are maps of ledger account paths to quantities, e.g. `base/oxygen_kg` and `suit/expedition_000001/crew_000001/oxygen_kg`. Task 01 resolves these paths to base or expedition stores; site-to-expedition salvage uses `site/{id}/{resource_id}` and `cargo/{expedition_id}/{resource_id}` with kind `salvage_collect`. These four kinds are transfers with matching resources/amounts and verified ownership/capacity, never arbitrary production. Effect IDs use `crew_tasks:{owner_id}:{operation}:{cycle_or_tick}` and are checked against the transition that authorizes them. Base metabolic/process debits remain Task 01's responsibility.

In full-record crew proposals, suit-store and cargo amounts are unchanged placeholders from the input snapshot. Only the linked resource requests may change those balances. Task 01 overlays their committed ledger results after applying other validated state fields; reject direct balance edits in a proposal. Otherwise the same EVA load could appear once in a record update and again in its transfer.

Command proposals may request allocations using symbolic local references `new_task`, `new_expedition`; Task 01 substitutes allocated IDs only on successful commit. Placement similarly allocates `new_building` and creates its construction task without calling into a visual scene.

Crew demand is calculated by Task 01 once per living crew member, using Task 03's committed location/activity and configured metabolic parameters. Base-located crew draw base stores; EVA crew draw their individual suit stores. Task 03 never submits a second metabolic debit. Oxygen deficit and exhausted suit energy produce explicit hazards; crew cannot continue productive work while configured safety/health constraints prohibit it. Food/water demand and recoverable wastewater have declared source/sink paths in Task 01.

If a base supply cannot meet aggregate crew demand for a resource, distribute available supply in proportion to requested demand and report each affected crew member's unmet need. Apply any floating-point remainder in stable crew-ID order. Suit stores are individual and cannot be pooled implicitly. Metabolic output/recovery coefficients and hazard response to unmet demand belong in the validated science/game configuration; they must not be inferred from UI bars or invented inside the crew adapter.

Task 03 supplies labor only for crew who are present, available, and assigned to that job during the tick. Sum labor by task ID with deterministic crew ordering. Construction completion commissions a building once at the end of the tick; it first produces power/resources on the next tick. Farming labor contributes to crop work/progress; food yield is committed only by Task 01's crop process. Repair changes equipment condition through Task 01's validated completion effect. No scene, animation, or UI callback grants output.

### Task lifecycle

`queued -> active -> completed` is the normal path; unavailable prerequisites produce `blocked`, which can return to queued/active. Cancellable nonterminal jobs can become `cancelled`; unrecoverable conditions become `failed`. Terminal jobs never become active again. Continuous farming uses persisted work cycles and monotonically increasing cycle IDs in save-only task state; it does not award a new harvest on load or every active tick. Construction work counters are capped at required work; a completion marker/effect ID prevents duplicate commissioning.

### EVA policy and cargo

- Task 03 computes speed from the minimum capable speed of the expedition crew and configured terrain/activity effects. Crew definitions declare movement speed and suit capacities. Policy parameters declare oxygen/battery workload rates and `reserve_fraction` in `[0,1)`; they are explicit game/science configuration, not hidden constants.
- Before departure, calculate outbound + requested work + return duration and each crew member's expected consumption. Require projected remaining oxygen and battery at return to be at least `reserve_fraction * loaded_amount` for that resource. Reject missing return routes or insufficient loading. The UI preview uses the same pure estimator as command resolution.
- V1 reserves one site exclusively per expedition. Launch starts at the scenario's base airlock cell; crew must be available at base. Transfer suit stores at launch once. The team follows route progress using authoritative tick time.
- At most one phase transition occurs at tick end; no leftover subsecond work/travel is granted after a phase completes. All crew oxygen/battery use for that interval reflects its starting phase. This is an explicit one-second discretization.
- Salvage work reduces site cargo and moves it to expedition cargo once upon work completion, capped by configured expedition carry capacity. Partial work interrupted by recall yields no salvage in v1. Remaining site cargo stays available for a future expedition.
- On base return, cargo and unused suit stores transfer once. If base capacity is full, cargo remains in a persisted expedition return cache and is credited automatically, by expedition/resource ID order, when capacity opens; no silent deletion. Suit excess is the explicitly recorded vent/energy loss described above.
- Recall switches from current location to a deterministic return route. No route sets `stranded` and a critical alert; it does not teleport the team or refund consumed resources. A later valid route permits a recall retry. Exhaustion/death policy is data-driven; failure retains cargo/stores at the last location rather than crediting base rewards.

## 9. Ordered tick pipeline

After the command boundary, one tick executes these phases in order. Within each phase sort stable IDs. No subsystem runs on wall-clock callbacks.

1. **Environment:** activate scheduled events and expire events whose end tick has arrived. Modifiers apply on intervals with `starts_tick <= tick_index < ends_tick`. Event generation uses the simulation's seeded RNG only.
2. **Intent:** Task 03 derives assignments, starting activity, and travel/work intents from the current committed state. Unknown/unavailable dependencies block jobs; they do not invent placeholder rewards.
3. **Electrical dispatch:** Task 01 allocates generation/discharge/charging and records power service.
4. **Base processes:** Task 01 executes resource-limited building processes, including recycling, electrolysis, CO2 removal, and crop progress where applicable.
5. **Crew demand:** Task 01 applies metabolism to the correct base/suit stores and calculates unmet needs. Suit electrical use is also applied here.
6. **Crew/work progress:** Task 03 proposes elapsed travel, labor, fatigue/health updates using the post-demand snapshot. Task 01 validates/applies proposals, one-time completion/cargo effects, and releases reservations. Crew with unmet critical needs cannot earn productive work for that interval.
7. **Losses and hazards:** Task 01 applies leakage, wear, radiation/environmental exposure, and hazard evaluation; crew outcomes use Task 03's validated state adapter. This phase must not deduct metabolism again.
8. **Finalize:** increment tick index, refresh rates/forecasts/alerts, check invariants, and emit committed events/snapshot notifications. If a tick fails internally, roll back the entire tick including RNG and adapter state, retain consumed accumulator time for retry, report `internal_error`, and stop the current advance batch.

Task 03's `plan_tick` is invoked once for intent with `dt_s=0.0` (assignment changes only, no elapsed effects), and once after demand with `dt_s=1.0` for progress. Set `context.phase` accordingly and pass the current tick's unmet needs to progress. Invoke `evaluate_hazards` during phase 7 after Task 01 computes exposure. Each proposal is validated/committed within the enclosing tick transaction. The intent call cannot submit resource requests or labor. This avoids using stale pre-consumption state for survival/work decisions.

## 10. World, placement, and route service

Task 02 exposes a headless `RefCounted` service under `scripts/world/`; it uses immutable logical map data plus a supplied snapshot, not a live navigation bake or physics query. Visual navigation can interpolate its authoritative results.

```text
validate_placement(request: Dictionary, snapshot: Dictionary) -> Dictionary
query_route(request: Dictionary, snapshot: Dictionary) -> Dictionary
```

Placement request is `{definition_id, cell: [int,int], rotation_quarters}`. Response is `{valid: bool, code: String, reason: String, occupied_cells: Array[[int,int]], entrance_cells: Array[[int,int]]}`. Invalid response returns empty cell arrays. Validate bounds, buildable terrain, rotated footprints, occupied/reserved cells, and at least one passable entrance reachable from the base airlock after proposed occupancy. Prevent placements that block an existing occupied building's only reachable entrance or an active crew return path. Task 01 calls the service again during resolution, rather than trusting the UI's preview.

Route request is `{from_cell: [int,int], to_cell: [int,int]}`. Response is `{reachable: bool, code: String, reason: String, route_id: String?, waypoints_m: Array[[number,number,number]], distance_m: number}`. Unreachable means `route_id=null`, empty waypoints, distance 0; consumers must check `reachable`, not treat zero distance as success. Same-cell success returns one waypoint and distance 0.

V1 logical routing uses four-neighbor grid BFS with neighbor order `+X, +Z, -X, -Z`, one-meter horizontal edge cost, and no diagonals. Terrain defines passable/buildable flags and a visual height; height does not alter route cost in this version. Building footprints block routing; entrance cells remain outside footprints. Routes include start/end points at logical cell centers. Partial EVA progress follows segments; to replan, backtrack along the current segment to its last reached cell, charging that remaining backtrack distance, then follow a new route. No cell snapping grants free travel.

`route_id` is a deterministic content hash of map ID/revision, blocked-cell set, and requested endpoints. Do not use randomized language hashes or rendered coordinates. Authoritative map data and active routes are restored before resumed crew ticks. If navigation must change beyond placement, its revision/command semantics need a contract extension rather than an invisible scene edit.

## 11. Events and alerts

Every `game_event` uses `{id, type, tick_index, entity_ids, data}`. IDs use the saved event counter. Canonical types include `command_result`, `building_commissioned`, `task_completed`, `eva_launched`, `eva_recalled`, `eva_returned`, `resource_shortage`, and `hazard_changed`. Emit in phase order, then stable entity/effect ID order. UI/audio consume events; events do not independently apply gameplay effects.

Alerts are persistent conditions in snapshots, keyed by stable condition/entity identity. Repeated low oxygen does not create a new alert each frame. Expiring an alert removes the condition from the snapshot; historical presentation logs are optional and are not replayed as gameplay events after loading.

## 12. Persistence and versioning

### Save envelope

```text
format: "mars-outpost-save"
save_version: 1
contract_version: "1.0.0"
campaign_id: String
definition_manifest: Dictionary[String, String]
core:
  clock: {tick_index, time_scale, accumulator_s}
  rng: {algorithm_id, seed: decimal String, state: decimal String}
  id_counters: Dictionary[String, int]
  next_receive_sequence: int
  revision: int
  command_journal: Dictionary[command_id, journal_entry]
  pending_command_ids: Array[String] in receive order
  committed_effects: Dictionary[effect_id, transaction_result]
  authoritative_resource/building/event/site/technology state
  per_battery_energy, prepaid_build_costs, crop_cycles, scheduled_events
subsystems:
  crew_tasks: {schema_version: 1, state: Dictionary}
```

The core fields spelled out above are required. The grouped authoritative state is implemented as explicit `resources`, `buildings`, `active_events`, `sites`, `technology`, `per_battery_energy`, `prepaid_build_costs`, `crop_cycles`, and `scheduled_events` keys; no literal slash-delimited key is used. Core also includes `map: {id, revision}`. `crew_tasks.state` contains `crew`, `tasks`, `expeditions`, `return_caches`, `completion_markers`, and `private_counters`. These are the same authoritative records used to build snapshot collections, not a second independent simulation copy. Use the pinned engine's `RandomNumberGenerator`, with `algorithm_id="godot-rng-4.7.2"`; different engine RNG versions are incompatible unless an explicit migration/replay strategy is added.

### Save/load API and registration

- Task 01 registers the required adapter under the fixed key `crew_tasks` during initialization. Adapter methods are specified in section 8. Core owns building/resource/event/site persistence; Task 02 restores visuals from snapshots and needs no gameplay save adapter in v1.
- `export_save` returns a detached complete envelope at a boundary, including pending accepted commands and fractional accumulator. Calling during a tick returns an operation error record `{ok:false, code:"invalid_state", reason:...}` instead of a partial save. UI invokes it outside update callbacks; filesystem writing belongs to the integration wrapper.
- `import_save` validates envelope, supported versions, definition manifest, numbers, counters, uniqueness, entity references, command/effect journals, and adapter state into a temporary candidate. Do not replace the current campaign until every validation succeeds. A failed load changes nothing, including current command queue and RNG.
- Successful load replaces state/queue/RNG together, restores the crew adapter, emits one `state_changed`, and does not re-emit historical command results, events, or rewards. Pending commands resolve at the next boundary. Adapter restoration must be non-failing after validation; unexpected failure restores the old core and adapter state.
- Write save files atomically through a temporary file then replacement using the target platform's supported storage API; retain the previous valid save on write failure. Browser persistence requires Task 02 to verify the actual host/storage behavior. No server-side persistence is assumed.
- Contract follows semantic versions. A new required field, changed unit, altered ordering/accounting rule, or incompatible command shape is a breaking major change. Optional backward-compatible fields/new capabilities use a minor revision; clarifications without behavioral change use patch. V1 clients reject unsupported major/minor versions; an explicit compatibility table may permit earlier minor versions later.
- `snapshot_version`, `save_version`, and adapter `schema_version` are separate integer schemas. No automatic migration is assumed in v1. Reject newer/older unsupported save schemas with `incompatible_save`; never reset missing fields silently. Author migrations and fixtures before supporting a new save schema.

## 13. Worked integration sequences

### Construct a module

1. Task 02 queries placement and shows a preview; Task 03 UI sends `place_building`.
2. Submission queues it. On resolution Task 01 revalidates geometry/materials/unlocks, then atomically spends cost, reserves footprint, and creates building/task IDs. Insufficient stock creates neither entity.
3. UI assigns crew to the construction task. Task 03 supplies labor while Task 01 controls time and resources.
4. At completion Task 01 commissions once and emits `building_commissioned`. Task 02 updates visuals; Task 01 permits production next tick.

### EVA and salvage

1. Task 03 previews the shared estimator using Task 02's deterministic outbound/return route and Task 01's parameter configuration.
2. `start_eva` resolves only if crew, site, capacities, route, and reserve policy pass. Suit loading transfers base stock; no departure grant creates oxygen.
3. Task 01 charges metabolism; Task 03 advances travel/work. Completed salvage moves site cargo into expedition cargo once.
4. Recall changes the path from current position. Return transfers cargo/stores once or preserves capacity-blocked cargo in the return cache. Repeated command IDs never duplicate transfers.

### Power loss and restore

1. A generator is disabled or a scheduled dust modifier reduces output.
2. Next tick dispatch reduces served power. The electrolyzer's operating fraction decreases, reducing water input and O2/H2 output together.
3. Crew still consume oxygen from the correct reserve; UI shows declining net rate and depletion estimate. CO2 safety is evaluated independently.
4. Saving and restoring this state preserves queued actions, battery energy, RNG, job progress, suit stores, and forecasts recomputed from the same authoritative state.

## 14. Required contract checks

These are acceptance criteria for implementation, not tests already executed.

- [ ] Validate every command's successful/invalid schema case and every failure path's no-partial-effect guarantee.
- [ ] Retry queued/completed IDs, including after save/load; conflicting payload fails and rewards never repeat.
- [ ] Two placements competing for one footprint or the last materials resolve in receive order; one wins.
- [ ] Paused commands resolve, while production/metabolism/travel stay unchanged; resume and accumulator behavior match section 4.
- [ ] Equivalent fixed-step inputs produce the same state under 1x/5x/20x rendering schedules at equal completed ticks.
- [ ] Returned snapshots cannot mutate live state; callbacks cannot recursively resolve newly submitted commands.
- [ ] Resource-limited electrolysis preserves configured input/output ratios; an independent expected-balance calculation agrees.
- [ ] Battery accounting uses `/3600`, honors charge/discharge losses and caps, and never charges/discharges the same battery in one tick.
- [ ] Crew/EVA oxygen use is charged once; invalid launches spend nothing; cargo/full-store return handling preserves accounting.
- [ ] Commissioning/harvest/repair/rewards apply once across cancellation, reload, and retries.
- [ ] Headless route queries are deterministic and unreachable routes cannot be mistaken for free travel.
- [ ] Mid-job/mid-EVA saves with queued commands and fractional time resume equivalently to uninterrupted play.
- [ ] Corrupt saves, missing definitions, incompatible schemas, and failed tick/adapter operations preserve the last valid state.

## 15. Handoff rules

Read this spec before coding a shared boundary. Task 01 publishes facade/state/fixture implementation first; Task 02 implements the two headless world queries; Task 03 implements the crew adapter and UI against the same fixtures. All owners use the named schemas instead of inventing parallel state dictionaries.

Changes to these interfaces require an explicit spec edit and coordination with affected task owners before dependent implementation changes. Claude may propose abstraction improvements in a separate proposal; implementation follows the accepted contract until it is deliberately revised. There is no requirement to wait for finished art or UI to validate Task 01.
