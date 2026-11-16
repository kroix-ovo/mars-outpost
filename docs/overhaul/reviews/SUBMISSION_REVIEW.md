# Submission build review (2026-11-15)

Historical Fable checkpoint. Superseded by [the final takeover review](TAKEOVER_SUBMISSION_REVIEW.md), which includes subsequent fixes, HUD work and radiation. Artifact hashes and missing-feature statements below describe this earlier checkpoint.

Workspace: `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`, branch `overhaul/living-colony-pr10`. Nothing was committed, pushed, merged, uploaded or submitted. This follows `docs/overhaul/RUSH_SUBMISSION.md`; it covers part of that list, and the sections below say exactly which part.

## What shipped tonight

All of it runs on the one existing simulation and ledger that the normal launch uses (title screen, then the colony). No second inventory exists.

1. **Working farm.** The greenhouse can now be placed and built like any module (8 alloy, 3 electronics, debited once by the ledger; cancel refunds as before). Once crew labor commissions it and it has power, it converts potable water and CO2 into food and oxygen every simulated second through the ledger (0.05 kcal/s at full operation, a game assumption). `farm_production: true` in capabilities.
2. **Two repair challenges, owned by the simulation.**
   - *Circuit reconnection* for batteries and other non-generating equipment: connect each lettered lead to the terminal with its matching shape.
   - *Tracker calibration* for solar arrays: press Lock while the moving marker is inside the marked band, for two or three passes.
   - The puzzle is generated from the simulation's seeded RNG and judged by the simulation. The UI sends only what the player pressed; there is no success input.
   - Engineering skill of the chosen astronaut matters: fewer leads or passes, a wider calibration window, and one more allowed mistake at 60% skill and above.
   - The colony clock is frozen while a challenge is open. Challenge time advances only from bounded inputs while the window is focused; there is a 75-second limit.
   - **Failure** (too many mistakes, timeout, or Abandon) sets the component to 0% condition and locks its repair for 86,400 simulated seconds. No other astronaut can start it during the lock, and no routine job exists that could bypass it. **Success** restores 100% condition, once.
   - Keyboard: number keys pick lead then terminal; Space or Enter locks. Shapes are words and the band is hatched, so nothing relies on colour. Slow mode halves the indicator and timer speed.
3. **Fault drill.** Build tab, select a commissioned module, **Fault drill**: the module really drops to 35% condition and needs the hands-on repair. One unresolved fault at a time.
4. **One real injury episode.** Failing the circuit challenge through too many wrong connections injures the operator (electrical shock). They become incapacitated at 50% health for a seeded one to seven mission days, cannot be assigned any job in that time, keep consuming supplies, and return to duty automatically when the episode ends. The crew card shows the remaining recovery time. Other work simply stays queued; no extra-fatigue rule for the rest of the crew was added.
5. **Camp Level 1 milestone.** The Tasks panel shows a four-row checklist read from committed simulation state: greenhouse built, farm producing, fault drill run, fault repaired or the colony stabilized under the lockout. Reaching it shows "CAMP LEVEL 1 · ESTABLISHED" and a status line. A failed repair still reaches Level 1 on backup equipment, with the retry time shown.

## How to play the new loop

1. Launch `MarsOutpost.exe` (or the project), start the game from the title screen, then press **F3** in the colony view for the reference colony. The training colony that opens first has the repair drill but no greenhouse.
2. Build tab: choose Greenhouse, place it on the map. Jobs tab: select the construction job, Suggest crew, Assign selected. Run time with `>` or `>>`.
3. Build tab: select a module such as the Battery Bank or a Solar Array, press **Fault drill**, then **Start repair**. The selected idle astronaut is used, otherwise the free astronaut with the best engineering skill.
4. Open **Tasks** (beside CREW) to see the Camp Level 1 checklist.

Existing controls are unchanged: Space pauses, 1/2/3 set speed, F2 restarts training, F3 the reference colony, F1 shows diagnostics.

## Artifacts

- Windows build: `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul/exports/windows/MarsOutpost.exe` (114,778,136 bytes, single file with embedded data, SHA-256 `b494f23ab109c2bfb80dac1896df1f034c154f80bbdeb7eeb6420ac0fccc5ca6`). Built with the installed 4.7.2 export templates: `Godot --headless --path . --export-release "Windows Desktop" exports/windows/MarsOutpost.exe`, exit code 0. `exports/` is ignored by git.
- Launch check of that file: started, ran 240 frames at the title screen and exited with code 0 and no error output. **The exported file's colony screen was not driven**, because release builds refuse a scene override on the command line. The colony, repair and farm checks below ran from the project with the same scripts.
- Source project: the worktree itself; open `project.godot` in Godot 4.7.2.
- Web and Linux presets exist in `export_presets.cfg` and were not exported.
- The export recreated seven missing `.uid` files next to existing scripts (Godot bookkeeping, shown in `git status`).

