# Mars Outpost game design

## Direction

A top-down/isometric 3D Mars colony-management game about keeping a small expedition alive while developing a functioning outpost. Visual direction: stylized NASA industrial realism, modular habitats, readable utilities, recognizable astronauts, and rovers.

The campaign starts with six crew members and pre-landed infrastructure. Surface exploration focuses on cargo recovery, equipment repair, surveys, and geological science.

Every important decision trades safety, time, labor, power, or materials against another need.

## Core loop

1. Plan using inventories, consumption rates, and reserve forecasts.
2. Assign crew according to skill, fatigue, priority, and travel time.
3. Build and connect new infrastructure.
4. Operate interdependent colony systems.
5. Explore with EVA teams and rovers, accounting for return reserves.
6. Respond to faults, environmental hazards, injuries, and shortages.
7. Improve equipment, redundancy, and operational efficiency.

## Systems

- Life support: water recovery, electrolysis, CO2 removal, oxygen storage, and habitat losses.
- Power: generation, batteries, distribution, dust effects, and maintenance.
- Crew: primary and secondary skills, health, fatigue, stress, radiation exposure, food, and hydration.
- Construction: modular buildings, utility connections, materials, and installation labor.
- Surface operations: salvage, EVA consumables, rover logistics, surveys, and ice extraction.
- Agriculture and progression: crops, food production, resource processing, shielding, and technology upgrades.

## Simulation architecture

Keep authoritative simulation state independent of rendering and advance it on a deterministic tick. The report names these components:

```text
SimulationClock
ResourceSystem
LifeSupportSystem
PowerSystem
CrewSystem
TaskSystem
EventSystem
GameState
```

Rendering reads `GameState`. Building definitions and crew tasks are data-driven. Save/load stores authoritative state, task queues, exploration sites, technology, events, and random seed rather than scene-tree internals.

## Development scope

Pursue the full project vision as far as possible. The report's hackathon scope section, feature caps, and time-boxed MVP restrictions do not govern this project.

This document captures design intent; the systems above are not implemented yet.
