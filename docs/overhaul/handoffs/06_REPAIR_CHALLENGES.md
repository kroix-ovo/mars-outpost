# Package 6: Component-specific challenges and the repair lockout

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 5 reviewed.

## Implementation

- Implement a simulation-owned repair state machine: queued, travel/preparation, ready, active challenge, success/failure, cooldown. Reserve one operator and needed parts. Routine maintenance stays automatic; corrective repairs use the challenge.
- First playable families are circuit tracing, solar calibration and generator stabilization. Their interactions must differ, not just text/colors around the same button.
- Use original Among Us-inspired presentation with short readable tasks. Engineering skill supplies fewer stages/better hints/slower drift/wider tolerance. Publish the exact skill bands and accessibility multipliers in data.
- The UI submits session-scoped, sequenced actions; the simulation checks them against saved challenge state. Never accept a player-supplied success boolean. Generate challenge parameters once from the campaign seed and persist them.
- Pause colony time during a challenge. Advance only bounded active challenge time from a focused wrapper; persist remaining timer, sequence and puzzle state. Ignore input after terminal resolution.
- Failure sets building.condition to zero and records retry_at_s = current_elapsed_s + 86400. Corrective repair and ordinary maintenance must not restore that component during cooldown; changing operator cannot bypass it. Spent attempt materials stay spent.
- Success restores functionality once, releases reservations and commits costs/completion once. Closing the challenge offers resume or explicit abandon-as-failure; quitting/loading resumes the same state.
- Show repair operator/engineering advantage, component-specific instructions, costs, retry time, and fallback choices such as isolation/load shedding/redundancy.
- Provide keyboard controls, labels/symbols and a slower accessibility mode. Do not rely on color or audio alone.

## Required verification

- Complete each of the three different puzzles through real input. Compare engineer/non-engineer stage/tolerance data without relying only on screenshots.
- Fail degraded and already broken components, test retry at 86399 and 86400 seconds, swap crew, and attempt routine-maintenance bypass.
- Save during preparation, active challenge and cooldown. Reload retains puzzle/timer/RNG and does not charge or reward twice.
- Verify UI focus loss, pause state, modal close, duplicate input, stale session, invalid action and changed operator. Add CAMPAIGN_REPAIR_PASS and rendered input evidence.

## Completion gate

Three real repair challenge families with component-wide one-day failure consequences and a reusable framework for the other five.

Write `docs/overhaul/reviews/06_REPAIR_CHALLENGES_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
