# Mars Outpost — shared product requirements

## 1. Executive summary

Mars Outpost is a top-down 3D Mars outpost-management game. The camera and spatial building experience draw on Planet Coaster; crew management and readable resource decisions draw on Fallout Shelter; interconnected infrastructure and expansion draw on SimCity. Players land with a small expedition, establish shelter from ship supplies, assign work, and develop a resilient outpost.

The game must make realistic dependencies understandable and fun. Oxygen comes from stored reserves and powered equipment, water recovery affects oxygen generation, and a distant salvage trip consumes time and suit reserves while removing workers from the base. Scientific values require source verification; gameplay simplifications must be labeled.

The first playable integration must connect building, resource simulation, crew work, and an oxygen-limited salvage expedition. This is a sequencing milestone, not a cap on the final game.

## 2. Mission

Let players learn surface-mission engineering by making meaningful decisions about a living outpost.

- Make resource causes, rates, and reserves visible.
- Give crew assignments consequences for both base operations and exploration.
- Separate verified science, proposed technology, and gameplay abstractions.
- Keep the world readable, responsive, and enjoyable at a top-down camera distance.
- Build modular systems that Codex and Claude Code can extend without conflicting edits.

## 3. Target users

Primary players are young learners and management-game players with no assumed aerospace expertise. They need clear controls, understandable warnings, explanations of resource dependencies, and a way to recover from early mistakes. Team members need isolated ownership and reproducible integration checks.

## 4. Product coverage and milestones

The original report's hackathon scope limits do not apply. The following features are intended product coverage; checkboxes describe planned work, not completed features.

- [ ] Core: top-down 3D construction, expandable shelter, connected infrastructure, and starting ship supplies.
- [ ] Core: selectable 5–9-person expedition, with six as the default pending balancing.
- [ ] Core: crew assignments, farming, maintenance, repairs, salvage, and resource collection.
- [ ] Simulation: oxygen generation/storage, CO2 removal, water recovery, power, batteries, food, and materials.
- [ ] Exploration: suit oxygen, batteries, travel/task/return estimates, cargo recovery, and recall.
- [ ] Progression: crops, ice extraction, atmospheric oxygen production, shielding, rovers, and improved power systems.
- [ ] Experience: tutorial, alerts, pause/speed controls, save/load, sound, and science explanations.
- [ ] Delivery: desktop and browser builds with verified NASA-data provenance and asset credits.

Multiplayer, account systems, and a hosted backend are not currently requested. They require a new product decision rather than being assumed dependencies.

## 5. User stories

1. As a new commander, I want to land with a small crew and ship supplies so I can establish my first safe habitat. Example: unpack shelter, oxygen reserves, and electrical storage.
2. As a builder, I want to place and expand modules so I can increase capability while managing new resource loads. Example: preview a greenhouse's construction cost and operating demand.
3. As a commander, I want to assign individual astronauts so I can balance farming, repairs, and expeditions. Example: keep an engineer home while two crew recover cargo.
4. As an explorer, I want to see outbound, work, return, and reserve requirements so I can make a safe salvage plan. Example: recall a team before its return margin disappears.
5. As a learner, I want to inspect oxygen production so I can understand failures. Example: a full water tank does not produce oxygen if the electrolyzer has no power.
6. As an operator, I want warnings and meaningful responses so I can manage emergencies. Example: shed greenhouse electrical load during a dust event.
7. As a returning player, I want to save my colony so I can continue building. Example: restore crew assignments and an expedition in progress.
8. As a contributor, I want stable command/state contracts so I can build one subsystem independently and integrate it predictably.

## 6. Architecture and ownership

Use the established `assets/`, `data/`, `scenes/`, `scripts/`, and `tests/` structure. Keep gameplay calculations independent of rendering. Use typed GDScript, data-driven definitions, seeded randomness, and deterministic simulation time.

| Task | Responsibility | Primary paths |
|---|---|---|
| [01](TASK_01_SIMULATION.md) | Simulation, resources, life support, hazards, persistence | `scripts/simulation/`, `scripts/systems/`, `data/events/`, `data/tech/`, `SCIENCE.md` |
| [02](TASK_02_WORLD.md) | World, construction, infrastructure visuals, integration, builds | `scripts/world/`, `scenes/world/`, `scenes/buildings/`, `assets/models/`, `assets/textures/`, `assets/nasa/`, `data/buildings/` |
| [03](TASK_03_CREW_AND_UI.md) | Crew, tasks, EVA, UI, tutorial, feedback | `scripts/crew/`, `scripts/tasks/`, `scripts/ui/`, `scenes/crew/`, `scenes/ui/`, `data/crew/`, `assets/audio/` |

Each owner uses `tests/simulation/`, `tests/world/`, or `tests/crew_ui/` respectively. Task 02 alone integrates the main world scene, `project.godot`, export configuration, and CI. Task 01 owns shared state and persistence. Task 03 supplies crew/task serialization adapters. Each owner records asset credits; Task 02 consolidates `ATTRIBUTION.md`.

### Shared interfaces — agree before implementation

The [shared simulation contract](SHARED_SIMULATION_SPEC.md) now establishes exact v2 interfaces, data records, command payloads, tick ordering, accounting, navigation queries, and save/load rules. All owners implement against that document. The summary below is introductory; the spec governs any interface differences. Runtime implementation is still pending.

```text
submit_command(command: Dictionary) -> Dictionary
  acceptance response: {accepted, command_id, reason}
  rejection must leave state unchanged

get_snapshot() -> Dictionary
  detached/read-only view for presentation

step(delta_sim_seconds: float) -> Dictionary
  authoritative updates at a fixed timestep

signals:
  state_changed(snapshot)
  command_resolved(command_id, success, reason)
  game_event(event)
```