## Tests

Final run after the last code change, `python tests/run_headless_checks.py --godot <godot console>` (log: `build/submission-validation.log`): **`HEADLESS_PASS`**, no script or parse errors.

`WORLD_PASS` 679 · `A1_PASS` 14,301 · `A2_PASS` 41,144 · `A3_PASS` 6,718 · `INTEGRATION_PASS` 54 · `BRIDGE_PASS` 25 · crew UI 85/85 · `A3_CREW_PASS` · `TUTORIAL_PASS` · `FRONTEND_PASS` 229 · `CAMERA_CONTROLS_PASS` · `REPAIR_FARM_PASS` 38 · `CAMPAIGN_FOUNDATION_PASS` 331 · `CAMPAIGN_TIME_PASS` 326 · title scene and colony scene boot.

Rendered: `SUBMISSION_SLICE_PASS` 18 checks at 1600x900. The other rendered suites (tutorial layout, HUD input probe, pacing profiler) were not rerun tonight.

New focused checks:

- `tests/simulation/run_repair_farm.gd` (`REPAIR_FARM_PASS`, 38 checks, headless, registered in the runner): greenhouse cost, construction by labor, real yield on top of crew meals; fault drill; frozen clock; failure sets 0% and a full one-day lock; another astronaut refused with `repair_locked`; the operator injured for a seeded 1 to 7 days, refused for job assignment, and recovered at the end of the episode; refusal one second before the lock ends and acceptance when it ends; skill reduces stages and adds tolerance; success applied once; abandon is a failure; oversized time inputs clamped; a made-up "win" action rejected.
- `tests/visual/run_submission_slice.gd` (`SUBMISSION_SLICE_PASS`, 18 checks, rendered at 1600x900): drives the real HUD buttons and modal through a failed circuit repair, the lockout, a solved calibration, a built greenhouse and Level 1. Screenshots in `docs/evidence/submission/`.

One existing assertion changed on purpose: `tests/crew_ui/run_a3_compatibility.gd` expected the greenhouse to be unavailable; it now expects it available with `agriculture` still false.

**Manual playtesting: none.** Everything above was driven by automated scripts through the real HUD handlers and simulation. Nobody has played it by hand with mouse and keyboard tonight. Please play steps 1 to 4 once before submitting.

## Not shipped (still planned)

From the rush list, these were **not** built:

- Separate habitat wings with cutaway interiors (living, service, farm wings, bunks, cafeteria, med bay). The camp is the existing exterior modules beside the ship.
- Crew hunger and fatigue panel, scheduled eating and resting, Eat/Rest commands. Food is still the existing continuous shared draw.
- Role-specific jobs for botanists and medics, a med bay, treatment actions, and extra fatigue for crew covering an injured colleague. The injury itself and its timed recovery are real; there is no treatment gameplay.
- A rewritten tutorial. The existing tutorial is unchanged; the new loop is reached through the Build tab and the Tasks checklist, not through step-by-step tutorial cards.
- Travel to the component before a repair. The operator must be idle at base; they do not walk to the module first.
- Random or seeded faults. Faults come only from the Fault drill button.
- Saving faults, lockouts and injuries. The quick-save path does not include them, and the v3 campaign facade refuses the repair commands until package 6 adds them to checkpoints.
- Crops, seeds, harvest timing, upgrades, cargo choice, more challenge families.

Known rough edges: the greenhouse exists only in the reference colony (F3), not in the training colony; the fault drill can be repeated after each resolved fault; greenhouse output is limited by available CO2, so its operating fraction is usually below 100%.

## Also delivered this session

Package 2 (mission clock, scheduler, fast-forward and exact stable-interval replay for the v3 campaign facade) is complete and documented in [02_TIME_AND_SCHEDULER_REVIEW.md](02_TIME_AND_SCHEDULER_REVIEW.md). The live game does not use the v3 facade yet, so Package 2 does not change what a player sees tonight.

## Remaining roadmap

Packages 3 to 11 in `docs/overhaul/README.md` are unchanged. The repair system here is a first version of package 6 on the v2 path: its sessions, lockouts and inputs should move into the campaign partition with save support when that package is done properly.
