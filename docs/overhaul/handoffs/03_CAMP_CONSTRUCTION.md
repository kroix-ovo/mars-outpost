# Package 3: Separate ship, connected camp and furnished interiors

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 2 reviewed.

## Implementation

- Create a campaign scene and map/profile without replacing the existing default launch yet. Add a development launch command and test harness so this is production-integrated rather than an orphan scene.
- Extend bridge snapshot validation through explicit v2/v3 dispatch; it currently expects v2 records. Keep v2 rejection/validation intact instead of simply accepting any dictionary from the v3 facade.
- Implement a validated campaign content loader for data/campaign/content.json. Extend its gameplay metadata with units and full definition fields instead of treating the catalog as legacy manifest data. Hash the actual files used in saves.
- Build a distinct landing ship, finite starting cache, 6x6 metre habitat core/wings, doorway sockets and room furniture on the 64x64 metre campaign map. Interior furnishing and outside equipment use distinct occupancy layers. Keep door-to-door routes clear.
- Add placement previews and transactional place_wing/place_furnishing commands, material spending, construction jobs, cancellation/refunds, utility connections, sealing and commissioning.
- Extend headless world queries for interior/exterior routes, airlocks, zone topology and route revisions. Do not use scene physics as authoritative navigation.
- Add connected atmosphere zones with explicit volume, gas inventories and safety state. Connect/split/isolate transfers must conserve gas exactly; reject splitting if the operation cannot be represented safely.
- Inside essentials: bunks, cafeteria, farm racks, med bay, workshop, life support/recycler. Outside: solar, generator, batteries, storage, utility routes. Unsupported production remains disabled until its package lands.
- Show a cutaway interior and legible construction/utility/air safety state. Derive meshes and status colors from committed records.
- Allocate enough starting resources for the tutorial plus a modest repair contingency; show the budget calculation. Ship emergency shelter has finite capacity/supplies and cannot be an indefinite free bypass.

## Required verification

- Build a core and two wings through real commands, furnish, connect, seal and commission them. Invalid adjacency, blocked doors, exterior furniture, interior solar and overlapping occupancy fail without spending.
- Test cancellation, competing placement commands, blocked travel after topology changes, duplicate commands, queued reload and save after a zone split.
- Assert gas conservation through connecting, isolating and reconnecting wings. Unsealed rooms never count as safe shelter or productive farms.
- Capture the ship separated from camp, a cutaway furnished wing, placement previews and isolation state at all three target resolutions. Add CAMPAIGN_CAMP_PASS.

## Completion gate

A buildable camp with honest safety and utility state, accessible through its campaign scene while the legacy game remains available.

Write `docs/overhaul/reviews/03_CAMP_CONSTRUCTION_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
