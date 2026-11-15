# Task 03 handoff: Crew, EVA, and mission control

Use Godot **4.7.2 standard** from the repository root. No add-ons are required.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/crew_ui/run_crew_ui.gd
godot --headless --path . res://tests/crew_ui/harness.tscn --quit-after 5
godot --path . res://tests/crew_ui/harness.tscn
```

The standalone training scenario opens paused. In **Crew & jobs**, select an
astronaut, choose the farm or repair job, and assign them. Use **5×** to follow
travel, work, then completion. In **Build**, choose the Fixture Electrolyzer
and use cell (4, 8) to create an unfinished module. Assign an idle crew member
to its construction job. In **EVA**, select idle crew, keep the 20 s work
plan and default stores, and examine the three phases and reserve. Try a
smaller oxygen load, then restore the default and launch. Recall during
outbound travel or work. Save a moving trip, advance it, then load the
checkpoint and watch it resume. The training slot is separate from the
production quick save.

`fixture_facade.gd` and `fixture_world.gd` are test-only. The former models
enough labor/completion and ledger behavior to exercise the controls; it is
not an accounting oracle, a production save format, or a replacement for
Task 01. The tests also validate unmodified shared save fixtures. Real-world
mounting, the production ledger/save pipeline, a first-time player session
and web export verification need the integrated build.

## Owned changes

- `scripts/crew/`, `scripts/tasks/`, `data/crew/`: roster, validated
  adapter, job scheduling, EVA estimator and lifecycle, save validation.
- `scripts/ui/`, `scenes/ui/`, `scenes/crew/`: command HUD, local save slot,
  snapshot-driven crew avatars and selection.
- `assets/audio/`: two original UI cues and their provenance for Task 02.
- `tests/crew_ui/`: standalone training scenario and regression checks.

## Task 01: adapter registration

Construct `preload("res://scripts/crew/crew_adapter.gd").new(world_service)`
and pass it as the crew adapter to `OutpostSimulation.initialize`. During
initialization call `adapter.initialize(config, initial_snapshot)` before
publishing the campaign. The adapter loads only manifest-listed scenario,
map, science, crew, job template and building definition paths. Existing
fixture paths are supported. To adopt the named roster and tuned job
settings, make the scenario reference the two `data/crew/` JSON files,
include their hashes, and select 5–9 roster definition IDs. The Task 03
crew speeds and suit capacities are gameplay settings, not Mars
equipment performance data.

Use the section 8 intent/progress calls, plus `evaluate_hazards` after
demand. Dispatch the four crew/EVA commands and ask the adapter for the
construction template during placement. For farm and repair lifecycle
hooks, use `get_task_template(kind, required_work_s)`; the facade supplies
the stable ID, target, initial status and progress. Explicit assignments
are never preempted. Priority sorts jobs with ID as the tie-breaker;
crew suggestions rank available, reachable crew by skill, health and fatigue.

- Allocate the symbolic `new_task`, `new_expedition`, and `new_building`
  references on successful commit; resolve them in map keys, records,
  result/event data and transfer paths/effect IDs.
- Reserve or release sites in core from committed expedition transitions.
  Mirror EVA work progress into the matching task. Apply suit and cargo
  balance changes only from the linked ledger requests, overlaying the
  unchanged balance placeholders in proposal records. Task 01 owns metabolism,
  labor counters, crop cycles, commissioning, repairs, refunds, and cache
  draining. No Task 03 scene or adapter performs those operations.
- Commit a candidate and validate the resulting `crew_tasks` schema-1 record
  before publishing. The adapter has no separate gameplay state or
  restore-time effects. The completion markers and counters maps are
  supported; the adapter does not allocate or advance them.
- Use the validated scenario values for EVA suitability and consumption.
  `crew_metabolism.eva_supported: false` disables EVA in the researched A3
  profile until Task 01 enables it. Optional science controls consumed by the
  adapter are `eva_policy.phase_rates_per_s`, `eva_policy.fail_on_suit_exhaustion`,
  and `crew_hazard_responses` (per hazard code: `health_loss_per_s`,
  `stress_gain_per_s`, `fatal_at_zero`). If supplied, use the same workload
  rates in Task 01 demand as in the forecast. Modifiers `eva_movement`,
  `eva_oxygen_kg` and `eva_battery_kwh` affect the corresponding configured
  values. With no health coefficients, dose still accumulates; with no
  fail-on-exhaustion rule, unmet needs block work without inventing a health
  penalty. V2 salvage uses the crew's count capacity, so other units
  remain at the site until a carry rule is defined.

## Task 02: scene mounting

Place `scenes/ui/outpost_hud.tscn` under a CanvasLayer (or a layout
container for a side panel). Call `hud.bind(sim, adapter, world_service,
definitions_by_id)`, passing the same initialized instances and immutable
building definition records used by the world. The HUD does not drive the
clock; the world integration still calls `sim.advance(delta)`, including
while paused. Set map picks with `hud.set_placement_cell(Vector2i(x, z))`
and subscribe to `placement_preview(request, result)` to display footprint
feedback. The facade revalidates before each commit.

Mount `scenes/crew/crew_view.tscn` under the world root, call
`apply_snapshot(sim.get_snapshot())`, and connect `state_changed` to
`apply_snapshot`. On a successful load call `apply_snapshot(snapshot, true)`
if the checkpoint has the same campaign and revision and should snap
immediately. Enable physics object picking in the viewport for clicks and
connect `crew_view.crew_selected` to `hud.select_crew`. If the HUD needs a
custom quick save slot, pass a separate `user://` path to `bind`. Verify
platform save replacement and browser persistence when exporting.
