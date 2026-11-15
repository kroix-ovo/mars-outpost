# World verification (Task 02)

## Headless world-service checks

Run from the repository root with the team's Godot 4.7.2 console executable:

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/world/run_world.gd
```

Exit code 0 with the marker `WORLD_PASS checks=N` is success. Any `WORLD_FAIL` line, a non-zero exit, or a script/parse error is a failure. No editor, main scene, or test library is needed.

What `run_world.gd` covers:

- **Stub replay.** Every placement and route case in `tests/simulation/fixtures/stubs/stub_world_fixture_flat_16.json` replays byte-for-byte against `WorldService`: reason strings, `occupied_cells`/`entrance_cells`, waypoints, distances and the `route_id` SHA-256 hashes. The expedition fixture `eva_working_tick10` carries the same route id and waypoints the service produces.
- **Rotation.** `(x, z) -> (-z, x)` per quarter turn, including multi-cell footprints and negative quarters.
- **Terrain and reserved cells.** Non-buildable terrain rejects footprints, impassable terrain blocks routes and entrances, heights appear in waypoints but never in distance, and site cells stay free.
- **Access protection.** A placement cannot remove an existing building's only reachable entrance, cannot cut an active expedition's return path (site cell or current route cell), and cannot wall off the airlock.
- **Harness injection.** `set_injected_blocked_cells` changes detours, unreachability and route ids, and clearing it restores the original id.
- **Request validation.** Missing keys, unknown definitions, rotation out of range, fractional cells, snapshot/map mismatch and uninitialized services all return the contract shape with empty arrays and a machine code.
- **Definitions and maps.** The section 7 schema validator, the registry copy semantics, and map validation (airlock in bounds and passable).
- **Authored content.** `data/buildings/*.json` and `data/maps/landing_plain.json` load through the same validators, every authored building is placeable somewhere on the authored map, every definition is labelled `balance_status: placeholder_pending_science_md`, and each `scene_path` resolves to a scene rooted on `building_node.gd` with an `Art` child.
- **Bridge flow (contract section 13).** Through `SimulationBridge` and the development stub: preview, a blocked `place_building` that fails at resolution without creating anything, a valid one that creates a constructing building and task, re-validation seeing the new footprint, duplicate command ids returning the cached result, explicit `module_unavailable` for EVA, commissioning after simulated work with a `building_commissioned` event, and a paused clock. Resource balances are byte-identical before and after.
- **Landing plain demo.** The authored world loads through `load_world`; every demo site and module entrance is reachable from the airlock, the utility network has one line per module and no cut-off module, the landing apron refuses placement with the terrain reason, and a failed world switch keeps the previous world.

## Integration with Task 01's simulation

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/world/run_integration.gd
```

Prints `INTEGRATION_SKIP` (exit 0) while `scripts/simulation/simulation.gd` is absent from the branch, so CI runs it unconditionally. With Task 01's `OutpostSimulation` present it must print `INTEGRATION_PASS checks=N`. It checks that the bridge boots on the simulation with matching map identity, that every starting building entrance and site is reachable, that previews change nothing, that `place_building` returns the contract envelope and (while Task 01 still answers `module_unavailable`) leaves balances and buildings untouched, that `set_time_scale` and `set_building_enabled` resolve into the snapshot, that real time ticks the clock and republishes snapshots, that dev patches are refused, that pause stops the clock, and that the main scene selects the simulation automatically, draws one node per building, switches to the stub for the authored world and back.

Last verified on 2026-11-15 against `origin/feat/simulation-a2` (A1 14,289 checks, A2 41,144 checks and the world suite all pass side by side; integration 44 checks). Once Task 01 implements `place_building`, the accepted branch of the probe applies: exactly one constructing building appears and the footprint becomes occupied.

## Booting the world scene headless

Catches script errors in the scene graph without a window:

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --quit-after 30
```

## Screenshots

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/world/screenshot.gd
```

Opens a window briefly and writes eight captures to `docs/screenshots/` (fixture world: overview, valid and blocked previews, construction and status states, commissioned modules with a site route preview; authored world: overview, modules with the ice-site route, rotated greenhouse preview).

## Running the world harness

Open the project in Godot 4.7.2 and press Play, or run the console executable with `--path .` and no other arguments. The main scene boots `scenes/world/main.tscn`:

- `Integration` (`SimulationBridge`) loads the map and building definitions, builds the headless `WorldService`, and attaches a backend. When `scripts/simulation/simulation.gd` exists and initializes, it uses Task 01's `OutpostSimulation`; otherwise it uses the development `FixtureSimulationStub`, which handles only `place_building`, `set_building_enabled` and `set_time_scale` and never changes resource balances.
- Two world presets: `F2` the Task 01 fixture world (`fixture_flat_16`, `salvage_6crew_tick0`), `F3` the authored `landing_plain` world with the seven `data/buildings/` modules and three site kinds (cargo, survey, ice) from `tests/world/fixtures/landing_plain_demo_snapshot.json`.
- Keys: `1`–`9` pick a building, `R`/`Shift+R` rotate, left click place, `Esc` cancel, `G` grid, `Space` pause, `+`/`-` time scale, `F1` hide overlay, `K`/`L` force `no_power` on/off for the hovered building (stub only). Click a site to pin its route preview (distance and route id, or the unreachable reason); click a module to select it. Camera: WASD/arrows or middle-drag pan, right-drag or Q/E orbit, wheel zoom, Home reset.
- Signals for Task 03: `site_selected(site_id, route)`, `building_selected(building_id)`, `world_loaded(preset_name)`; call `begin_placement(definition_id)` from the HUD instead of the number keys.

## Status language

Module state uses colour **and** shape so it reads without colour vision: green sphere = operating, amber cube = warning (`partial_power`, `input_limited:*`, `output_full:*`, low condition), red triangle = failure (`no_power`, `damaged`, destroyed), grey disc = off (constructing or `disabled`). Utility lines from the airlock to each module follow the authoritative route and use the same palette for power served / partial / none, yellow while constructing, grey when idle.

## Heightmap import (B5 pipeline)

`tests/world/tools/heightmap_to_map.gd` converts a grayscale heightmap (for example a MOLA or Mars Trek DEM tile shipped under `assets/nasa/`) into a `WorldMapData` JSON:

```powershell
& '<godot console exe>' --headless --path . --script tests/world/tools/heightmap_to_map.gd -- --heightmap res://assets/nasa/<tile>.png --out res://data/maps/<id>.json --id <id> --size 48 --min-m 0 --max-m 12 --airlock 10,24 --source "<provenance>"
```

No NASA tile is in the repository yet; `ATTRIBUTION.md` must receive the asset record before the output map is committed.

## Boundaries

- Placement previews are advisory. Only Task 01 spends materials; the scene only submits `place_building` commands through the bridge.
- Crew figures and the HUD belong to Task 03 and mount under `Main/CrewRoot` and `Main/UIRoot`.
- `landing_plain` terrain is a procedural blockout, not NASA elevation data. Nothing under `assets/nasa/` has been imported yet.
- Balance numbers in `data/buildings/` are placeholders awaiting `SCIENCE.md` entries; footprint and entrance geometry are authoritative.
- Utility lines visualize the single shared network of contract section 7; they do not imply separate grids or pipe routing.
