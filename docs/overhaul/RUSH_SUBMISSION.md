# Submission build: one integrated delivery

## This instruction replaces the sequential package workflow for tonight

The user needs a playable submission by 11:59 PM America/New_York on November 15, 2026. At preparation it was approximately 8:35 PM, leaving about 3 hours 24 minutes. The original full overhaul remains the long-term design. Do not require ten more sessions or review gates before delivering this submission build.

Work in `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`. Preserve PR #10's title screen, crew customization, input controls, frame-budget protections and the existing dirty foundation work. Do not overwrite the original checkout. Do not publish or send a submission automatically.

If currently implementing Package 2, first leave that work in a compiling, testable state. Stop adding general-purpose scheduler abstractions and six-month aggregate optimization. Reuse existing budgeted advancement. Then implement the submission sequence below in this same session. Intermediate review handoffs are waived for this delivery.

## Deliver the visible playable loop first

Use the existing Godot presentation, HUD, models, real simulation and ledger. Avoid a rewrite. Keep one simulation authority and one active inventory. Use the v3 path if the current work is ready; otherwise extend the existing transactional path with the minimum coherent changes. Never connect a display-only campaign inventory to working legacy equipment.

### Priority 1: build and inhabit a separate camp

- Keep the ship as a distinct landed object and temporary shelter. Place a construction cache and a small connected camp beside it.
- Provide a short guided objective to construct/commission living, service and farming wings. Use authored wing layouts with visible cutaway interiors to save implementation time; free furniture arrangement can wait.
- Make farm, bunks, cafeteria and med bay visibly interior. Solar, battery and generator are outside. Build costs and refunds must use the existing ledger.
- Allow the player to place at least the farm, generator and solar equipment. Commissioning requires completed work and a connected safe camp. Show a clear Level 1 completion milestone.
- Start with enough declared materials and backup resources to finish this sequence and survive one failed repair. No hidden grants or fabricated progress.

### Priority 2: make the crew matter

- Engineers perform actual maintenance jobs at equipment; botanists work at farms; medics attend the med bay. Use existing path/task machinery and simple work animations.
- Add a concise crew panel showing health, hunger and fatigue. AI eats/rests through scheduled activities; use visible Eat/Rest commands for the selected player astronaut if full direct-control mode cannot be completed safely.
- Food comes from actual stock. Implement one functional farm crop/yield cycle before adding crop variety. Avoid charging both meal food and the existing continuous shared-food drain.
- Add one real injury episode: the injured engineer goes to treatment and stops work. Other assigned workers incur extra fatigue from actual coverage, or work remains visibly queued. Recovery occurs after the configured one-to-seven-day duration.
- If time is short, complete the actual role/job consequences before adding elaborate movement modes, traits or medical submenus.

### Priority 3: a memorable repair challenge

- Build two genuinely different component interactions: circuit reconnection for an electrical component and alignment/timing calibration for solar equipment. Original Among Us-inspired tasks, with keyboard alternatives and symbols as well as colors.
- Pick the repair astronaut. Engineering skill gives fewer stages, clearer hints or wider tolerance. Use a saved simulation-owned session; UI input must not directly set success.
- Freeze colony time while the challenge is open. On failure, set the component fully broken and enforce a component-wide 86,400-simulated-second lockout. Switching crew or routine maintenance cannot bypass it.
- Show the retry countdown, backup option and repair result. Costs/results apply once. Successful repair restores functionality.
- Near the end of the tutorial, trigger one controlled fault through this real system. Both success and failure must leave a reachable path to completion. A failure can end the first-session demonstration on a clear recovery objective rather than trapping the player in a modal.

### Priority 4: finish the tutorial and submission flow

- Replace the visible tutorial's salvage/storage-first sequence with arrival, build/place essentials, assign specialists, establish safe camp, plant/operate farm, resolve or stabilize the fault, and reach Level 1. Keep the player's colony throughout.
- Accept actions done early. Handle canceled construction and invalid placement with actionable hints. Tutorial acknowledgement cannot spend resources or complete simulation jobs.
- Make the new loop available through normal launch. Preserve the existing title/customizer assets rather than building a second menu.
- Keep manual save/load and native autosave only if their scene wiring and current schemas pass tests. If a feature is unavailable, disable its button with honest wording.

## Stretch work only after the loop plays

1. Add seeded occasional fault/injury events with a quiet interval and at most one major incident during the short demonstration.
2. Add one visible, functional farm or solar upgrade with a real cost and measurable effect.
3. Show the next six-month supply arrival and a simple cargo choice only if delivery/accounting also work. Otherwise label this as planned; do not pretend the two-year campaign has been validated.
4. Add more crops, challenge families and advanced room furnishing only if all higher priorities are complete.

The submission does not need Mk I–III across every component, eight challenge families, full cross-training, a 720-day balance sweep, sophisticated zone gas splitting or ironclad browser persistence tonight. Keep those requirements in the existing roadmap. Clearly report which features shipped and which remain planned.

## Time gates (Eastern; use remaining time, not wishful estimates)

- By 9:30 PM: launchable separate-camp construction loop. If late, use authored room interiors and reduce art work.
- By 10:15 PM: specialist routines, one farm cycle, injury consequence and two repair interactions work through real state.
- By 10:45 PM: tutorial and Level 1 path are connected. Stop adding features.
- 10:45–11:15 PM: actual playthrough, fix blockers, run focused tests and the existing suite.
- By 11:15 PM: freeze features and create the requested/native submission artifact using installed export templates. If templates are unavailable, report that immediately and provide the clean source project plus concrete export instructions; never claim an executable exists.
- By 11:35 PM: launch the exported artifact, check controls and complete the critical sequence. Write a short README and known-limitations list.
- Keep the remaining buffer for the user's upload/submission. Do not use all available time polishing.

If these times have passed when reading, reduce stretch scope immediately. Preserve the working build over unfinished features. Do not silently remove a completed working feature.

## Minimum evidence

- Game launches from its normal menu and through the actual exported artifact if produced.
- Construction spends/refunds correctly; farming produces real food; specialist jobs affect real progress.
- The injury removes real labor and treatment/recovery have actual state.
- Both repair interactions run, engineering changes difficulty, failure enforces the full one-day component lockout, and success is applied once.
- Tutorial can reach Level 1 after a successful repair and can recover after failure/cancellation.
- No parse/script errors. Run `tests/run_headless_checks.py` and new focused tests. Preserve prior assertions; report unresolved failures.
- Capture a few actual gameplay screenshots at a usable desktop resolution. State whether manual playtesting was performed. Avoid spending the deadline generating exhaustive 4K evidence.

## Final handoff

Produce one `docs/overhaul/reviews/SUBMISSION_REVIEW.md` containing implemented features, exact launch/export artifact paths, controls, test results, known limitations and the remaining roadmap. Do not generate nine intermediate handoffs. Stop with a launchable project/build ready for the user to submit; do not publish, merge or upload without an explicit instruction.
