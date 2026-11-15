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
- **Authored content.** `data/buildings/*.json` and `data/maps/landing_plain.json` load through the same validators, every authored building is placeable somewhere on the authored map, and every authored definition is labelled `balance_status: placeholder_pending_science_md`.

## Booting the world scene headless

Catches script errors in the scene graph without a window:

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --quit-after 30
```

## Running the world harness

Open the project in Godot 4.7.2 and press Play, or run the console executable with `--path .` and no other arguments. The main scene boots `scenes/world/main.tscn`:

- `Integration` (`SimulationBridge`) loads the map and building definitions, builds the headless `WorldService`, and attaches a backend. When `scripts/simulation/simulation.gd` exists and initializes, it uses Task 01's `OutpostSimulation`; otherwise it uses the development `FixtureSimulationStub`, which renders `salvage_6crew_tick0` and handles only `place_building`, `set_building_enabled` and `set_time_scale`. The stub never changes resource balances.
- Keys: `1`–`9` pick a building, `R`/`Shift+R` rotate, left click place, `Esc` cancel, `G` grid, `Space` pause, `+`/`-` time scale, `F1` hide overlay, `K`/`L` force `no_power` on/off for the hovered building (stub only). Camera: WASD/arrows or middle-drag pan, right-drag or Q/E orbit, wheel zoom, Home reset.

## Boundaries

- Placement previews are advisory. Only Task 01 spends materials; the scene only submits `place_building` commands through the bridge.
- Crew figures and the HUD belong to Task 03 and mount under `Main/CrewRoot` and `Main/UIRoot`.
- The authored `landing_plain` terrain is a procedural blockout, not NASA elevation data. Nothing under `assets/nasa/` has been imported yet; `ATTRIBUTION.md` records that state.
- Balance numbers in `data/buildings/` are placeholders awaiting `SCIENCE.md` entries; footprint and entrance geometry are authoritative.
