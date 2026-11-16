# Living colony implementation

The overhaul turns Mars Outpost into a commander-led survival colony. Build a sealed camp separate from the ship, establish crew routines, survive disruptions, research improvements, and choose supplies every six months. Finish a two-year settlement milestone, then continue in endless play.

## Current delivery

Packages 0 and 1 are implemented on `overhaul/living-colony-pr10`, based on PR #10's merge commit `5d33c7b`. Use workspace `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`. The existing title screen and prototype still start normally. The new campaign facade is opt-in and is not a playable overhaul yet.

- Prior dirty files remain in the original `Nasa_Space_Apps` checkout, with a backup at `Nasa_Space_Apps/build/overhaul-baseline.zip`; they were not copied over PR #10's integrated files.
- The original checkout's pre-change headless suite and benchmark passed (`Nasa_Space_Apps/build-baseline.log`). The final PR #10-based suite has its own log at `build/overhaul-validation.log` in this worktree.
- The v3 facade, complete checkpoint codec, native save store, and foundation regression suite are implemented.
- The campaign content catalog is authored starting data, not enabled machinery or validated balance.
- Gameplay, interiors, challenges, progression, fast-forward, and the replacement tutorial belong to the following Fable packages.

## Start Fable here

Open `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul` in Fable 5.2 and send:

```text
Implement docs/overhaul/handoffs/02_TIME_AND_SCHEDULER.md.
First read AGENTS.md, docs/overhaul/README.md, docs/overhaul/DESIGN.md,
and docs/overhaul/CAMPAIGN_CONTRACT.md. Preserve the current dirty work.
Follow the shared workflow in docs/overhaul/FABLE_WORKFLOW.md.
Complete this package, test it, and write its review handoff. Do not start
the next package or publish/merge anything. I will bring the result back for review.
```

Return the resulting diff/branch and review handoff for review before advancing. Use the same kickoff with the next numbered package after its predecessor passes review.

## Package order

| Package | Status | Review gate |
|---|---|---|
| 0: baseline preservation | Complete | Existing suite and benchmark pass |
| 1: contract and saves | Complete | `CAMPAIGN_FOUNDATION_PASS` |
| [2: time and scheduler](handoffs/02_TIME_AND_SCHEDULER.md) | Implemented, awaiting review ([handoff](reviews/02_TIME_AND_SCHEDULER_REVIEW.md)) | `CAMPAIGN_TIME_PASS`; exact boundary processing and continuation |
| [3: camp construction](handoffs/03_CAMP_CONSTRUCTION.md) | After package 2 passes review | Commission a furnished, sealed camp |
| [4: commander and crew](handoffs/04_COMMANDER_AND_CREW.md) | After 3 | Visible autonomous work, meals and sleep |
| [5: food and medicine](handoffs/05_FOOD_AND_MEDICINE.md) | After 4 | Harvests, treatment and workload coverage |
| [6: repair challenges](handoffs/06_REPAIR_CHALLENGES.md) | After 5 | Distinct challenges and real failure lockout |
| [7: playable slice](handoffs/07_PLAYABLE_SLICE.md) | After 6 | Play through setup, injury, repair failure and recovery |
| [8: events and exploration](handoffs/08_EVENTS_AND_EXPLORATION.md) | After 7 | Seeded replayable incidents and discoveries |
| [9: upgrades and cargo](handoffs/09_PROGRESSION_AND_CARGO.md) | After 8 | Research, meaningful branches and four deliveries |
| [10: tutorial and presentation](handoffs/10_TUTORIAL_AND_PRESENTATION.md) | After 9 | Continuous setup tutorial and all challenge families |
| [11: campaign validation](handoffs/11_CAMPAIGN_VALIDATION.md) | After 10 | Two-year campaign, endless play and export evidence |

## Run the checks

```powershell
$godot = 'C:/Users/Symok/Downloads/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script tests/campaign/run_foundation.gd
python tests/run_headless_checks.py --godot $godot --benchmark
```

Foundation checks are registered in the normal runner. New packages must register their own tests there too. Do not weaken old fixture assertions to get the new campaign through.

## Important boundaries

- Fable is a coding workflow. It is not an online dependency or a runtime character brain.
- Gameplay coefficients in the new catalog are explicit abstractions. Keep reference physiology and source-backed claims separate.
- Tell the user when deeper backend research would help, as required by `AGENTS.md`. Research is useful before finalizing agriculture balance, atmosphere zones, and aggregate time advancement.
- Nothing in this delivery is committed, pushed, merged, or deployed.
