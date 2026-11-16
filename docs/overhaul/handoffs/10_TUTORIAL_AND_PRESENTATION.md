# Package 10: Continuous camp-building tutorial and complete repair variety

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 9 reviewed.

## Implementation

- Replace the campaign tutorial with the continuous setup sequence in DESIGN.md. Keep the player's colony throughout; remove the training-to-reference reset from the campaign path while preserving legacy scene tests.
- Explain one actionable step at a time, highlight the actual next control/object, and advance only from committed outcomes. Accept valid early actions; handle cancellation, invalid placement, exhausted materials, busy crew and save/resume.
- Teach the separate ship/cache, connected wings, inside versus outside equipment, utilities, sealing/commissioning, crew roles, meals/sleep, crops and reserves.
- Script exactly one near-end fault through the real event/repair system. Support successful repair or failure with a real 24-hour lockout. Teach isolation/load shedding/backup and offer safe fast-forward to retry when conditions allow.
- Finish only when the camp meets Level 1 and the fault is resolved. Skip creates an explicitly budgeted Level 1 preset using shared construction/accounting/bootstrap rules, never arbitrary UI resource edits.
- Complete the remaining pressure, oxygen, water, irrigation and medical challenge families. Keep each interaction distinct and preserve the repair framework's skill, input, pause, cooldown and accessibility rules.
- Improve cutaway readability, crew activity labels, nighttime lighting, equipment status and room affordances. Contextual help should explain choices, not developer machinery.
- Add challenge-specific sound/visual feedback with non-audio and non-color alternatives. Respect reduced motion and input focus.

## Required verification

- Walk the complete tutorial through success and failure/retry; compare the final real camp state and resources.
- Test early building, canceled jobs, skipped/resumed cards, save during each major stage, duplicate acknowledgement and skip-preset accounting.
- Input-test all eight challenge families, keyboard alternatives and slower accessibility mode. Capture 720p/900p/4K layouts with no covered controls, unreadable labels or unclickable targets.
- Register CAMPAIGN_TUTORIAL_PASS and CAMPAIGN_PRESENTATION_PASS. Document actual manual playtesting separately.

## Completion gate

An understandable first session that leaves the player in their own Level 1 camp, with a complete set of component-specific challenges.

Write `docs/overhaul/reviews/10_TUTORIAL_AND_PRESENTATION_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