- Commands contain a stable ID, type, and payload. Initial types: `place_building`, `set_building_enabled`, `assign_task`, `cancel_task`, `start_eva`, `recall_eva`, `set_time_scale`.
- Snapshots contain schema version, simulation time, seed/RNG state, resources, buildings, crew, tasks, expeditions, technology, and active events. All entities use stable IDs.
- Use meters, kilograms, kW for power, kWh for stored electrical energy, and simulated seconds for durations. Record the Martian-sol conversion in `SCIENCE.md`; never silently equate a sol with 24 Earth hours.
- Task 02 supplies placement, occupancy, entrance, and route-query services. Task 03 consumes routes and owns assignment/movement/EVA behavior. Task 01 owns the ordered tick orchestration and resource accounting; crew metabolism and EVA use must not be deducted twice.
- Commands queue for an authoritative tick. Define deterministic ordering, atomic resource changes, one-time task rewards, and command deduplication before implementation. A queued command can fail later; the resolution signal reports that failure.
- Paused gameplay can accept planning commands without advancing metabolism or travel. Task 01 defines which commands resolve during pause and tests that behavior.
- Save files include registered subsystem state and RNG state. Snapshot presentation and save serialization are separate formats.

## 7. Feature requirements

Oxygen must include storage, generation from water, power availability, crew consumption, EVA transfer/use, leakage, and CO2 removal as a separate safety concern. Water recycling and atmospheric oxygen production are distinct capabilities. Plants may contribute only through explicitly documented assumptions; they must not be a magic replacement for engineered life support.

Construction requires valid placement, materials, crew labor, and commissioning. Expanding a colony changes both capability and operating demand. Crew have primary/secondary skills and individual health/fatigue. Salvage sites represent pre-landed cargo, damaged equipment, or science targets with bounded rewards and travel risk.

## 8. Technology stack

Godot 4.x, GDScript, Compatibility renderer; Blender to glTF/GLB; JSON or Godot Resources; WAV/OGG. Task 02 pins an exact installed Godot version and matching export templates for all contributors and CI before integration. No extra runtime libraries are required initially.

Use curated, attributable NASA resources for terrain/reference data and educational content. Source links in the supplied report are research leads, not proof that quantities have been verified.

## 9. Security and configuration

Local single-player operation needs no account or server secrets. Keep secrets outside version control. Validate data definitions and save-file schema, reject invalid commands, and fail gracefully on corrupt or incompatible saves. Ship required demo assets locally rather than relying on live NASA services during play.

## 10. API specification

The exact internal API is defined in [SHARED_SIMULATION_SPEC.md](SHARED_SIMULATION_SPEC.md); section 6 summarizes it. No HTTP service is required. Browser hosting must serve the actual Godot export correctly; Task 02 validates it on the intended host.

## 11. Success criteria

- [ ] A player can land, inspect reserves, assign crew, build a useful structure, and recover cargo.
- [ ] Removing power stops affected production; forecasts and alerts explain the dependency.
- [ ] EVA planning includes work and a safe return margin; recall works during an expedition.
- [ ] Building costs and recovered cargo apply once; invalid actions spend nothing.
- [ ] Identical seed/commands produce equivalent authoritative state at equal simulated times.
- [ ] Save/load preserves the colony, active jobs, expeditions, and subsequent deterministic behavior.
- [ ] Core flow works with 5, 6, and 9 crew and at supported speed settings.
- [ ] Desktop and browser smoke tests complete without blocking errors.
- [ ] Every imported asset has provenance; every adopted science quantity has an explicit status.

## 12. Implementation phases and effort

Give each task six work packages, initially estimated at four relative effort points each: **24 points per owner**. These are planning estimates, not evidence of equal hours. Re-estimate together after the first integrated loop and transfer optional polish work if one track is blocked or substantially heavier.

| Phase | Goal and deliverables | Validation / estimate |
|---|---|---|
| 1 | Agree contracts, pin engine, publish fixtures, open isolated harnesses | Everyone can develop against the same fixture; approximately first 15% of effort |
| 2 | Connect resources, placement, crew jobs, and basic HUD | Build and operate one useful module; approximately next 35% |
| 3 | Connect salvage, hazards, crops/progression, save/load | Complete expedition/emergency scenario and round trip save; approximately next 30% |
| 4 | Improve presentation, teach systems, verify builds | All acceptance checks pass on chosen delivery targets; approximately final 20% |

Calendar dates depend on team availability and measured throughput. Each phase must produce an integrated result, and additional features can continue afterward.

## 13. Further development

Deepen crop variety, medical care, rover logistics, ice surveys, advanced oxygen recovery, fission power, mission architectures, procedural terrain, and sandbox tuning as capacity allows. These extend the same three ownership areas rather than requiring a fourth workstream.

## 14. Risks and mitigations

- Integration drift: agree interfaces first, share fixtures, and merge small completed increments.
- Unequal work: use the same package count/initial points, expose dependencies, and rebalance using actual progress.
- Misleading science: verify primary sources and identify assumptions in `SCIENCE.md` and the UI.
- Scene conflicts: one world integrator; reusable crew/building/UI scenes owned separately.
- Delivery failure: validate browser and native exports early, then repeat after material integration changes.

Deep research could improve the oxygen/water/power simulation backend by resolving activity-dependent consumption, recycling boundaries, and technology scaling. Tell the user before starting that investigation, as required by `AGENTS.md`; this planning task does not perform it.

## 15. Appendix

Design context: `GAME_DESIGN.md`, `SCIENCE.md`, `ATTRIBUTION.md`, the supplied Mars Outpost research report, and the user's original game concept. Format reference: supplied `create-prd.md`. The three task documents below are the implementation handoffs.
