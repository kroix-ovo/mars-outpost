# Visual polish and guided first shift

The clean `codex/cohesive-game` checkout was fast-forwarded from `6de5938` to reviewed visual-polish commit `39f38b6`. The following local changes add readable mission guidance on top of that integration.

The HUD opens Guide on a new colony and keeps the current objective beside the roster. Training asks the player to return salvage, place a storage module, assign its construction crew, and commission it. Completion comes from committed simulation snapshots, including actual EVA return and module lifecycle. Starting modules, unrelated module definitions, an empty recall, and placement without construction do not satisfy those completion conditions. The next-mission button loads the existing reference colony, where the objectives are to inspect Systems and finish all starting repair jobs. Reference EVA remains unavailable under the existing science configuration.

`first_shift.gd` is a presentation-only observer. It sends no commands and grants no resources. Existing HUD controls send the same commands as before. Mission progress is session-only and resets on colony restart; campaign persistence remains unavailable.

The project uses a 1280×720 logical canvas with a minimum 16 px HUD text size. Wider resource accounting stays in Systems; the top strip prioritizes oxygen, potable water, power and battery. Drawer pages and crew details scroll when needed. Multiple crew selections show names rather than expanding every astronaut's skills at once; select one astronaut for skill details.

## Verification

- The complete `tests/run_headless_checks.py` run passed, including world, A1, A2, A3, world integration, bridge, crew UI and A3/crew compatibility. [Full output](evidence/first_shift/headless.log).
- The new production-gameplay test passed 105 checks: empty recall, working salvage return, HUD placement and assignment, actual commissioning/storage capacity, transition to the reference colony, every starting repair, and restart.
- Rendered input checks passed 18 checks each at 1280×720 and 1600×900 after the final layout changes.
- The mission layout checks passed at both resolutions, checking panel bounds, status-strip overflow and guide font size. Fresh PNGs are in [720p evidence](evidence/first_shift/1280x720/) and [900p evidence](evidence/first_shift/1600x900/).
- The integrated main scene was opened and maximized locally; its startup log has no errors. Rendered checks used the Dummy audio driver; audio was not verified.

These checks drive the actual main scene and HUD with scripted commands/input. The screenshots document the mission introduction and EVA planning, while the headless test verifies completed gameplay outcomes.
