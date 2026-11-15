# Task 02 — 3D world, construction, and integration

**Required interface baseline:** [SHARED_SIMULATION_SPEC.md](SHARED_SIMULATION_SPEC.md). Implement its building-definition schema and headless placement/route queries; render its snapshots without changing resource balances. Earlier interface sketches defer to this spec.

**Implementation status:** the headless `WorldService` (`scripts/world/`), map/definition loaders, the world harness scene (`scenes/world/main.tscn`) with camera, terrain blockout, placement preview, lifecycle/status visuals, utility network lines, site kinds with route previews, authored module scenes (`scenes/buildings/`) and definitions (`data/buildings/`), the authored `landing_plain` world, a heightmap import tool for NASA terrain, export presets and CI are in place. Not yet done: importing an actual NASA terrain tile with its attribution record, Task 01/03 integration once their branches land, and verified exports (templates are only available in CI). See [world verification](tests/world/README.md) for the test command, controls and boundaries.

## 1. Executive summary

Build the top-down 3D place where the game happens: Martian terrain, landing assets, expanding modules, utility connections, and visible exploration sites. Make the outpost readable and satisfying to build, using modular, stylized assets.

Own the main scene integration and delivery pipeline so the three workstreams become one playable game. The first milestone is a controllable camera and valid placement of a module whose state comes from the simulation.

## 2. Mission

Turn colony decisions into a clear physical world. Keep placement predictable, routes navigable, system states visible, and exported builds usable.

## 3. Users

Serve players who want Planet Coaster-style camera control and expansion, plus contributors who need stable world services without editing the same central scene.

## 4. Coverage

- [ ] Terrain, camera, selection, landing ship, modular buildings, and placement previews.
- [ ] Occupancy, entrances, routes, utility visualization, cargo sites, and expansion space.
- [ ] Visual asset pipeline, NASA terrain/reference provenance, integrated main scene, and builds.

Resource calculations belong to Task 01; crew behavior and HUD panels belong to Task 03. Task 02 connects their scenes and services.

## 5. User stories

1. As a builder, I want pan/orbit/zoom so I can inspect and expand the outpost.
2. As a builder, I want placement previews so I can see blocked tiles and access constraints.
3. As a commander, I want construction states so I can distinguish planned, unfinished, and operating modules.
4. As an explorer, I want visible cargo sites and routes so travel choices have spatial meaning.
5. As a player, I want an easy-to-launch build so I can play without installing development tools.

## 6. Architecture and ownership

Own `scripts/world/`, `scenes/world/`, `scenes/buildings/`, `assets/models/`, `assets/textures/`, `assets/nasa/`, `data/buildings/`, `tests/world/`, `project.godot`, export configuration, CI, and consolidated `ATTRIBUTION.md`.

Keep reusable building scenes independent. Mount Task 03's crew/UI scenes through an agreed integration point. Supply placement validation, stable building IDs, building footprints/entrances, site positions, and route services. Task 01 alone applies inventory changes. Task 03 decides jobs and movement intent using the provided navigation services.

## 7. Six work packages — 24 initial points

| Package | Deliverable | Initial points |
|---|---|---:|
| B1 | Pin engine/templates, world harness, terrain blockout, camera and scene integration hooks | 4 |
| B2 | Placement preview/rotation, occupancy/access checks, construction lifecycle presentation | 4 |
| B3 | Landing ship/module kit, building definitions, utility/status visualization | 4 |
| B4 | Navigation/entrances, salvage locations, survey/ice sites and rover-ready routes | 4 |
| B5 | Mars art/lighting, NASA-derived terrain/reference integration, credits and visual feedback | 4 |
| B6 | Main scene integration, CI/export setup, browser/native checks and world bug fixes | 4 |

Integration is part of this estimate. Prefer placeholders until behavior integrates; use visual polish as a rebalancing lever after the first loop.

## 8. Stack

Godot 4 with Compatibility rendering, Blender to glTF/GLB, reusable text scenes, and data definitions. Pin matching export templates and communicate the version before peers begin dependent scene work.

## 9. Configuration and safety

Track source/credit/license for every imported asset. Keep generated editor caches and export artifacts out of source control. Do not make runtime NASA network requests a prerequisite for playing.

## 10. Interface

Implement `validate_placement` and `query_route` using the exact request/response schemas in the shared spec. Submit `place_building` commands and render construction/commissioned lifecycle plus enabled, condition, power, and blocking states from snapshots; never deduct materials in a scene script.

## 11. Acceptance checks

- [ ] Placement rejects overlap, invalid terrain, and inaccessible entrances without spending materials.
- [ ] A valid order reserves/consumes resources once through the shared command flow.
- [ ] Modules transition visually when crew finish construction and when utilities fail.
- [ ] Astronaut routes reach entrances and salvage sites; unreachable paths give an actionable reason.
- [ ] The camera, picking, placement, and UI coexist without input conflicts.
- [ ] Native and hosted browser builds load and complete the shared colony/salvage scenario.
- [ ] A visible NASA-derived data/reference use is documented accurately with its actual provenance.

## 12. Phases

1. Deliver B1, proposed footprint/route schemas, and a blockout world.
2. Connect B2–B3 to Task 01 commands and Task 03 construction jobs.
3. Add B4–B5 and integrate real crew/UI scenes; test an early browser export.
4. Complete B6, fix blockers, and verify the final combined flow.

Use the shared phase effort proportions; dates depend on team capacity and first-loop estimates.

## 13. Expansion

Add more biome/terrain layouts, varied habitats, rover presentation, extraction infrastructure, industrial animation, and broader build tools using the same scene and placement contracts.

## 14. Risks

Art can consume integration time: block out first. Buildings can break routes: validate entrances and refresh affected navigation. Web delivery can fail late: export early. Shared scene merges can conflict: this task alone owns main scene integration.

## 15. Handoff

Use branch `feat/world-construction`. Return changed paths, engine/template versions, import/export steps, screenshots, tested scenarios, and asset records. Request reusable peer scenes instead of editing their internals. See `PRD.md` for the full game contract.
