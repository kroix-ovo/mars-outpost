# Campaign foundation checks

Run `run_foundation.gd` using Godot's headless `--script` option. It is also registered in `tests/run_headless_checks.py`.

```powershell
& 'C:/Users/Symok/Downloads/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/campaign/run_foundation.gd
```

Expected marker: `CAMPAIGN_FOUNDATION_PASS`. The initial implementation has 331 checks.

The suite exercises the real v3 facade and existing ledger, with and without the real crew adapter. It checks detached JSON-safe checkpoints, exact binary64/RNG continuation, partial accumulators, pending/resolved command journals, duplicate/conflicting commands, malformed loads and no partial replacement, cross-campaign loads, callback reentrancy, construction spending/refund receipts, outbound/working/returning expeditions, full-storage cargo return caches, and native save/backup/rotation behavior.

Temporary filesystem tests use a unique `user://foundation_test_<timestamp>` directory and remove only files created there. The suite does not overwrite actual player save slots.

These are foundation tests. They do not claim the future campaign mechanics, browser persistence, rendered campaign UI or human playtesting are complete. See `docs/overhaul/README.md` for the feature sequence.
