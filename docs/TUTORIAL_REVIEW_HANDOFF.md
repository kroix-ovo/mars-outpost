# Interactive tutorial mission: review handoff

Branch `codex/tutorial-mission` in `C:/Users/Symok/Documents/Nasa_Space_Apps_Tutorial`, based on `f9e9f63`. Implementation commit: `f965320`; this handoff is committed separately on top. Nothing was pushed, merged or exported, and no long-lived game was launched.

## What the player sees

**Fresh launch.** The game opens paused on a centred welcome card with one prominent amber **Start tutorial** button, which is the only thing pointed at. **Skip to free play** is a quiet secondary text button. The card says plainly that this is the training colony with practice numbers. This addresses the playtester's "I didn't know what to click first".

**One step at a time.** Each step is one card. Every card has:

- progress ("First shift (training) · step 7 of 21");
- a short title and two or three conversational sentences;
- **YOUR MOVE**: the exact next action;
- a **Why** line;
- a green "✓ previous step" acknowledgement when the player advances.

**Exactly one pointer.** A pulsing amber outline with an arrow points at the single next action: a crew row, a tab, a drawer control, a speed button, or a projected world target (habitat, salvage flag, recommended placement square, construction, repair). When a step is waiting for the card's own Next or Start button, the pointer goes to that button. What the step is talking about then gets only a quiet ring or outline with no arrow.

**Keeping the action visible.**

- Targets inside drawer pages are scrolled into view.
- The EVA page now leads with a plain-language safety summary ("Safe to launch. Each astronaut should come home with about 33% of their suit oxygen…"), with **Launch** directly below it. Editable supplies and the per-phase forecast are behind **Show supplies and forecast details**.
- Steps that point into the world use a wide, short card, placed on the half of the screen away from the target.

**The taught loop.** Training (21 steps):

1. Welcome, then habitat and supply strip.
2. Pick a named astronaut, then Ctrl/Shift-click a second (an "Add … for me" helper exists but stays secondary).
3. Explain spacewalks, open EVA, read the safety forecast, launch.
4. Start the clock, then watch outbound, working and returning (the text follows the live phase).
5. Crew home, with the actual alloy and electronics totals.
6. Open Build, choose storage, **Choose a cell on the map**, click the glowing valid square (R rotates, Esc cancels; green/red explained).
7. Open Jobs, choose the construction job, Suggest crew, Assign.
8. Run time, and watch construction percentage.
9. "Storage online!" with the real oxygen capacity before and after.
10. Training complete, with an explicit **Go to reference colony**, which says it starts that colony from scratch.

Reference (9 steps for the current colony):

1. Reference welcome, paused. The damaged-machine count is derived from the colony's starting repair jobs (currently one). The card states that crew consumption follows researched reference rates while equipment output is a game assumption, and that spacewalks are off because suit budgets are not researched yet.
2. Open Systems, then read it.
3. For each starting repair: open Jobs, choose "Repair · Solar Array", Suggest, Assign, run until done.
4. Mission debrief and **Finish tutorial**, which leaves free play.

The **Guide** tab shows the checklist for the current colony, **Resume tutorial** (after a skip) and **Restart tutorial**, which clearly restarts from a fresh training colony.

## Honesty and safety rules

`scripts/ui/tutorial_mission.gd` is read-only. It derives the current step from the committed snapshot plus live UI state (selection, open tab, placement mode, forecast result).

- **What the tutorial changes.** It only stores which explanations were acknowledged, and a baseline of what the colony started with. The only commands it causes are a `set_time_scale 0` pause when a tutorial colony starts and the player-requested colony restarts, all through the facade.
- **What it never touches.** No balances, tasks, ledger entries, science data or the shared spec are touched, and Next buttons exist only on explanation steps.
- **Evaluation.** Steps are evaluated in order on every refresh, and each step's done test also accepts later real outcomes. Acting out of order therefore never deadlocks, and losing a precondition (deselecting crew, cancelling construction) moves back to the right step.
- **Storage wording.** The storage explanation is read from the module definition (synthetic storage adds 100 kg of oxygen capacity only).

## Recovery paths

Each of these stays on a reachable step with an understandable hint:

