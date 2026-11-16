# Package 4: Commander controls, daily needs and visible specialist routines

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 3 reviewed.

## Implementation

- Add commander selection from the six starting astronauts and clear Commander/Overview modes. Tab toggles modes; WASD drives exactly one target. Keep mouse/keyboard camera control and selection usable, and prevent UI interaction from moving the astronaut.
- Add authoritative movement/interaction commands, interior/exterior routing and airlock transit. Render movement by interpolating committed routes.
- Add role priorities and work/meal/sleep schedules. Engineers visit equipment, medics attend med bay, botanists visit farms, geologists survey/research and logistics staff handle cargo/work staging. Pending farm/medical production uses capability checks until package 5.
- Health/fatigue stay on crew records. Store nutrition reserves, meal windows, last meal and active activity in campaign-owned needs state. Three default meals at hours 7/13/19; sleep 22–06.
- Replace shared continuous food draws only for the campaign profile: debit food at actual meals, then debit a personal reserve for nutrition use. Do not charge both. Keep oxygen/water/waste accounting valid. Model cafeteria service capacity, beds and travel.
- AI manages its meals/sleep. Commander needs manual interaction in ordinary play; visible standing orders apply only during explicit fast-forward. Add reminders, individual forecasts and blocked-reason explanations.
- Priorities: immediate danger, medical need, meal/sleep, assigned work, optional activity. Overtime is explicit and temporary. Enforce one active task and equipment reservation per astronaut.
- Support packed meals from the same ledger for excursions; consume them instead of charging cafeteria stock. If travel/medical state makes self-service impossible, report the need for assistance.
- Save all schedules, reservations, routes and needs; register transitions with the scheduler and update strict schemas.

## Required verification

- Observe each role traveling to its station and performing its activity. Pause, change assignments and reload without duplicated work or simultaneous occupancy.
- Verify three AI meals, commander reminders/manual meals, meal queues, unavailable cafeteria, missing bed, interrupted sleep, overtime and starvation progression.
- Assert inventory food is charged once, packed meals cannot be duplicated, and missed lunch does not instantly inflict starvation.
- Verify controls at 720p/900p/4K and that typing/clicking UI never moves the commander or camera unexpectedly. Add CAMPAIGN_CREW_PASS.

## Completion gate

A living camp with visible work and self-care, with a playable commander whose needs the user manages.

Write `docs/overhaul/reviews/04_COMMANDER_AND_CREW_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
