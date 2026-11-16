# Package 1 review: campaign contract and saves

## Result

Implemented an opt-in v3 campaign facade on top of the existing transactional simulation, complete checkpoint serialization/validation, and native save slots. The existing prototype is still the default. Camp construction, crew needs, agriculture/medicine, repair challenges, events, progression and the new tutorial are handed to Fable in packages 2–11.

The supplied checkout was at older local HEAD `e0a4f79`, with dirty HUD/camera/tutorial files. Those remain untouched by the integration; their backup is in the original checkout at `build/overhaul-baseline.zip`. The original baseline suite passed. Local `origin/main` identifies PR #10's merge as `5d33c7b`. The delivery is isolated in `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`, branch `overhaul/living-colony-pr10`, based on that merge. Only the new campaign code/data/docs/tests and small README/runner additions were transferred. No old dirty frontend files were copied over PR #10. No network fetch or claim about a newer remote head was needed.

## Implementation

- `scripts/campaign/campaign_simulation.gd`: external v3 envelope/snapshot, explicit capabilities, existing handler/ledger reuse, guarded atomic load.
- `scripts/campaign/campaign_schema.gd`: initial campaign partition and empty-only validation until feature handlers exist. Numeric canonicalization distinguishes exact binary64 storage from integer JSON fields.
- `scripts/campaign/campaign_save.gd`: detached complete checkpoints, config/content hash verification, exact RNG strings and binary64 tags, state/entity/reference/queue/receipt validation, off-to-the-side adapter initialization and no historical callback replay.
- `scripts/campaign/campaign_save_store.gd`: fixed safe slots, bounded file size, verified temporary writes, rename replacement, prior-save backup, backup recovery and three rotating native autosave slots.
- `data/campaign/content.json`: authored starting catalog for 16 equipment/room types, five crops, specialization branches, nine cargo packs and seven event families. These are not active simulation definitions yet.
- `tests/campaign/run_foundation.gd`: 331 behavior checks, registered in the normal runner.
- `docs/overhaul/`: design, actual foundation contract, workflow and ten bounded feature prompts.

The public v3 facade translates existing commands into internal v2 journal entries. This is intentional and documented; new v3 feature commands need their own validated dispatch extension. The old command validator and fixture semantics were not changed.

## Verification

Engine: Godot 4.7.2, Compatibility project, native Windows console binary. Final validation runs from the PR #10-based overhaul worktree, including its title/frontend and frame-pacing checks.

```powershell
$godot = 'C:/Users/Symok/Downloads/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script tests/campaign/run_foundation.gd
python tests/run_headless_checks.py --godot $godot --benchmark
```

Foundation result: `CAMPAIGN_FOUNDATION_PASS checks=331`.

The foundation tests include actual native first/repeated replacement, corrupt-primary recovery, retaining a good backup when replacing a corrupt primary, refusing to overwrite a valid checkpoint with invalid live state, and all three auto slots. A decimal JSON roundtrip initially exposed one-ULP differences; binary64-tagged checkpoint encoding fixes them, and post-reload continuation compares exact saved representations after sixty more real ticks. Every active expedition phase and completed cargo-return state is roundtripped, including capacity-blocked return caches.

The final PR #10-based runner completed with `HEADLESS_PASS`, including `CAMPAIGN_FOUNDATION_PASS checks=331`, frontend/title and colony boot, tutorial, bridge/frame-budget checks and the A1 benchmark. The full output is retained in [01_FOUNDATION_VALIDATION.txt](01_FOUNDATION_VALIDATION.txt), copied from `build/overhaul-validation.log`. This is automated native/headless evidence; it does not claim human or browser campaign validation.

## Limits

- This delivery completes the shared foundation and Fable handoff preparation, not the playable overhaul.
- Save UI triggers, day/incident autosave timing and preparing worlds for cross-map loads belong to scene integration. The foundation rejects mismatched worlds and crew capabilities.
- The future campaign partitions deliberately reject unimplemented populated records; their packages must add real schema validation, not remove checks.
- Checkpoints require the same engine version and matching definition/content hashes. V2 checkpoints and changed content have no automatic migration.
- Native file behavior is tested. Browser host persistence and export-template availability are not verified.
- No rendered campaign UI or manual campaign playtest was performed; the new facade has no replacement default scene yet.
- Nothing was committed, pushed, merged or deployed.

## Next handoff

`docs/overhaul/handoffs/02_TIME_AND_SCHEDULER.md` is ready for Fable 5.2. Implement and review that package before starting camp construction.
