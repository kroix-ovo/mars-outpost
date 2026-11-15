# Local cohesive game integration

Integrates PR #6 (`f00efcf`) with the A3 simulation (`152546f`) and the existing world integration on `codex/cohesive-game`. The main scene uses the production simulation, crew adapter and HUD together. The disposable crew test facade is not used by the game.

## Playable paths

- Building placement validates geometry, technology, supported processes and inventory; it allocates stable IDs, prepays materials and creates a construction job.
- Assignment routes crew to module entrances. The core applies bounded labor once, commissions finished modules and updates storage/battery capacity. Unfinished batteries start empty and supply no capacity or power.
- Cancellation returns the prepaid construction materials once and removes the unfinished module. A refund that cannot fit is rejected atomically.
- EVA checks routes, crew availability, suit capacity and forecast reserves. The ledger loads suits, consumes phase-specific supplies, transfers salvage from the reserved site, and returns unused supplies and cargo. Overflow cargo stays in a return cache and moves into storage when space opens. Recall returns without granting unfinished salvage rewards.
- The authored map loads PR #6's named roster and repair templates. Initial damaged modules get repair jobs; finishing one restores condition and releases its crew.
- Mission control binds to the active simulation and rebinds on world restart. The world displays crew and reserves screen space for the HUD. Save controls and unsupported agriculture placement are disabled.

## Fixed review failures

The route planner now validates every remaining saved segment. A newly obstructed path strands the trip even when another route exists; an explicit recall may request a fresh return route. Crew no longer continue through the obstruction.

The launch estimator and the core metabolism phase share `eva_rates.gd`, including workload-phase overrides and event intervals. EVA modifiers do not accidentally multiply electrical generation. Unsupported/invalid modifiers still fail the simulation transaction.

`crew_runtime.gd` applies detached proposals inside the same working copy as electrical dispatch and life support. It validates records, ownership, task fields, transitions, labor limits and transfer kinds. Core-owned balances cannot be replaced by an adapter proposal. Receipts and events become visible only after commit. A failure in crew progress rolls back earlier power and metabolism changes too.

## Explicit limits and assumptions

F2 training retains the original synthetic reference fixtures. F3 retains the researched A3 physiology and equipment assumptions; EVA remains disabled there because suit budgets have not been established. No new physiological, radiation-injury or crop-yield values were introduced.

Authored repairs use a **gameplay assumption** in `data/crew/task_templates.json`: restoring a fully damaged module requires 60 work seconds, scaled by missing condition and the configured crew productivity. This is an abstract labor budget, not a measured equipment repair time. No repair material cost or crop reward is invented.

Campaign persistence, agriculture and environmental/medical outcomes are still pending. F2/F3 start fresh colonies. Exports and hosted-browser behavior have not been re-certified by this local integration.

## Verification

Run `python tests/run_headless_checks.py --godot <Godot-console-path> --benchmark`. It includes the original world/A1/A2/A3/bridge suites, the 85-check standalone crew suite, production crew integration, retained-journal benchmarks and main-scene boot.

The production crew suite covers initialization, fixed intent/progress calls, HUD commands, reference EVA refusal, the two review regressions, salvage-to-construction, ledger costs/refunds, rejection atomicity, commissioning capacity, crew release, full EVA return, repeated recall, return caches, reference repairs and whole-tick rollback/retry. It passes 80 checks locally.

Interactive Windows verification also launched and completed a trip from the main scene's EVA tab through the real facade. The HUD showed completed status, returned crew, and empty suit balances. This does not certify physical audio playback.
