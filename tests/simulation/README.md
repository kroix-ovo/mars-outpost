# Simulation verification

## A1 foundation

Run from the repository root using the team's Godot 4.7.2 standard console executable:

```powershell
& '<godot-console>' --headless --path . --script tests/simulation/run_a1.gd
```

Replace `<godot-console>` with the Godot 4.7.2 console executable on your machine. The runner returns exit code 0 with `A1_PASS checks=...` on success and exit code 1 for failed assertions. Compiler/runtime errors must also be treated as failures; require the explicit success marker. No editor, main scene, third-party test library, or rendered world is needed. Temporary malformed-content fixtures are written under ignored `.godot/` with process-specific names and removed after the run.

The A1 runtime under `scripts/simulation/` provides:

- Manifest/hash validation, atomic initialization, and detached initial snapshots matching all eight fixture configurations.
- Schema validation and numeric normalization for all seven command types.
- FIFO execution of `set_time_scale` and `set_building_enabled`, acceptance versus resolution, deduplication, and immutable cached results.
- A one-second fixed-step clock, 0/1/5/20 time scales, fractional accumulation, pause/resume, and retained backlog with a 120-tick call budget.
- Stable initial entity IDs, the seeded Godot RNG, command-result events, one final state notification per changing update call, and guards against callback-driven recursive updates.
- Validation of malformed initial content, invalid commands/deltas, failed resolutions, snapshot mutation, callback submission, and equivalent clock outcomes across frame schedules.
- A retained-journal regression check with 2,000 commands, including old result retries, failed-candidate isolation, a structural check that gameplay clones exclude journal metadata, and a deliberately loose timing guard against journal-sized tick copying.

To print a fuller journal-scaling benchmark (0, 250, 1,000, 2,000, and 20,000 retained commands), run:

```powershell
& '<godot-console>' --headless --path . --script tests/simulation/run_a1.gd -- --benchmark
```

`A1_BENCH` reports median milliseconds per A1 clock tick and total submission/resolution time for each batch. Timings depend on the machine and cover the foundation only, not future resource systems. The default runner checks 0/250/2,000 retained commands and rejects a tick median above the larger of 2 ms or eight times its empty-journal baseline. It also rejects resolution cost per command above the larger of 2 ms or four times the 250-command baseline. These deliberately loose guards catch large scaling regressions; the structural and semantic checks remain necessary even when timing passes.

The facade retains command history/queue metadata separately from transactional gameplay state. Ticks never copy or change that history. Command resolution clones gameplay only, then updates the one journal entry after committing or discarding the candidate. Consequently rollback never needs to copy or undo the whole journal. Future persistence must serialize the facade metadata alongside gameplay; the save envelope remains unchanged.

**A1 ticks advance the structural clock only.** Resource production/consumption, power dispatch, crew work, hazards and persistence have not been integrated. Running a 600-tick reference scenario against A1 will therefore not produce its expected gameplay balances. The runtime is a partial implementation of contract 2.0.0, not a playable outpost or complete conformance implementation.

`place_building`, `assign_task`, `cancel_task`, `start_eva`, and `recall_eva` reject at submission with `module_unavailable`; their IDs are not claimed. Save/load return the same explicit unavailable status. Supplied world/crew service references are reserved for subsequent integration and are not called by A1. No unavailable command is acknowledged as successful work.

Initialization currently supports the explicitly marked synthetic fixture content formats only. Production map/crew formats and adopted scientific data remain later integration work. It rejects production data explicitly rather than treating synthetic assumptions as real science.

## Reference tooling

```powershell
python tests/simulation/tools/generate_fixtures.py --check
python tests/simulation/tools/closed_form_checks.py
```

These verify reproducible expectations and independent arithmetic. See [tools/README.md](tools/README.md) and [fixtures/README.md](fixtures/README.md). Only the eight tick-zero snapshots are currently compared with actual Godot simulation output. Later work packages must execute the full reference scripts and add independent invariants; the Python model must not become the runtime implementation.
