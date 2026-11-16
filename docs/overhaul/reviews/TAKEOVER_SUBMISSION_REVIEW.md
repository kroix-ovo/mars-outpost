# Submission takeover and HUD review

Integration branch: `ui/submission-hud`, PR #10 base `5d33c7b` plus a preserved snapshot of Fable's work. The original and Fable worktrees were not reset, merged or overwritten. This review accompanies the final submission PR authorized by the user.

## Implemented submission slice

- Normal title/customizer/crew/intro path enters the camp mission without F3. The last intro caption now explains the actual camp mission.
- Six-step farm/build/assign/tend/incident/repair-or-stabilize path. Direct next-step actions call real commands; canceled placement/construction can recover.
- Working linear farm conversion, a real botanist tending job/harvest, two engineering-sensitive repair challenges, component-wide 24-hour failure lock and seeded injury recovery.
- Seeded dust storm, forecast pause, solar-only 25% modifier, real farm load shedding versus battery consumption, clearing and cooldown. A focused native storm test passes.
- Dark slate HUD, four resource groups, bottom navigation, hidden-on-demand panels, separate Build/Inspect contexts, real playback icons, close-up astronaut portraits, explicit two-line names/roles and a full no-alert label. Top resources open Colony details.
- Light storm haze under the HUD, driven by the actual event state. No decorative random simulation.
- Correct equipment labels: Oxygen, Water recycler and Air filter replace the misleading repeated Life support wing sign.
- Solar radiation warning and active event: shelter reduces the simplified health penalty by 90% and pauses crew work. Timing and health coefficients are explicitly labeled game assumptions; no live weather or medical-dose claim.
- Thirteen 1920x1080 slide screenshots, including active dust/radiation states and a specialist close-up, are in `docs/evidence/submission_slides/`. These are staged native game renders, not an uninterrupted human playthrough.

## Exported playtest finding and fix

Direct input through the exported executable successfully reached the camp, placed a farm, assigned a builder and assigned a botanist. This exposed a real softlock after the arrival CO2 buffer depleted: the scrubber consumed fresh crew CO2 before the farm, so the farm never resumed producing and the incident milestone could stall.

The farm's authored process priority is now 100, ahead of the scrubber's 95. Its electrical priority remains 40, so life support still receives electricity first. The farm uses available CO2 before residual scrubbing. This is game resource-routing policy, not a crop-yield measurement. The authored config manifest was regenerated and checked. A new empty-CO2-buffer regression passes in `run_repair_farm.gd` (46 checks).

## Evidence

- Full existing suite plus campaign quick checks: `build/final-submission-checks.log` ends `HEADLESS_PASS`. Quick mode explicitly skips the already-recorded long detailed-day oracle. Later carbon-order change has its own focused regression and camp-flow rerun.
- `REPAIR_FARM_PASS checks=46`: `build/farm-carbon-fix.log`.
- `DUST_STORM_PASS checks=29`: `build/dust-takeover.log`, repeated in the final runner.
- `CAMP_FLOW_PASS checks=13`: `build/final-camp-flow.log`.
- `TUTORIAL_PASS` (111 checks): `build/hud-legacy-tutorial.log`.
- `FRONTEND_PASS checks=229`: `build/hud-frontend.log`.
- HUD interaction/render checks: `build/hud-refresh-tests.log`. They verify panel navigation, real speed changes, unobscured alert labels, placement/cancel and storm response/resume; latest run count is written in that log.
- Real rendered checkpoints at `docs/evidence/hud_refresh/`, including approved dark overview, separate crew labels, repair and active-storm views. These are actual Godot renders, not image-generated mockups.
- Export log: `build/final-windows-export.log`. Final artifact metadata and launch directions are beside the executable in `exports/windows`.
- Radiation checks: `RADIATION_PASS checks=16` and `RADIATION_UI_PASS checks=6` in focused local logs. Slide capture ends `SLIDE_CAPTURE_PASS`; framing ends `SLIDE_FRAMING_PASS`.
- The final PR regression log is `build/final-pr-checks.log`. Submission CI and this local run explicitly use `--quick`, omitting the long campaign oracle.

The older literal-arrow UI assertion was replaced by an assertion for one/two/three drawn triangles, matching the user's explicit change. The intro test now checks entry into the actual camp mission. Legacy gameplay assertions were retained.

## Honest limits

- This is the Level 1 submission slice, not completion of every overhaul package.
- Actual connected/furnished habitat interiors, a med bay, hunger/sleep schedules, treatment gameplay, full specialist autonomy, research/upgrades and six-month supply deliveries remain incomplete.
- Existing crew do real construction, tending and repairs. The commander model is not directly controllable; medical/pilot/geology role labels do not imply complete job systems.
- The live v2 mission's Save/Load controls remain unavailable because faults, injuries and weather are not persisted there. The separately tested v3 save/scheduler backend is not the live campaign.
- Crop, tending-harvest, incident and challenge coefficients are game assumptions. Reference physiology provenance remains in `SCIENCE.md`.
- Source-level rendered automation, physical input through the exported binary and headless oracle checks are distinct evidence. Only actions actually reached in the final executable should be described as exported playtesting.
