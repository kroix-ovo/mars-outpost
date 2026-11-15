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
- **Authored content.** `data/buildings/*.json` and `data/maps/landing_plain.json` load through the same validators, every authored building is placeable somewhere, each balance is labeled as a pending placeholder or documented game abstraction, and each `scene_path` resolves to a scene rooted on `building_node.gd` with an `Art` child.
- **Bridge flow (contract section 13).** Through `SimulationBridge` and the development stub: preview, a blocked `place_building` that fails at resolution without creating anything, a valid one that creates a constructing building and task, re-validation seeing the new footprint, duplicate command ids returning the cached result, explicit `module_unavailable` for EVA, commissioning after simulated work with a `building_commissioned` event, and a paused clock. Resource balances are byte-identical before and after.
- **Landing plain demo.** The authored world loads through `load_world`; every demo site and module entrance is reachable from the airlock, the utility network has one line per module and no cut-off module, the landing apron refuses placement with the terrain reason, and a failed world switch keeps the previous world.

## Integration with Task 01's simulation

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/world/run_integration.gd
```

Prints `INTEGRATION_SKIP` (exit 0) while `scripts/simulation/simulation.gd` is absent. With Task 01's facade present require `INTEGRATION_PASS`. Checks cover map identity, reachability, advisory previews, unavailable construction, resolved controls, clock/snapshots, dev-patch refusal, pause and switching. Both presets use the real backend. Authored checks verify 5.46 kW generation, 2.9 kW load, 0.95 battery efficiencies, solar shutdown via the selected-module `T` control, and the A3 oxygen balance including crew consumption. Repeated switching checks preview-node retention.

Integrated A3 verification on 2026-11-15: world 679, integration 54, bridge regressions 17, A1 14,295, electrical-only A2 41,144, A3 6,718 and full-runtime A1 benchmark 36,565 checks, all with success markers and exit 0. The runner rejects compiler/runtime errors even when a success marker appears. Once construction is implemented, the accepted-placement probe must create exactly one constructing building and occupy its footprint.

```powershell
python tests/run_headless_checks.py --godot '<godot-console>' --benchmark
python tests/world/tools/generate_integration_scenario.py --check
```

`tests/world/run_bridge_regressions.gd` reproduces and prevents mutable cached views, signal payload aliases, retired-backend publications, mismatched world/config attachment, AUTO fallback masking broken runtime initialization, and cursor/ghost roots leaking on reload. It also forces a tick failure and verifies one error notification, stopped automatic retries, unchanged committed view, failed-load isolation and recovery by replacing the world.

The authored runtime scenario/config are generated separately under `tests/world/fixtures/`. First run `python tests/simulation/tools/generate_a3_profile.py` to normalize the reference science and documented game throughput; then `python tests/world/tools/generate_integration_scenario.py` to refresh manifest hashes. Seven commissioned modules, fixture crew identities, full resource records and the A3 reference science profile are used. The unfinished greenhouse/task remain excluded until construction exists. The original generated synthetic reference fixtures stay unchanged.

## Booting the world scene headless

Catches script errors in the scene graph without a window:

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --quit-after 30
```

## Screenshots

```powershell
& 'C:\Users\Pierre\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/world/screenshot.gd
```

Opens a window briefly and writes eight captures to `docs/screenshots/`. The first five explicitly select the visual stub to demonstrate construction/status shapes; they are not evidence of runtime construction. The last three use the authored preset (real A2 when present): overview, ice-site route, rotated greenhouse preview. Previously committed images remain historical Task 02 captures.

## Running the world harness

Open the project in Godot 4.7.2 and press Play, or run the console executable with `--path .` and no other arguments. The main scene boots `scenes/world/main.tscn`:

- `Integration` (`SimulationBridge`) validates that the rendered map/definitions match the simulation manifest and initialized snapshot. AUTO uses Task 01's facade when present; a broken present facade fails visibly instead of becoming a successful stub. If the script is absent, AUTO can use the development `FixtureSimulationStub`. Explicit STUB mode remains available to visual harnesses only.
- Two world presets: `F2` restarts the Task 01 fixture colony; `F3` restarts the authored `landing_plain` colony with seven commissioned modules, three site kinds and real A2 power. These switches create new colonies, not save/load or travel between persistent maps.
- Keys: `1`–`9` pick a building, `R`/`Shift+R` rotate, left click place, `Esc` cancel, `G` grid, `Space` pause, `+`/`-` time scale, `F1` hide overlay, `K`/`L` force `no_power` on/off for the hovered building (stub only). Click a site to pin its route preview (distance and route id, or the unreachable reason); click a module to select it. Camera: WASD/arrows or middle-drag pan, right-drag or Q/E orbit, wheel zoom, Home reset.
- Signals for Task 03: `site_selected(site_id, route)`, `building_selected(building_id)`, `world_loaded(preset_name)`; call `begin_placement(definition_id)` from the HUD instead of the number keys.
- `T` toggles the selected building via the real command boundary. Live resource rates/forecasts and warnings are shown alongside electrical diagnostics. The authored map uses reference daily-average crew rates plus game assumptions, not validated machinery or health outcomes.
- Tick errors stop automatic advancement, preserve the last committed view/backlog, and emit `simulation_failed(result)` from the bridge. The overlay explains the failure; `F2`/`F3` starts a fresh colony. Consumers of bridge snapshots/signals receive detached views.

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
- Equipment kW/cost/capacity values remain game choices. A3 process throughput is explicitly sized from six reference crew plus 20% margin; provenance and boundaries are in SCIENCE.md. Footprint and entrance geometry remain authoritative.
- Utility lines visualize the single shared network of contract section 7; they do not imply separate grids or pipe routing.