| Situation | Response |
|---|---|
| One astronaut sent | 3 items is not enough. "you have 9 alloy and 2 electronics; storage needs 10 and 2. Send two astronauts…" |
| Empty recall | "recalled before it collected anything. Send another one." Shown on whichever spacewalk step is current. |
| Failed trip | Explained, and the salvage loop restarts. |
| Busy astronaut selected | Asked to pick an idle one. |
| Unsafe forecast | Forecast reason, and Next is disabled. |
| Blocked placement cell | "That spot will not work: …" |
| Wrong module in placement mode | Press Esc first. |
| Rejected command | Its reason is shown on the step where it happened. |
| Cancelled construction | Refund verified; back to placing storage. |
| Cancelled or failed starting repair | Its substeps are replaced by "Repair job cancelled" with **Restart reference colony** (Codex finding 3, regression-tested with a real `cancel_task`). |
| Drawer collapsed | Points at «. |
| Simulation tick failure | **Restart this colony**. |
| Training materials impossible | **Restart training colony**. |
| Out-of-order actions, scenario restart (F2/F3, button), skip/resume | Steps re-derive from the snapshot. |

## Codex review notes addressed (`docs/TUTORIAL_CODEX_REVIEW.md`)

1. The damaged count is derived from the baseline repair jobs, so it now reads "One machine starts damaged". This is tested.
2. Storage copy comes from `storage_capacity` and says oxygen only. Tested: no "water".
3. Cancelled repairs no longer deadlock on Assign. Regression: real Cancel job, then a `_lost` step with a restart button and no Assign action; restart restores the job.
4. Reference copy no longer implies every equipment number is researched.
5. Fresh launch was verified at both resolutions: exactly one pointed action, Start tutorial, without needing to find the Guide tab.

## Files

| File | Change |
|---|---|
| `scripts/ui/tutorial_mission.gd` | **New.** Read-only step machine, recovery logic, debrief |
| `scripts/ui/tutorial_overlay.gd` | **New.** Pulsing pointer, context rings and world labels; ignores mouse input |
| `scripts/ui/outpost_hud.gd` | Tutorial card, target resolution, scroll-into-view, Guide resume/restart and a public test hook (`tutorial_press`, `tutorial_step`). EVA page reordered (summary, then Launch, then details toggle). A newly launched trip becomes the selected expedition, so Recall targets it (previously it kept the old, finished trip). Site and trip lists show "Cargo cache" and "Trip 2" instead of developer IDs; buildings show "Solar Array · #1". Codex's crew-card checklist removed. |
| `scripts/world/main_world.gd` | Enables the tutorial. Passes the camera projector, habitat point, placement mode/preview and simulation failures to the HUD. Explicit training/reference restart signals. Placement mode now ends after a successful map placement, so a second click cannot place another module by accident. |
| `scripts/ui/first_shift.gd`, `tests/crew_ui/run_first_shift.gd`, `tests/visual/run_first_shift_layout.gd` (+ `.uid`) | **Removed**, superseded. `docs/FIRST_SHIFT_INTEGRATION.md` is marked superseded. |
| `tests/crew_ui/run_tutorial_mission.gd` | **New.** Headless full-loop and recovery test (`TUTORIAL_PASS`), registered in `tests/run_headless_checks.py` in place of `FIRST_SHIFT_PASS` |
| `tests/visual/run_tutorial_layout.gd` | **New.** Rendered walkthrough with layout assertions and evidence |
| `tests/visual/run_hud_input_probe.gd`, `tests/visual/capture_visual_evidence.gd`, `tests/world/run_integration.gd` | Updated stale expectation: they test free play with a running clock, so they call `tutorial_press("skip")` first. Without it, the tutorial correctly pauses the reference colony and the integration power checks see no tick. All assertions are unchanged. |
| `tests/visual/README.md`, `README.md` | Documentation |
| `docs/evidence/tutorial/{1280x720,1600x900}/*.png` | Rendered evidence |

No change to `scripts/simulation`, `scripts/systems`, `scripts/tasks`, the crew adapter, `data/`, fixtures, `SHARED_SIMULATION_SPEC.md` or `project.godot`.

## Validation

All runs used Godot 4.7.2 (`C:/Users/Symok/Downloads/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`) after `--headless --editor --import --quit` in this checkout. Rendered runs used `--audio-driver Dummy`.

