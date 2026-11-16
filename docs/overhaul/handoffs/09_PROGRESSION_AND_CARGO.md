# Package 9: Research, meaningful upgrades and six-month shipments

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 8 reviewed.

## Implementation

- Implement the five camp-level capability milestones in DESIGN.md. Persist earned levels/unlocks; temporary breakdowns do not repeatedly revoke them. Day 720 completes the settlement milestone and leaves the campaign running.
- Add research jobs funded by science earned from surveys, experiments, crop trials and contracts. Require labor/station access; research unlocks designs, not physical items.
- Implement Mk I–III hardware and one replaceable specialization slot per component. Use the branches in DESIGN.md; catalog choices must each produce measurable simulation changes and a tradeoff/opportunity cost.
- Upgrading consumes local materials, scarce kits, installation labor and downtime. Preview before commit, validate affordability again on resolution, and define partial/cancel salvage. Do not let upgrades restore a component to bypass a repair cooldown.
- Implement beans, tomatoes and medicinal crops with research plus imported seed prerequisites. Seed propagation, variety benefits and medicine crafting must debit their real inputs.
- Add data-driven maintenance/crop-handling perks earned from named milestones. Display exact active effects and prevent repeated stacking or resource creation.
- Shipments at days 180/360/540/720 and every 180 days afterward; deadline 30 days before each arrival. Freeze the chosen 12-point discretionary manifest at deadline. Use the documented default if no order exists; add an explicit modest baseline allocation and balance it against local production.
- Populate a visible unloading queue on arrival. Logistics labor transfers cargo into actual storage; overflow remains in the queue. Delivery, unloading and inventory credits have distinct exactly-once receipts.
- Display supply countdown, deadline, manifest capacity, research dependencies, forecast deficits and next-level progress. Save all production/upgrade/order/unloading state.

## Required verification

- Simulate all four delivery/deadline boundaries, missing/invalid/late manifests, duplicated commands, full storage and reload before/after unloading.
- Verify each upgrade branch changes its named process, costs its inputs, respects capacity, and cannot stack multiple modules or bypass cooldown.
- Compare efficient and resilient strategies across matched seeds; both must be viable without identical decisions.
- Verify day-720 ending once, continued day-900 supplies, earned-level persistence and new-crop gating. Add CAMPAIGN_PROGRESSION_PASS.

## Completion gate

A two-year progression arc whose shipments, research and component choices create distinct colony strategies.

Write `docs/overhaul/reviews/09_PROGRESSION_AND_CARGO_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
