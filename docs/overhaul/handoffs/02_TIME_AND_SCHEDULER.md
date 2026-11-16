# Package 2: Mission clock, scheduler and safe advancement

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Implemented foundation (packages 0–1).

## Implementation

- First read PR #10's `docs/TIME_AND_MISSION_HANDOFF.md` and `docs/MISSION_TASKS_AND_FRAME_PACING.md`. Reuse the existing `advance_budgeted`/8 ms yielding path and retained backlog. Preserve legacy 60/120/240 pacing and mission/task UI. Add 120x normal pacing only for the new campaign, without multiplying time twice through the wrapper and facade.

- Add mission-day/month/shipment calendar queries and a persisted scheduled-boundary queue with deterministic ordering. Default paused campaign start; normal simulation speed 120x with 1x/5x/20x player multipliers. Keep the old fixture time scales unchanged.
- Add strict v3 request_fast_forward(target_elapsed_s) and cancel_fast_forward commands, committed target and stop reason, and bounded work per frame. Paused command processing must still work.
- Keep detailed one-second stepping as an oracle. Define registerable system hooks for next transition, detailed interval, and safe aggregate interval. Stable flows can aggregate only when no lifecycle, route, saturation, production fraction or hazard threshold changes inside the interval.
- Implement aggregate power/life-support/demand for the currently supported campaign systems where mathematically equivalent. Split at reserve exhaustion, battery/full-storage saturation, travel/work completion, calendar and scheduled events. If a model cannot safely aggregate, retain detailed stepping and show that limitation rather than skipping it.
- Future packages register their transitions against this scheduler. Preserve exact RNG draw/event ordering. Do not draw random outcomes per rendered frame.
- Add a campaign-specific content/profile path; existing fixture science/clock semantics stay unchanged. Until that campaign scene exists, exercise the new facade in a headless harness.
- Persist accumulator, target, event ordering and pending transitions. Update empty-only campaign schema guards and explicit development-save migration policy where required.

## Required verification

- Compare ordinary and aggregate advancement for a stable day, a week, and the first 180-day boundary. Continuous quantities use documented abs/relative tolerances; IDs, commands, discrete events and RNG continuation must match exactly.
- Include battery saturation, production shortages, storage overflow, paused queues, cancellation, invalid/earlier target, save mid-fast-forward, and bounded frame work.
- Do not require a simulated 180-day habitat to survive when food/agriculture are not installed. Use declared sustainable test conditions and report this boundary.
- Record wall time, simulated duration, detailed tick count, aggregate interval count and maximum wrapper-frame work. Add CAMPAIGN_TIME_PASS to the normal runner.

## Completion gate

A deterministic, checkpointable time foundation that future jobs and hazards can use; fast-forward capabilities must distinguish implemented integration from fallback detailed stepping.

Write `docs/overhaul/reviews/02_TIME_AND_SCHEDULER_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
