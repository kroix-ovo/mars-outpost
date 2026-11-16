# Package 11: Balance, complete campaign verification and release readiness

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Packages 2–10 reviewed.

## Implementation

- Run the complete two-year campaign through real production commands and at least two upgrade strategies. Include low-resource recovery and an injury-driven maintenance problem. Continue beyond the ending into another delivery.
- Run a reproducible multi-seed balance sweep with a versioned policy harness. Report survival, crew losses, incidents, food/power shortages, upgrade choices, cargo use and unrecoverable states. This is simulation evidence, not a replacement for human play.
- Benchmark one day, 180 days and 720 days. Report aggregate/detail work, frame responsiveness and save size. Optimize only with equivalence and event/RNG ordering preserved.
- Add migrations/explicit rejection tests for every supported development/release save version and content manifest. Fault-inject partial writes, corrupt primary/backup, changed definitions, stale sessions and callback reentrancy.
- Verify all capabilities correspond to available real gameplay. Remove development-only launch assumptions from the player flow and ensure diagnostics cannot grant resources.
- Build/export native and intended browser targets using installed templates if available. Test the actual exported build. Browser saves must be exercised on the real host; do not claim IndexedDB persistence from native tests.
- Perform manual tutorial and free-play sessions, capturing usability failures and fixing them. Keep automated screenshots, manual evidence and simulated policy sweeps clearly separated.
- Update the main README, controls, campaign science/assumption notes, attribution for new assets and release limitations.

## Required verification

- Full existing headless suite plus all campaign suites pass. No lowered fixture thresholds or replaced deterministic expectations.
- Same seed/commands/save reproduce discrete outcomes and continuous state within stated tolerances. Every reward/cost/harvest/delivery is exactly once.
- Publish a local review report with commands, engine/template versions, logs, balance inputs, seed list, screenshots and exported-build smoke results.
- Unavailable templates, browser hosting or manual testers must be reported as outstanding release gates, not silently marked passed.
- Add CAMPAIGN_RELEASE_PASS only for checks actually automated; human/browser gates have separate explicit status.

## Completion gate

An evidenced release candidate. Do not publish, merge or deploy as part of this package without separate user instruction.

Write `docs/overhaul/reviews/11_CAMPAIGN_VALIDATION_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
