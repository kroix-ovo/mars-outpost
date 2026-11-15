# Task 03 handoff: Crew, EVA, and mission control

Use Godot **4.7.2 standard** from the repository root. No add-ons are required.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/crew_ui/run_crew_ui.gd
godot --headless --path . res://tests/crew_ui/harness.tscn --quit-after 5
godot --path . res://tests/crew_ui/harness.tscn
```

The standalone training scenario opens paused. The **Field guide** has links
to Crew & jobs, Build and EVA. In **Crew & jobs**, select an astronaut,
choose the farm or repair job, and assign them. Use **5×** to follow
travel, work, then completion. In **Build**, choose the Fixture Electrolyzer
and use cell (4, 8) to create an unfinished module. Assign an idle crew member
to the construction job that opens. In **EVA**, select idle crew, keep the 20 s work
plan and default stores, and examine the three phases and reserve. Try a
smaller oxygen load, then restore the default and launch. Recall during
outbound travel or work. Save a moving trip, advance it, then load the
checkpoint and watch it resume. The training slot is separate from the
production quick save.

`fixture_facade.gd` and `fixture_world.gd` are test-only. The former models
enough labor/completion and ledger behavior to exercise the controls and is
scoped to fixture gameplay and its own training save. The tests also
validate unmodified shared save fixtures. Track 01 provides authoritative
placement, job completion, EVA transfers and campaign saves for the game.

For a checkout with the world and simulation PRs applied, run the optional
integration check:

```sh
godot --headless --path . --script tests/crew_ui/run_world_mount.gd
```

The check mounts Mission Control in the real world scene, validates an EVA
preview with the real route service, toggles power through the real facade,
and compares live oxygen rates, warnings and alerts with the HUD. It also
checks rebinding when changing maps. It skips on a Track 03-only checkout.
Plan a first-time player session and native/browser smoke tests once the
production gameplay loop is wired.

## Owned changes

- `scripts/crew/`, `scripts/tasks/`, `data/crew/`: roster, validated
  adapter, job scheduling, EVA estimator and lifecycle, save validation.
- `scripts/ui/`, `scenes/ui/`, `scenes/crew/`: command HUD, local save slot,
  snapshot-driven crew avatars and selection.
- `assets/audio/`: two original UI cues and their provenance for Task 02.
- `tests/crew_ui/`: standalone training scenario and regression checks.

## Task 01: adapter registration

Once the campaign's world service is configured, construct
`preload("res://scripts/crew/crew_adapter.gd").new(world_service)` and pass
the new adapter to `OutpostSimulation.initialize`. Use a new adapter for
a new world service. During
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

Instantiate `scenes/ui/outpost_mission_control.tscn` once under the world's
`UIRoot`. After both the world and simulation are initialized, call:

```gdscript
mission_control.bind($CrewRoot, simulation, adapter, world_service, definitions_by_id)
building_selected.connect(mission_control.hud.select_building)
site_selected.connect(func(id: String, _route: Dictionary):
    mission_control.hud.select_site(id))
```

`definitions_by_id` is the map of stable definition IDs to the world's
building definition records. Connect the map selection signals once.
Rebind after a world change with the new facade, adapter, route service,
and catalog. The mount creates the crew view under `CrewRoot`, connects
crew selection in both directions, and snaps crew positions on HUD loads.
Use `hud.set_placement_cell(Vector2i(x, z))` when the player picks a build
cell on the map and `hud.placement_preview` for world ghost feedback.
While using the HUD's placement control, route the pick to the HUD and
let the HUD submit the order once. The facade revalidates each order.

The right dock can collapse to leave the viewport available. Enable physics
object picking on the world viewport for crew clicks. World integration
continues to call `simulation.advance(delta)` including while paused.
For a custom layout, `outpost_hud.tscn` and `crew_view.tscn` remain usable
independently. Pass a separate `user://` save path to `bind` if the
installer needs a separate slot. Verify file replacement and browser
persistence in the exported game.
