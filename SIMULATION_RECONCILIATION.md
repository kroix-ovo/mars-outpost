# Simulation design reconciliation

Decision date: 2026-11-14. Reviewed input: revision 3 of `SIMULATION_DESIGN_PROPOSAL.md` and the synthetic fixtures under `tests/simulation/fixtures/`.

**Implementation authority: [SHARED_SIMULATION_SPEC.md](SHARED_SIMULATION_SPEC.md), contract 2.0.0.** The proposal remains design history. The fixtures have now been regenerated with repository-owned tooling against 2.0.0. No simulation runtime has been implemented or tested yet.

## Accepted decisions

| Proposal item | Resolution |
|---|---|
| D1 — effect retention | Keep irreversible completion markers. Protect recurring effects within their tick transaction; do not retain a journal entry each simulated second. Persisted ID retries must also match the original normalized effect. |
| D2 — private state | Accept full-record replacements for `completion_markers`/`private_counters`, with explicit permitted deletion and whole-candidate validation. The ledger alone writes return caches. |
| D3 — save metadata | Preserve last-tick power, alerts/first occurrence, and resource diagnostics. Validate battery aggregate equality. Do not add duplicate non-base account storage. |
| D4 — construction templates | Task 03 supplies templates through `apply_command(place_building, snapshot)`. Task 01 validates costs/work/IDs and commits. |
| D5 — labor | Task 01 applies construction/repair labor once. Farming labor feeds the next crop phase rather than re-running a completed phase. |
| D6 — atomicity | Start with working-copy command/tick transactions. Benchmark with realistically sized state, including command/effect journals, before making a performance claim or switching to undo logs. Two milliseconds is a profiling signal, not a promised requirement. |
| D7 — configuration | Use synthetic values until science parameters are verified or explicitly documented game abstractions. Task 01 may own `data/scenarios/` and `data/science/`; fixture-only equivalents remain under tests. Do not impose a fixed maximum of 100 buildings based on a benchmark fixture. |
| D8 — vocabulary | Adopt blocking/alert codes enumerated in the shared spec. UI can now depend on them. |
| D9–D12 | Consumer-only requested/served power; validated whole JSON numeric integers; signed-int64 nonnegative seed range; no revision increase for failed/no-op commands. |
| D13 — CO2 | Accept registry `capacity_policy` and snapshot `capacity: null` for accumulators. Never discard cabin CO2 because an artificial storage cap was reached. Atmosphere hazard fidelity remains future science/model work. |
| D14/D16 | Flush events at boundaries/ticks and emit one final state snapshot. Cache snapshots only while all snapshot-visible state is unchanged; invalidate on successful load even if its revision equals the previous campaign's revision. |
| D17 — EVA | Accept separately validated expedition travel/work proposals, a mirrored EVA task work counter, and transition-authorized resource transfers. Add valid stranded-to-returning recall recovery. Unmet needs do not grant productive work; movement still obeys the configured health/exhaustion policy. |
| D18 — release | Release non-EVA terminal-task crew at next intent. EVA return immediately changes crew location to base so the next metabolic tick cannot charge an empty suit. |
| D19 — event order | Amend: preserve tick phase order before sorting entity/type/effect identity. Boundary events follow command receive order, with each command result first. Include array-valued crew references. IDs are allocated after sorting. |
| D20/D21 | Zero tiny displayed rates only; never round stockpiles. Before first tick diagnostics start at zero, without inventing a simulated interval. |
| D22 | Persist normalized journal envelopes and reconstruct their comparison representation on load. |
| D23 | Resolve EVA checks in order: site, crew, routes, reserve policy, suit capacity, base stock, after envelope/type validation. Documented first-failure codes are public behavior, not just private implementation details. |
| D24 | A recalled team returning safely has a completed expedition. Its task is cancelled if no salvage was collected, otherwise completed. |
| D26 | Accept zero EVA food/water draw only as a synthetic-fixture simplification. It is not adopted real physiology. |

## Remaining questions resolved

**Wastewater (Q-W):** keep finite storage, with explicitly recorded unrecoverable overflow/spillage and a `storage_full` alert when obligatory metabolic waste cannot fit. A full waste tank cannot prevent oxygen consumption or erase a recorded loss. Only retained water can later be recycled. Other production processes remain capacity-limited. This rule must be exercised by a new fixture.

**Nullable capacity:** use `capacity: null` for accumulators and a declared registry policy, rather than a fake numeric capacity. UI must render that as accumulation, not unlimited usable storage.

**Reference generator:** supplied and reviewed under `tests/simulation/tools/`, including reference-model source, deterministic regeneration, a stale-file `--check` mode, and independent closed-form checks. The model intentionally covers a subset of the contract, not all input validation, adapter proposal validation, hazards, or rollback behavior. Runtime assertions must independently cover those boundaries.

## Version and fixture follow-up

1. Keep historical proposal defaults identified as proposals wherever they differ from the reconciled spec.
2. Regenerate command envelopes and expected snapshots for contract `2.0.0`, snapshot schema 2, save schema 2. The stored crew adapter schema remains 1. Required proposal replacements and `export_state(crew_tasks_state)` must follow the new spec.
3. Regenerate event IDs/order if affected, capacity/full-output cases, record references and manifest hashes. Do not hand-edit the expected arithmetic or blindly relabel versions.
4. Add wastewater overflow, full-store EVA return cache, stranded recall recovery, and load-into-an-instance-with-equal-revision/different-campaign checks.
5. Keep map/crew/task fixture formats labeled test stubs until Tasks 02/03 adopt production formats. Stub placement checks are not evidence that the full world placement contract is implemented.
6. Then implement A1 using the installed Godot console binary. Early milestones must have real engine-run assertions; checking reference JSON is not runtime verification.

## Independent checks performed during this review

The following first-pass checks preceded generator delivery:

- Parsed all 55 fixture JSON files.
- Verified all 72 manifest path/hash entries across initialization configs and the save.
- Compared 5/6/9-crew tick-600 oxygen, food, hydrogen, battery and applicable water/CO2 totals with independent formulas.
- Compared charged, depleted, and restored battery snapshots against independent expected energy values.

Those artifact checks passed. The Python generator's claimed save/load continuity has not been independently reproduced because its source is absent. No fixture script has run against a Godot simulation runtime. Previously reported Godot parser/hash/RNG checks are useful engine probes, not proof of gameplay correctness.

## Generator delivery review

The generator source is now present. The first-pass source-availability limitation above is resolved. Local checks performed after delivery:

- `python tests/simulation/tools/generate_fixtures.py --check` passed for all 85 generated JSON files; this also executes the reference-model save/load continuity assertion.
- `python tests/simulation/tools/closed_form_checks.py` passed independently of model imports.
- Isolated mutation checks proved that changed, extra, and missing JSON each cause `--check` to return a failure, without modifying the working fixtures.
- A fresh scratch Godot 4.7.2 headless probe parsed all 85 files, checked JSON numeric decoding, reproduced all 144 valid-save/init manifest hashes, and verified seed 42's RNG state `708718527385777908`.

Accepted clarifications: an initial blocked recall transitions to stranded and resolves successfully; a still-blocked stranded retry fails without mutation. Injected blocked cells remain a harness-only failure hook. The shared spec also makes canonical suit/base energy identity, capacity-blocked return-cache destinations, and explicit suit-return loss destinations clear for future ledger validation.

The tooling/reference outputs are ready to commit as a reproducible test baseline. No gameplay simulation has executed these scripts yet. The model does not exercise real `CrewTickProposal` validation merely because the stub policy README describes that field; that remains implementation work.
