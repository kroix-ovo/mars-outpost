# PR #6 against A3 — compatibility test

**Historical baseline:** the failures below describe the initial review candidate. They are fixed in the local `codex/cohesive-game` integration. See [current integration and verification](COHESIVE_GAME_INTEGRATION.md); the compatibility probe now exercises real gameplay and must pass.

Tested 2026-11-15 using Godot 4.7.2 standard. A3 base: `152546f5ec73601c8858a1bed6c30c585af359a2`; PR #6: `f00efcf861dad70990022ed3afca35debc690d2b`. Combined in the isolated `codex/test-crew-against-a3` worktree. The merge has no conflicts. The normal A3 checkout, the collaborator's branch and main were not changed or pushed.

## Result

The component PR coexists with A3 and its standalone training scenario passes. It is **not yet a fully integrated crew/EVA game**, and two targeted compatibility checks fail. Keep the PR in draft for integrated-game readiness until the issues below and the planned runtime wiring are addressed.

| Check | Result |
|---|---|
| Editor import, including the two audio assets | Exit 0, no script/parse error |
| `tests/crew_ui/run_crew_ui.gd` | 85/85 standalone checks, exit 0 |
| Standalone training scene, five headless frames | Exit 0 |
| World | 679 checks pass |
| A1 | 14295 checks pass |
| A2 electrical isolation | 41144 checks pass |
| A3 | 6718 checks pass |
| World/A3 integration | 54 checks pass |
| Bridge regressions | 17 checks pass |
| Full-runtime A1 large-journal benchmark | 36565 checks pass |
| Main-scene headless boot | Exit 0 |
| Original reference fixtures / A3 profile / authored manifest freshness | Pass; reference JSON unchanged |
| New direct A3/crew probe | 24 checks: 22 pass, 2 fail; exit 1 expected on this candidate |

These are headless component/compatibility results, not exported-browser, audio-output or interactive player-session validation.

## Reproduced defects

### P1 — EVA advances along an obstructed saved path when a detour exists

PR #6 `scripts/tasks/eva_planner.gd:216–226` queries a replacement route only to test `reachable`, then advances `trip.route_progress_m` on the **old** `trip.route_waypoints_m`. Reachability through a different path does not establish that the saved next segment is still passable.

The probe uses the real Task 02 `WorldService` and a synthetic in-flight snapshot. At 3 m along the route from [2,8] toward [12,8], crew are at [5.5,0,8.5]. `validate_placement` accepts a module at [6,8] because an alternate return route remains available. With that module present, the adapter proposes [6.5,0,8.5] on the next tick: inside the new occupied cell.

Observed output:

```text
BLOCKED_ROUTE_REPRO placement_valid=true proposed_position=[6.5, 0.0, 8.5] cell=[6, 8]
```

Before advancing, either validate the saved next segment and enter the contract's stranded state when it is obstructed, or perform an explicitly validated replan that preserves partial-segment backtracking distance and route identity. Do not use successful detour lookup as permission to advance along a blocked old route. Add a regression covering a valid placement that preserves connectivity while occupying the old path; the existing blocked-airlock test only covers total unreachability.

### P1 integration blocker — forecast rates and actual suit demand disagree

PR #6 `scripts/tasks/eva_planner.gd:32–34` supports `eva_policy.phase_rates_per_s` and EVA rate modifiers. A3 `scripts/systems/crew_demand_system.gd:107–115` consumes only constant `crew_metabolism.eva_suit_rates_per_s` values. Merely passing the adapter to the facade does not synchronize these policies.

The probe gives both components a working-phase oxygen override of 0.001 kg/s while the baseline suit rate is 0.002 kg/s. The estimator uses 0.001; the real A3 demand system and ledger deduct 0.002 in the same working interval. A reserve preview can therefore understate real consumption by a factor of two with these settings.

```text
WORKLOAD_RATE_REPRO forecast_per_s=0.001 actual_A3_per_s=0.002
```

This requires an integration change in Task 01 as well as a shared rate policy, not just a cosmetic forecast change in PR #6. Use the same phase/modifier-aware calculation for forecasting and committed demand, or reject unsupported overrides/modifiers before enabling a scenario. Add a real-ledger consumption-versus-forecast regression. Default synthetic rates agree when no overrides are present; the authored A3 reference profile correctly keeps EVA disabled, so this is a blocker to enabling combined EVA rather than a claim that the current authored game launches unsafe trips.

## Known integration work, separate from PR defects

The probe manually initializes the PR adapter with real A3 snapshots and validates its exported crew partition successfully. The HUD also renders actual A3 resources/crew and resolves pause through actual A3 command-result events. The adapter correctly honors `eva_supported: false` in the researched reference profile.

However, A3 currently stores the adapter reference without calling `initialize`, `plan_tick` or `evaluate_hazards`. Its facade still rejects placement, assignment, cancellation, launch and recall with `module_unavailable`, and save/load remains unavailable. `CrewRoot` and `UIRoot` in the main scene remain empty. A manually mounted HUD can show a synthetic forecast while the real facade refuses launch; the probe confirms refusal makes no expedition. Those limitations are already acknowledged in the PR handoff and must not be confused with the standalone fixture facade's implemented training loop.

Integration still needs validated intent/progress/hazard proposals; ID substitution and transition checks; authorization of transfers; preparation of existing zero-valued suit/cargo/cache slots; actual ledger commits and balance overlay; labor/commissioning/refund ownership; site reservations; HUD/crew-view mounting and rebinding; and production save integration. The existing A3 test runner also does not automatically discover the PR's crew suite; add an explicit CI job before relying on green integrated checks.

## Reproduce

From the isolated worktree:

```powershell
& '<godot-console>' --headless --path . --editor --import --quit
& '<godot-console>' --headless --path . --script tests/crew_ui/run_crew_ui.gd
python tests/run_headless_checks.py --godot '<godot-console>' --benchmark
& '<godot-console>' --headless --path . --script tests/crew_ui/run_a3_compatibility.gd
```

The final command deliberately exits 1 until both reproduced issues are fixed. No production source was edited to make these probes pass, and no game/PR merge was published as part of this review.
