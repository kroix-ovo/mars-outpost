# Visual polish: review handoff

Branch `codex/visual-polish` in `C:/Users/Symok/Documents/Nasa_Space_Apps_Visual`, based on integrated game commit `6de5938`. Implementation commit: `e053d23`. This handoff document is committed separately on top of it. Nothing was pushed or merged.

This is a presentation pass on the real main scene (`scenes/world/main.tscn`). Simulation records, tick order, balances, command schemas, science values and fixture oracles are unchanged. No test was weakened or edited. The HUD keeps every widget and member the existing probes inspect.

## Visual direction

A stylized Mars engineering colony: rust terrain, charcoal/graphite structure, off-white shells (never pure white), restrained amber hazard accents and cyan indicators. One material palette (`ModuleArt.CHARCOAL/GRAPHITE/SHELL/AMBER/CYAN`) is shared by modules, lander, crew and HUD accents.

- **Modules** (`scripts/world/module_art.gd`). Each kind has its own silhouette, consistently scaled to its footprint, and faces its entrance:
  - solar: tilted PV panels with cell lines, torque tube and inverter;
  - battery: a cabinet with module slabs, fins and terminals;
  - CO₂ scrubber: louvres and a top fan;
  - electrolyzer: a stack with O₂ (cyan band) and H₂ (amber band) bottles and pipes;
  - water recycler: a horizontal tank on cradles with a filter column;
  - storage: a habitat-like pressurized module with hatch and window band;
  - greenhouse: an unplanted glazed shell with no crops, so it does not imply agriculture works.

  The seven authored scenes keep `building_node.gd` as root and an `Art` child, now `module_art.gd`. Synthetic training definitions have no scene; they map to the same models through `ModuleArt.kind_for()`, so F2 and F3 look consistent. Emissive indicators dim to zero when a module is off, unfinished, destroyed or at zero condition. Their intensity also scales with condition.
- **Lander** (`scripts/world/lander_art.gd`):
  - pressure hull with ring bands and service panels;
  - descent stage with engine bell;
  - four legs and footpads, kept within the old model's ~1.75 m radius;
  - +X airlock vestibule with hatch and steps, windows, radiator and a comms mast.
- **Terrain** (`scripts/world/terrain_view.gd`):
  - deterministic per-map low-frequency rust/dust colour variation and fine speckle; buildable, not-buildable, apron and impassable remain distinguishable;
  - a rolling backdrop beyond the map that rises into low hills, for horizon and scale;
  - multimesh boulder fields outside the map, plus a few rocks on impassable cells only;
  - the grid is quiet by default and brightens only while placing a module.

  Nothing here creates collision. Routing, placement occupancy, map geometry and travel costs are untouched; the terrain mesh is still never read by routing, placement or picking.
- **Light and atmosphere** (`scenes/world/main.tscn`):
  - a lower warm sun (PSSM 2 splits, 70 m shadow distance, softened bias/blur) aimed so the camera-facing sides are lit and shadows fall to screen-left;
  - a cool unshadowed fill light from the opposite side;
  - a dusty sky, cooler ambient fill and distance fog;
  - filmic tonemap with a small contrast lift.

  Still the Compatibility renderer, with no SSAO, glow or SDFGI.
- **Crew** (`scenes/crew/crew_avatar.tscn`, `scripts/crew/crew_avatar.gd`):
  - suit, helmet with visor, life-support pack and a per-astronaut accent stripe (presentation hash of the ID);
  - an amber ground ring for roster-selected crew;
  - avatars face their direction of travel. Movement still interpolates toward snapshot positions only.

  Nameplates have a constant screen size and are drawn above geometry. Grouped crew at one location keep the existing single group label, now lifted above individual plates.
- **Selection and hover** (`building_node.gd`, `building_view.gd`, `main_world.gd`):
  - a footprint outline (light on hover, amber when selected) and a constant-size name label with lifecycle, condition or off state;
  - status beacons keep their colour-blind-safe shapes, smaller and seated on each model's top;
  - clicking a module opens it in the Build drawer, and clicking a salvage site opens EVA with that site selected;
  - stale highlights are cleared on world switches.
- **Camera** (`camera_rig.gd`):
  - each world opens framed on the lander, airlock and existing modules (yaw 35°, pitch 50°, distance clamped to 12–34 m), and Home returns there;
  - the framing snaps on load, so world switches rebind cleanly;
  - the screen-space offset keeps the colony centred between the roster and the drawer, and updates when the drawer collapses;
  - wheel zoom ignores steps over HUD controls.
