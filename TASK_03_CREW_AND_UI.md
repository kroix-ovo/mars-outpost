# Task 03 — crew management, EVA, and player interface

## 1. Executive summary

Make the colony feel inhabited and give players the tools to command it. Build individual astronauts, job assignments, farming/repair/construction work, oxygen-limited salvage expeditions, and the interface that explains their consequences.

Use simple readable behavior, not complex autonomous AI. The first milestone is selecting a crew member, assigning a useful job, and seeing its authoritative progress in the HUD.

## 2. Mission

Connect the player's decisions to visible crew actions and understandable outcomes. Keep assignments interruptible, expedition reserves explicit, and interface information consistent with the simulation.

## 3. Users

Serve players managing 5–9 astronauts, especially learners who need clear actions and warnings. Provide reusable scenes and state adapters that the world and simulation owners can integrate independently.

## 4. Coverage

- [ ] Crew setup, skills, health/fatigue, individual selection, movement, and assignments.
- [ ] Task scheduling, farming, repairs, construction labor, salvage, EVA planning, and recall.
- [ ] HUD, forecasts, build controls, crew panels, tutorial, alerts, audio, and save/load controls.

Task 01 owns shared accounting and save format; Task 02 owns terrain/navigation services, world building scenes, and deployment. Keep their boundaries explicit while implementing crew behavior.

## 5. User stories

1. As a commander, I want to select an astronaut and assign farming so I can improve food supply.
2. As a commander, I want to compare skills and fatigue so I can choose who repairs life support.
3. As an explorer, I want outbound/work/return oxygen forecasts so I can judge a salvage trip.
4. As an operator, I want to recall an expedition so I can react when reserves change.
5. As a learner, I want to inspect the oxygen chain so I can understand why production stopped.
6. As a player, I want clear controls, time settings, and saves so I can manage at my own pace.

## 6. Architecture and ownership

Own `scripts/crew/`, `scripts/tasks/`, `scripts/ui/`, `scenes/crew/`, `scenes/ui/`, `data/crew/`, `assets/audio/`, and `tests/crew_ui/`. Build isolated crew and UI harness scenes; Task 02 mounts them in the main world.

Implement crew/task/EVA state adapters within owned scripts and register them with Task 01's tick/save orchestration. Use Task 02's path queries and stable entrances/site IDs. UI submits commands and reads snapshots; it never changes stockpiles. Coordinate exactly once accounting for metabolism, suit transfers, cargo rewards, and construction completion.

## 7. Six work packages — 24 initial points

| Package | Deliverable | Initial points |
|---|---|---:|
| C1 | Crew definitions/setup for 5–9, selection, reusable crew scenes and state adapters | 4 |
| C2 | Skill/priority/fatigue scheduler, movement, construction/farm/repair job lifecycle | 4 |
| C3 | EVA planning, oxygen/battery/return margins, salvage travel/work/cargo, recall | 4 |
| C4 | HUD/resource detail, crew/task panels, building actions and time controls | 4 |
| C5 | Onboarding, oxygen-flow explanation, alerts, save/load controls and audio feedback | 4 |
| C6 | Assignment/EVA edge cases, usability checks, save adapters and integration fixes | 4 |

Keep visual complexity modest until behavior integrates. Rebalance UI polish against world polish if observed effort differs.

## 8. Stack

Use the shared pinned Godot 4 version, typed GDScript, reusable Control-based panels, and lightweight crew scenes. Use deterministic priority rules with stable tie-breaking. Do not introduce machine learning for scheduling.

## 9. Configuration and safety

Reject assignments to unavailable crew or unreachable destinations. Validate saved crew/task/expedition records. Pause and cancellation must not grant rewards or bypass costs. Record provenance for added audio; send records to Task 02 for attribution consolidation.

## 10. Interface

Consume shared snapshots and submit `assign_task`, `cancel_task`, `start_eva`, `recall_eva`, building, and time-control commands through the common interface. Publish registered tick/save adapter requirements during the contract pass. Report blocked tasks and recall failure reasons visibly.

Use route-derived travel time and Task 01's documented resource parameters for EVA forecasts. Include outbound, task, return, and emergency margin. Update forecasts when work, route, or environmental conditions change. Rendering movement must not independently advance authoritative travel time.

## 11. Acceptance checks

- [ ] Players can inspect and assign individuals in 5-, 6-, and 9-person colonies.
- [ ] One astronaut cannot execute incompatible simultaneous jobs; cancel/reassign leaves no stuck reservations.
- [ ] Construction, repairs, and farming apply their completion effects exactly once.
- [ ] EVA planning rejects trips outside policy reserve limits and shows why.
- [ ] Recall handles outbound and working teams; unreachable return or exhausted reserves produces an explicit state.
- [ ] A saved active job/expedition resumes without duplicating cargo, crew, or resource deductions.
- [ ] HUD rates match simulation snapshots, and oxygen warnings identify relevant upstream failures.
- [ ] A new player can assign work, construct a module, and plan/recall salvage using in-game guidance.

## 12. Phases

1. Deliver C1 and fixture-driven crew/UI harnesses; agree task/EVA state schemas with Task 01.
2. Integrate C2 and a basic C4 HUD with Task 02 routes and construction.
3. Connect C3 and C5 to the real resource model and save adapters.
4. Complete C6, observe a new player, resolve blockers, and support export verification.

Use the shared phase effort proportions; estimate calendar dates after availability and first-loop progress are known.

## 13. Expansion

Extend medical care, morale, cross-training, rover crews, complex expeditions, richer tutorial scenarios, accessibility controls, and advanced management views through the same crew/task/UI systems.

## 14. Risks

Crew/UI breadth can overload this track: use simple movement and reusable panels first, then rebalance polish. Unclear time ownership can desynchronize expeditions: use the authoritative clock. Hidden automation can frustrate players: show task reasons, priority, and blocked status.

## 15. Handoff

Use branch `feat/crew-eva-ui`. Return changed paths, check commands, assignment/EVA scenarios, reusable scene mount instructions, and known assumptions. Coordinate contract changes before editing dependent code. See `PRD.md` for overall acceptance criteria.
