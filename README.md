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

Repository initialized. There is no playable build or implemented simulation yet. Engine selection, implementation, assets, and deployment are still to come.

The research report proposes Godot 4 with GDScript; this repository does not yet commit to an engine or toolchain.

## Development principles

- Keep simulation logic separate from rendering and interface code.
- Make simulation parameters data-driven and distinguish sourced science from gameplay assumptions.
- Track provenance and credits for external assets and scientific sources.
- Validate research claims against their original sources before using them as implementation requirements.

This is an independent project and does not imply NASA endorsement.