- **Mission control** (`scripts/ui/outpost_hud.gd`, `scripts/ui/hud_icon.gd`, `scenes/ui/outpost_hud.tscn`). The HUD root is a full-screen pass-through `Control`, replacing the 710 px full-height panel:
  - **Status strip**:
    - mode badge;
    - pause/1×/5×/20× buttons that show the active speed;
    - mission clock;
    - chips for O₂, water, power, battery %, CO₂ and food, each with a tooltip for available stock, capacity, last-tick rate and time-to-empty;
    - an alerts chip, coloured by severity, that opens Systems.
  - **Crew roster** (left, 252 px, content height): multi-select (Ctrl/Shift), with statuses coloured idle/busy/incapacitated and compact skills for one or two selected astronauts.
  - **Contextual drawer** (right, 384 px, only as tall as the open page, collapsible to 46 px). The header holds the explicit unavailable **Save**/**Load** buttons (disabled, with tooltip) and **Mute**. Pages:
    - **Jobs**: job, priority, suggest/assign/cancel;
    - **Build**: selected module and toggle, catalog with unsupported modules marked "(unavailable)", a new **Choose a cell on the map** button that starts the existing world placement ghost, the exact-coordinate fields and their place button;
    - **EVA**: plan, live forecast, launch, expedition status and recall;
    - **Systems**: alerts, life-support explanation and module operating list, with the full accounting behind **Show detailed accounting**;
    - **Guide**: onboarding checklist and controls.
  - **Status toast** (bottom left).

  Icons are drawn with primitives, so no font glyph or image asset is required. Buttons and lists do not take keyboard focus, so Space, WASD and +/- keep controlling time and camera after a click. Clicking the world also releases field focus.

Pre-existing behaviour kept: F1 diagnostics, F2/F3 restart, 1–9 developer placement keys, R/Esc, G grid toggle, T toggle selected module, K/L stub patches.

## Files changed

| Area | Files |
|---|---|
| New | `scripts/world/module_art.gd`, `scripts/world/lander_art.gd`, `scripts/ui/hud_icon.gd`, `tests/visual/capture_visual_evidence.gd`, `tests/visual/run_hud_input_probe.gd`, `tests/visual/README.md`, `docs/evidence/visual_polish/**` |
| World | `scenes/world/main.tscn` (environment, sun, fill light), `scenes/world/landing_ship.tscn`, `scripts/world/{terrain_view,building_node,building_view,camera_rig,main_world,site_view,utility_view}.gd` |
| Modules | `scenes/buildings/*.tscn` (all seven: same root script, `Art` child now procedural) |
| Crew | `scenes/crew/crew_avatar.tscn`, `scripts/crew/{crew_avatar,crew_view}.gd` |
| HUD | `scenes/ui/outpost_hud.tscn` (root `PanelContainer` → `Control`), `scripts/ui/outpost_hud.gd` |
| Docs | `README.md` (new tab names and layout) and this file |

No backend file changed: nothing under `scripts/simulation`, `scripts/systems`, `scripts/tasks`, `scripts/crew/crew_adapter.gd`, `data/` or the fixtures, and not `project.godot`. One input bug was found and fixed in presentation code: mouse-wheel steps over HUD panels used to fall through to the camera and zoom the world. Panels now accept the mouse button events that reach them, and the camera ignores wheel steps while a control is hovered. `tests/visual/run_hud_input_probe.gd` covers this.

## Asset provenance

No external assets, downloads or installs. All geometry is built from Godot primitives (`BoxMesh`, `CylinderMesh`, `SphereMesh`, `TorusMesh`, `SurfaceTool`, `MultiMesh`) and `FastNoiseLite` in repository scripts. All HUD icons are drawn in code. No textures, fonts, models or audio were added, so `ATTRIBUTION.md` needs no new entry. Existing audio is unchanged.

## Checks and results

All runs used Godot 4.7.2 at `C:/Users/Symok/Downloads/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe` on Windows 11, after `--headless --import` in this fresh worktree.

| Check | Before (6de5938) | After |
|---|---|---|
| `python tests/run_headless_checks.py --godot <console> --benchmark` | HEADLESS_PASS | HEADLESS_PASS |
| world / A1 / A2 / A3 | 679 / 14,298 / 41,144 / 6,718 | identical |
| integration / bridge / crew UI / A3 crew | 54 / 17 / 85/85 / A3_CREW_PASS | identical |
| A1 benchmark | 36,570 | identical |
| main scene boot (`--quit-after 30`) | pass | pass, no errors or warnings |
| `generate_fixtures.py --check` | — | 85 fixtures up to date, closed-form checks passed |
| `generate_integration_scenario.py --check` | — | AUTHORED_FIXTURES_PASS |
| `generate_a3_profile.py --check` | — | A3_PROFILE_PASS |
| crew UI harness scene boot | — | no errors |
| `git diff --check` | — | clean |
| `tests/visual/run_hud_input_probe.gd` at 1600×900 and 1280×720 (windowed) | — | HUD_INPUT_PASS checks=18 at both sizes |
| `tests/visual/capture_visual_evidence.gd` at 1600×900 and 1280×720 (windowed) | — | EVIDENCE_DONE at both sizes |

The rendered evidence run plays the production simulation through the HUD's own handlers, and its log reports these states:

- **Training (F2)**:
  - EVA forecast "Ready to launch"; trip 1 launched (outbound), recalled, and back as `completed` with empty cargo, so the recall granted no salvage;
  - trip 2 completed, raising stock to alloy 10 and electronics 4;
  - storage module previewed with **Choose a cell on the map** and placed through the world-click submission path (`building_000006:constructing`);
  - Suggest crew picked `crew_000001`; Assign led to `task_000003:completed` and `building_000006:commissioned`;
  - oxygen capacity rose from 200 to 300 kg and materials were spent (alloy 0, electronics 2).
- **Reference (F3)**:
  - repair suggested and assigned to Inez Solis, who travelled to the job;
  - the repair task completed and every building is at condition 1.00;
  - EVA shows "EVA supplies and workload are not configured for this scenario", with Launch disabled.

The input probe checks:

- framing on load;
- world click → module selected and Build drawer opened;
- clicks and wheel steps on the drawer and status strip neither select nor zoom; the wheel over the world zooms;
- W and Space typed into a numeric field neither pan nor pause;
- a world click releases focus, after which W pans;
- collapsing the drawer frees camera space;
- an F3 switch rebinds the roster and title, and picking still maps to cells.

## Screenshots

Ordinary PNGs at `docs/evidence/visual_polish/1600x900/` and `docs/evidence/visual_polish/1280x720/`, with the same thirteen names in each:

| File | Shows |
|---|---|
| `01_training_overview.png` | F2 colony overview, status strip, roster, drawer |
| `02_training_module_selected.png` | module selected from the world: outline, label, Build drawer |
| `03_training_eva_plan.png` | two crew selected, EVA forecast ready |
| `04_training_eva_active.png` | expedition outbound with crew on the route |
| `05_training_eva_recalled_home.png` | recalled trip completed, crew home |
| `06_training_placement_preview.png` | map placement ghost with the planning grid emphasised |
| `07_training_crew_jobs.png` | construction job with suggested crew |
| `08_training_module_commissioned.png` | new storage module commissioned and selected |
| `09_reference_overview.png` | F3 reference colony overview |
| `10_reference_repair_in_progress.png` | repair assigned; astronaut travelling, damaged-solar beacon |
| `11_reference_eva_unavailable.png` | reference EVA clearly unavailable |
| `12_reference_drawer_collapsed.png` | drawer collapsed, world unobstructed |
| `13_reference_systems_diagnostics.png` | Systems page with detailed accounting expanded |

Baseline screenshots for comparison: `C:/Users/Symok/Documents/Mars Outpost Screenshots/2026-11-15/`.

## Known issues and limitations

- **1280×720 is a scaled layout.** The project's existing `canvas_items` stretch (unchanged) renders a 1280×720 window as the 1600×900 layout at 80%. Nothing is clipped and the probe passes, but the smallest labels are about 10 px. A responsive layout would require changing `project.godot` stretch settings, which this pass leaves alone.
- **Training lander overlaps buildable cells.** The training map (`fixture_flat_16`) does not mark the lander's cells impassable, so a module can still be placed under the lander model on the cells just west of the airlock. This is pre-existing; the new lander keeps the old footprint radius. The authored map marks those cells impassable.
- **Group labels can crowd at the airlock.** The group label and an individual nameplate can still sit close together when one astronaut stands next to the group.
- **The windowed probes are not in the headless runner.** `run_hud_input_probe.gd` and the evidence capture need a real window: the headless display server has a 64×64 dummy viewport and renders nothing. They are documented in `tests/visual/README.md` but not added to `tests/run_headless_checks.py`.
- **No `.uid` sidecars.** New scripts have no `.uid` sidecar files. Godot creates them when the project is next opened in the editor; nothing references them by UID.
- **Unchecked areas.** Audio playback, web/HTML5 export and frame-rate profiling on low-end or web targets were not checked. The added geometry is small: primitives per module, one multimesh for rocks, a single skirt mesh and two directional lights.
- **Mouse-driven verification was synthetic.** Interactive checks used synthetic viewport input in a real window, plus scripted HUD handler calls, not a human-driven mouse session.
- **Reverted import churn.** The fresh-worktree `--import` rewrote `assets/audio/*.wav.import` line endings; those were reverted and are not part of the commit.