| Check | Result |
|---|---|
| `python tests/run_headless_checks.py --godot <console> --benchmark` | **HEADLESS_PASS** (details below) |
| `tests/crew_ui/run_tutorial_mission.gd` (headless, in the runner) | **TUTORIAL_PASS**, 89 checks |
| `tests/visual/run_tutorial_layout.gd` at 1280x720 and 1600x900 (windowed) | **TUTORIAL_LAYOUT_PASS**, 115 checks each |
| `tests/visual/run_hud_input_probe.gd` at 1280x720 and 1600x900 | **HUD_INPUT_PASS**, 18 checks each |
| `tests/visual/capture_visual_evidence.gd` at 1280x720 (free play, tutorial skipped) | EVIDENCE_DONE; storage commissioned (oxygen capacity 300) and repair completed. Its existing PNGs were restored, not recommitted. |
| `generate_fixtures.py --check` / `generate_integration_scenario.py --check` / `generate_a3_profile.py --check` | 85 fixtures up to date / AUTHORED_FIXTURES_PASS / A3_PROFILE_PASS |
| `git diff --check` | clean |

The headless runner results, all with exit 0:

- world 679;
- A1 14,298;
- A2 41,144;
- A3 6,718;
- integration 54;
- bridge 17;
- crew UI 85/85;
- A3 crew;
- tutorial;
- A1 benchmark 36,570;
- main-scene boot.

**What the gameplay test asserts.** It uses the real main scene, HUD handlers and production simulation, with no injected progress or balances:

- **Fresh launch:** paused, with Start tutorial as the single pointed action. Selecting crew before Start does not skip the welcome. Orientation points only at Next, with the habitat as context.
- **Drawer and skip:** the collapsed drawer is explained and its toggle pointed at; skip hides the tutorial and resume continues.
- **Failed tick:** it offers a restart; the restarted colony starts paused.
- **Salvage:**
  - a one-astronaut trip really returns 9 alloy, and the card explains the shortfall;
  - the new trip is selected for Recall, and the recall truly returns empty before any work;
  - the full two-astronaut trip goes through outbound, working and returning, reaching alloy 10 or more with electronics 2 or more;
  - Launch stays inside the visible drawer.
- **Build:**
  - storage text mentions oxygen and not water;
  - a blocked cell is explained;
  - placement spends materials and ends placement mode;
  - a real Cancel job refunds the materials and returns to building;
  - Suggest and Assign commit a real assignment;
  - commissioning really increases oxygen capacity, and the built card reports it.
- **Reference colony:**
  - an explicit restart loads it paused;
  - the damaged count matches its jobs, with no hard-coded "Two";
  - opening Systems advances;
  - a real cancellation of the starting repair produces the `_lost` recovery step with Restart and no Assign action, and restarting restores the job;
  - every starting repair completes with condition 1.0;
  - the debrief's Finish leaves free play.

## Evidence screenshots

Nineteen PNGs per size, in `docs/evidence/tutorial/1280x720/` and `docs/evidence/tutorial/1600x900/`:

- **Training:** `01_welcome`, `02_habitat_and_supplies`, `03_select_astronaut`, `04_add_second_astronaut`, `05_open_eva_tab`, `06_safety_forecast`, `07_launch_visible`, `08_watch_spacewalk`, `09_crew_home`, `10_place_on_map`, `11_assign_builder`, `12_construction`, `13_storage_online`, `14_training_complete`.
- **Reference and finish:** `15_reference_welcome`, `16_reference_systems`, `17_reference_repair`, `18_debrief`, `19_free_play`.

## Decisions taken without asking

- **Where it runs.** The tutorial runs only in the main scene (`enable_tutorial`); HUD harness tests stay tutorial-free.
- **Acknowledgements.** They persist across a training restart (welcome and orientation are not replayed), and reset per colony for the "home", "built" and reference explanations.
- **Jumping ahead.** F3 during training jumps straight to the reference steps rather than blocking.
- **Placement mode.** It ends after a successful placement. This is a small free-play behaviour change, made to prevent accidental double placement.

## Known gaps

- No human playtest and no audio verification. The checks use scripted input through HUD handlers and the placement controller, not a person with a mouse.
- The recommended placement square is computed east of the airlock. If the camera is rotated so it is off screen, the pointer disappears until the player pans back; the card text still explains the action.
- On the "Watch the spacewalk" step the pointer follows the crew; their walking animation is presentation-only.
- **Encoding:** `README.md` at `f9e9f63` already contains a Windows-1252 "×" byte (`0xD7`) in "1280×720". I edited it byte-preserving and did not re-encode the file.
- Export and web builds were not produced or checked (Codex owns export).
