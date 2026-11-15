# Mars Outpost

A Mars colony-management game being developed for NASA Space Apps, centered on the engineering decisions needed to keep a crew alive and grow a surface outpost.

## Project vision

Build a top-down/isometric 3D colony where life support, power, water, food, construction, crew assignments, exploration, and emergencies interact. Player decisions trade resources, time, labor, and safety against one another.

Planned systems include:

- Oxygen generation, CO2 removal, water recovery, and habitat reserves.
- Power generation, storage, distribution, and equipment maintenance.
- Crew skills, health, fatigue, task assignments, and EVA planning.
- Modular construction, greenhouses, resource extraction, and cargo recovery.
- Environmental hazards, shielding, emergency response, and scientific exploration.

The aim is to advance the game as far as possible. The initial research report's scope limits are not project requirements.

## Current status

The integrated Godot 4.7.2 prototype combines Task 02's 3D world, building scenes, camera and route/placement previews with Task 01's A1/A2 authoritative clock, control commands, atomic ledger and electrical dispatch. Both the fixture map and authored `landing_plain` map run real generation/load/battery math. Values are synthetic placeholders, and this is not a complete playable colony: construction, life support, crew/EVA and save/load remain pending. See the [integration findings](docs/WORLD_SIMULATION_INTEGRATION.md), [world verification](tests/world/README.md) and [simulation verification](tests/simulation/README.md).

## Stack

- Engine: Godot 4.x, GDScript, Compatibility renderer.
- Models: Blender to glTF/GLB.
- Data: JSON or Godot Resource files.
- Audio: WAV/OGG.
- Repository: GitHub; planned CI: GitHub Actions.
- Planned delivery: itch.io browser build and native desktop backup.

## Repository structure

```text
mars-outpost/
├── README.md
├── SCIENCE.md
├── GAME_DESIGN.md
├── ATTRIBUTION.md
├── project.godot
├── assets/
│   ├── models/
│   ├── textures/
│   ├── audio/
│   └── nasa/
├── data/
│   ├── buildings/
│   ├── crew/
│   ├── events/
│   └── tech/
├── scenes/
│   ├── world/
│   ├── buildings/
│   ├── crew/
│   └── ui/
├── scripts/
│   ├── simulation/
│   ├── systems/
│   ├── crew/
│   ├── tasks/
│   ├── world/
│   └── ui/
└── tests/
```

Empty directories contain `.gitkeep` files so Git preserves the scaffold. Repository housekeeping also includes `AGENTS.md`, `.gitignore`, and `.gitattributes`.

## Getting started

Clone `https://github.com/kroix-ovo/mars-outpost.git`, then import `project.godot` in Godot 4.7.2 and press Play. The main scene is `scenes/world/main.tscn`. `F2` restarts the fixture colony; `F3` restarts the authored Mars colony. `Space` pauses, `+`/`-` change speed, WASD pans and the wheel zooms. The overlay reports live power and battery energy and labels unimplemented features. A valid placement preview currently leads to an explicit `module_unavailable` rejection on the real backend.

Run all headless checks with Python 3 and the installed console executable:

```powershell
python tests/run_headless_checks.py --godot '<godot-console>' --benchmark
```

Read `GAME_DESIGN.md` for the design direction, `SCIENCE.md` before adding simulation quantities, and `ATTRIBUTION.md` when importing external assets.

## Three-person implementation plan

Start with the [shared product requirements](PRD.md), which define the interfaces, integration milestones, and acceptance criteria for all three contributors.

Before implementing shared boundaries, read [SHARED_SIMULATION_SPEC.md](SHARED_SIMULATION_SPEC.md): the established v2 command payloads, snapshot schemas, fixed-step/pause rules, resource accounting, world queries, crew adapter, and save/load contract. This is the implementation baseline for all three tasks; the A1 foundation implements part of it, with later systems still to be built.

The [simulation reconciliation](SIMULATION_RECONCILIATION.md) records the review decisions behind contract 2.0.0. [Fixture tooling](tests/simulation/tools/README.md) regenerates and checks the synthetic reference outputs; A1/A2 runtime conformance is tested, with remaining gameplay scenarios awaiting later packages.

1. [Simulation and colony systems](TASK_01_SIMULATION.md): resources, life support, power, hazards, progression, and persistence.
2. [3D world, construction, and integration](TASK_02_WORLD.md): terrain, camera, buildings, navigation services, assets, and delivery.
3. [Crew management, EVA, and player interface](TASK_03_CREW_AND_UI.md): assignments, work, salvage expeditions, HUD, and onboarding.

Each task starts at six work packages and 24 relative effort points. Rebalance after the first integrated loop using actual progress.

## Development principles

- Keep simulation logic separate from rendering and interface code.
- Make simulation parameters data-driven and distinguish sourced science from gameplay assumptions.
- Track provenance and credits for external assets and scientific sources.
- Validate research claims against their original sources before using them as implementation requirements.

This is an independent project and does not imply NASA endorsement.
