# Finish the submission loop

Read this after the current final suite finishes. At review it was approximately 9:17 PM Eastern, November 15, with a deadline of 11:59 PM. Do not spend the remaining session on more long-horizon scheduler work. Preserve the functioning farm, challenges, injury and original title/customizer.

The current SUBMISSION_REVIEW is candid: the core separate-camp presentation, specialist routines and replacement tutorial are missing, and the feature loop requires F3. Focus this pass on those player-visible gaps, then validate the exported executable.

## 1. Normal launch must reach the submission loop

- Add a clearly named camp mission option to the existing title/new-game flow, or make the new camp mission the documented default. It must launch the profile that supports the greenhouse. Do not require F3, diagnostics, a scene override or hidden knowledge.
- Retain legacy training behind a clearly named secondary option. Preserve crew customization and introduction where compatible.
- Add short objective cards for building the farm, assigning construction crew, establishing utilities, watching real production, choosing a repair astronaut, repairing/stabilizing a fault and earning Level 1.
- Use committed conditions, not acknowledgement-only progress. Show recovery hints for cancellations, unaffordable placement and failed repair. Keep the player's world throughout.
- Do not require the player to intentionally damage equipment through a debug-looking Fault drill button to discover the main mechanic. Trigger the tutorial incident once at an appropriate committed milestone and retain the manual drill as an optional training action.

## 2. Make the camp recognizable within the current architecture

- Keep the ship physically separate. Use authored living, farming and service wings with cutaway interiors and existing lightweight procedural art; freeform furnishings and sophisticated gas-zone splitting can wait.
- Show the farm inside the farming wing, beds/cafeteria in living space and treatment station in service space. Solar/generator/battery stay outside.
- Make construction/commissioning and operating state real. Do not draw a second camp that disagrees with building footprints, pathfinding, resource transactions or actual job destinations.
- If a safe full room model cannot be completed, prefer a smaller authored interior with accurate occupancy/state and disclose the remaining limitation. Do not replace the functioning colony with a non-interactive mockup.

## 3. Show specialist work and injury care

- Reuse the existing crew/task movement machinery. Engineers visit actual equipment for maintenance, a botanist tends the farm and a medic attends the treatment station. Reserve actual labor; walking animations alone do not satisfy a specialist job.
- Send the injured operator to treatment/rest instead of leaving them standing at work. They remain unavailable until recovery.
- Give the player one clear interaction for assigning a specialist and one useful status explanation for absent coverage. Preserve the real injury and repair-lock rules.
- Do not attempt the full hunger/sleep/medical simulation if it would compromise the working build. Report omissions honestly.

## 4. Save and exported-build integrity

- The current review says faults, cooldowns and injuries are absent from quick saves. Either add validated persistence for those exact records and roundtrip tests, or disable the unsupported save/continue route in the submission flow with clear wording. Do not advertise saving that loses active failures.
- After changes, export a new Windows executable. Record its actual path, timestamp and hash; the earlier executable is not evidence for later source changes.
- Drive the executable from its real title menu into the camp, open the objectives, build/assign the farm, and play a repair using normal mouse/keyboard input. Project-level HUD-handler automation and a 240-frame title boot are useful evidence but do not establish this exported path works.
- If manual playtesting cannot be done, state that explicitly and give the user a short exact click sequence to verify before uploading. Do not mark the exported loop passed based only on a title-screen boot.
- Update SUBMISSION_REVIEW with final test output, screenshots, shipped features and limitations. Remove the @@TESTS@@ placeholder once results exist.

## Time bounds

- Aim to have camp launch/layout and objective flow connected by 10:15 PM.
- Stop feature work at 10:45 PM. If the remaining time is shorter, prioritize normal launch/objectives and export correctness over added visual scope.
- Use focused tests for changed behavior; the current full suite establishes the existing baseline. Do not rerun a 180-day oracle or repeatedly spend nine minutes on unchanged scheduler code.
- Re-export and exercise the artifact by 11:15 PM. Keep the rest for fixes and the user's upload.

Deliver one final review and the tested artifact. No intermediate package sessions are required. No upload, publication, merge or message to others is authorized by this file.
