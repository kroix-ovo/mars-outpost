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

The integrated Godot 4.7.2 prototype combines the 3D world, A1–A3 simulation, and PR #6's crew, EVA and mission-control HUD. Construction, cancellation/refunds, crew assignments, repairs, salvage trips and recall use the real transactional simulation and resource ledger. Training uses synthetic rates; the authored `landing_plain` map uses NASA reference crew rates, the named roster and explicit game assumptions. Reference-profile EVA stays disabled until suit inputs are researched. Agriculture, medical/environmental outcomes and campaign saves remain pending. See [integration notes and verification](docs/COHESIVE_GAME_INTEGRATION.md), [A3 research and solution](docs/A3_RESEARCH_AND_SOLUTION.md) and [SCIENCE.md](SCIENCE.md).

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

Import `project.godot` in Godot 4.7.2 and press Play. The game starts on the **Mars Outpost Survival** title screen (`scenes/frontend/front_end.tscn`), with the title music looping. **New Game** opens the astronaut designer (name, skin tone, hair, eyes, facial hair, glasses, build, height, suit and trim), then a lineup of the six named crew and a skippable landing intro that leads into the training mission. **Load Game** opens a scenario directly (training or reference colony); colony saves wait on simulation persistence. **Settings** covers music volume, full screen and the intro. The colony itself is `scenes/world/main.tscn`, which still runs on its own for tests and the editor. Mission control overlays the world: a resource/status strip along the top, the crew roster on the left and a collapsible drawer (Jobs, Build, EVA, Systems, Guide) on the right. Clicking a module or salvage site opens it in the drawer. `F2` restarts synthetic training; `F3` restarts the authored/reference colony. `Space` pauses, `+`/`-` change speed, WASD or edge scrolling pans, middle-drag rotates and tilts, wheel or Z/X zooms, Home/End tilts and F recentres. Right-click cancels; 1/2/3 changes speed. `F1` shows diagnostics. World switches restart the colony; saves are not available yet.

The colony opens paused on an interactive tutorial that greets your commander by name: press **Start tutorial**. One card at a time explains the next action and why, and a pulsing highlight points at the exact control or map spot to use. Every step advances only from your real selections and committed simulation results: a two-astronaut salvage spacewalk, placing and building a storage module, then (after an explicit restart into the reference colony) inspecting life support and finishing the starting repair. Mistakes such as an empty recall, a blocked cell or a cancelled job show a recovery hint instead of getting stuck. **Skip tutorial** switches to free play; the **Guide** tab can resume it, or restart it from a fresh training colony.

HUD text uses a 1280�720 logical canvas with a 16 px minimum; larger windows scale it up. The top strip prioritizes oxygen, water, power and battery. Full resource accounting is available under **Systems**. Crew details and mission pages scroll when space is limited.

For the first training loop, pause, select two astronauts in the crew roster, then open **EVA** and launch the default salvage trip. Resume and wait for their return. In **Build**, choose the storage module and press **Choose a cell on the map**, then click an open cell (R rotates, Esc cancels); the coordinate fields remain for exact entry. In **Jobs**, select its construction job, suggest available crew and assign them. The finished module adds oxygen capacity. Cancel unfinished construction to recover its materials. On the reference map, assign crew to the initial repair jobs to restore damaged solar equipment.

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
