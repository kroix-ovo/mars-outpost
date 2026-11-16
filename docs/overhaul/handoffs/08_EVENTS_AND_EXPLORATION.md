# Package 8: Condition-driven random events, discoveries and cross-training

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 7 reviewed.

## Implementation

- Implement authored event definitions with prerequisites, weight, warning, duration, severity budget, response choices, cooldown and terminal resolution. Add fault, injury, illness, dust, crop contamination, salvage and discovery families.
- Seed all selection and outcomes. Persist next check time, candidate state, cooldowns and history. Evaluate at scheduled mission-time boundaries, never rendered frames.
- Start with at most two concurrent major incidents and two quiet days between major incidents. Keep positive discoveries possible during quiet periods. Tutorial pacing explicitly suppresses ordinary incident generation.
- Calculate equipment fault risk from wear, utilization, exposure, overdue maintenance and capable engineering coverage. Add a documented absent-engineer modifier with a capped combined risk. Disabled equipment cannot suffer use-related faults.
- Provide warning/diagnostic text that names risk contributors. Give storms meaningful preparation time and alternative responses; severe events cannot retroactively invent costs or remove all safety alternatives without warning.
- Add surveys, finite salvage sites, material deposits and optional contracts with capacity/time/return-reserve checks. Use actual expedition supplies and packed meals. Do not enable the old science-reference EVA profile without the missing suit inputs; campaign excursions use explicitly labeled game assumptions.
- Add seeded crew traits and cross-training jobs that consume labor and cap secondary ability below native specialists. Traits are bounded tradeoffs, not arbitrary resource multipliers.
- Add wear/maintenance completion and interruptions; medicine/coverage changes must feed future risk. Save all site depletion and discovery rewards with receipts.

## Required verification

- Same seed/actions produce the same incident order before and after load and through different render frame rates.
- Compare matched scenarios with healthy versus injured engineering coverage; assert exact risk modifiers and distribution behavior across many seeds.
- Verify incident caps, quiet periods, invalid candidates, cooldowns, warnings, response affordability and positive events.
- Test depleted salvage, recalled expeditions, insufficient meals/suit reserves, double contract claim and interrupted training. Add CAMPAIGN_EVENTS_PASS.

## Completion gate

Replayable events caused by the colony's state, plus exploration and training that provide useful recovery and progression choices.

Write `docs/overhaul/reviews/08_EVENTS_AND_EXPLORATION_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
