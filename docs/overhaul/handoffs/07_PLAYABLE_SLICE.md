# Package 7: Integrate and play the first colony

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Packages 2–6 reviewed.

## Implementation

- Make the campaign discoverable from normal launch with New campaign, Continue, Load, and Legacy prototype options. Preserve the existing scene and fixture launch for regressions.
- Extend PR #10's existing title/customizer/intro flow and Tasks panel; do not replace them with a second unrelated menu or lose the existing crew customization.
- Wire manual save/load and three rotating autosaves to outer simulation boundaries. Autosave on mission-day boundaries, before major incidents and before entering a repair challenge; avoid saving recursively from simulation callbacks.
- Create a reproducible starting scenario and short integrated objective sequence that exercises building a safe camp, meals/sleep, specialist work, planting, an injured engineer, a degraded component, failed repair, full cooldown and recovery.
- Use the real command/ledger path and production UI. The scripted incidents must be idempotent and saved; test-only state injection is not a successful gameplay walkthrough.
- Add actionable status/forecast panels for reserves, zone safety, job coverage and repair readiness. Make blocked tasks explain the missing resource/person/path.
- Register all current subsystem transitions for fast-forward. Stop before health danger, treatment capacity failures, repair readiness and scripted milestones.
- Wire cross-map load preparation so the appropriate headless world is ready before atomic import; failed loads preserve the running campaign.
- Tune the initial cache and backup reserve so a novice can survive the demonstration failure without immunity or balance injection.

## Required verification

- Run an end-to-end automated UI walkthrough from New campaign to a repaired inhabited camp, with real inventory deltas and visible worker locations.
- Run alternate paths: successful first repair, failure then retry, cancel/rebuild wing, save/reload mid-objective, and continue from an autosave.
- Perform and document a manual playthrough; if unavailable, state that limitation and leave manual validation outstanding.
- Capture 720p/900p/4K evidence, check input/focus/overlays, and rerun the entire baseline. Add CAMPAIGN_SLICE_PASS.

## Completion gate

A genuinely playable early colony. It is acceptable for later progression/events to remain capability-disabled until their packages land.

Write `docs/overhaul/reviews/07_PLAYABLE_SLICE_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
