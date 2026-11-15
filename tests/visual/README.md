# Visual and input evidence

Both scripts need a real window (the headless display server uses a 64×64 dummy viewport and does not render). Run from the repository root with the Godot 4.7.2 console executable after the project has been imported once.

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
