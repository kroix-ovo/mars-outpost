# Visual and input evidence

The rendered scripts need a real window (the headless display server uses a 64×64 dummy viewport and does not render). Run from the repository root with the Godot 4.7.2 console executable after the project has been imported once.

```powershell
& '<godot-console>' --path . --resolution 1600x900 --script tests/visual/run_hud_input_probe.gd
& '<godot-console>' --path . --resolution 1280x720 --script tests/visual/run_hud_input_probe.gd
```

`run_hud_input_probe.gd` drives the real main scene with synthetic viewport input and prints `HUD_INPUT_PASS checks=N`. It checks that world clicks select the module under the cursor and open it in the Build drawer, panels and the status strip swallow clicks and wheel steps, typing in a field neither pans the camera nor toggles pause, clicking the world releases keyboard focus, collapsing the drawer frees camera space, and a world switch rebinds the HUD and picking.

```powershell
& '<godot-console>' --path . --resolution 1600x900 --script tests/visual/capture_visual_evidence.gd
& '<godot-console>' --path . --resolution 1280x720 --script tests/visual/capture_visual_evidence.gd
```

`capture_visual_evidence.gd` plays both worlds through the production simulation and HUD handlers: module selection, a training EVA launch and recall, a completed salvage trip, map placement, construction assignment and commissioning, a reference repair, the disabled reference EVA, the collapsed drawer and the diagnostics view. It writes PNGs to `docs/evidence/visual_polish/<window size>/` and prints `EVIDENCE` lines with the observed simulation states. The project uses `canvas_items` stretch, so a 1280×720 window shows the same 1600×900 logical layout scaled to 80%.


The interactive tutorial has a rendered walkthrough with layout assertions:

```powershell
& '<godot-console>' --path . --resolution 1280x720 --audio-driver Dummy --script tests/visual/run_tutorial_layout.gd
& '<godot-console>' --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_tutorial_layout.gd
```

It plays the tutorial through HUD handlers and the production simulation and, at each key step, asserts the following, then saves PNGs to `docs/evidence/tutorial/<window size>/`:

- the card and every highlight are on screen;
- no highlighted control or world target is hidden under the card;
- card text is at least 16 physical pixels;
- Launch is fully visible.

Success marker: `TUTORIAL_LAYOUT_PASS`. The input probe and the visual-polish capture call `tutorial_press("skip")` first, because they exercise free play.

`tests/crew_ui/run_tutorial_mission.gd` (in `tests/run_headless_checks.py`, marker `TUTORIAL_PASS`) plays the whole tutorial headless against the real backend and covers:

- paused welcome, with Start tutorial as the single pointed-at action;
- out-of-order selection, collapsed drawer, skip/resume, a failed tick with restart;
- a one-astronaut salvage shortfall, an empty recall, then full salvage;
- blocked placement, placement, cancelled construction with refund, assignment and commissioning;
- the reference restart, systems, a cancelled starting repair with restart recovery, every repair, the debrief and finish.

These are scripted checks; they do not certify audio or human usability.

The title screen, astronaut designer, crew lineup and landing intro have their own rendered walkthrough:

```powershell
& '<godot-console>' --path . --resolution 1280x720 --audio-driver Dummy --script tests/visual/run_frontend_layout.gd
& '<godot-console>' --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_frontend_layout.gd
& '<godot-console>' --path . --resolution 1600x900 --audio-driver Dummy --script tests/visual/run_crew_lineup.gd
```

`run_frontend_layout.gd` walks title → settings → load game → designer → crew → intro (seven moments) → colony, asserts on-screen, readable (16 physical px) and non-overlapping controls, the corner logo, the looping music, saved settings and profile, the commander's name in the intro and the tutorial greeting, and writes `docs/evidence/frontend/<window size>/`. Marker: `FRONTEND_LAYOUT_PASS`. It uses test-only `user://test_frontend_*` files and deletes them. `run_crew_lineup.gd` renders the nine designed crew (`crew_lineup.png`) and every hair style across the skin-tone range (`customization_range.png`); marker `CREW_LINEUP_PASS`. The headless counterpart is `tests/frontend/run_frontend.gd` (marker `FRONTEND_PASS`).
