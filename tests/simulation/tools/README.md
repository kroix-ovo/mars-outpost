# Fixture generator and reference model

These tools generate every JSON file under [`../fixtures/`](../fixtures/README.md). They are test tooling only. They are not the simulation runtime, and passing them is not runtime verification.

| File | Role |
|---|---|
| `fixture_content.py` | Synthetic definitions, scenarios, and init-config list (all values synthetic) |
| `reference_model.py` | Python oracle of the contract 2.0.0 rules that the fixtures exercise; raises on anything else (for example `cancel_task`) |
| `generate_fixtures.py` | Drives the model through each fixture script and writes the outputs |
| `closed_form_checks.py` | Independent hand-derived formulas checked against the outputs; does **not** import the model |

## Commands

Run from the repository root. They need Python 3.10 or newer and use the standard library only.

Regenerate all fixture JSON (README files are never touched):

```bash
python tests/simulation/tools/generate_fixtures.py
```

Fail if the committed fixtures differ from a fresh generation (missing, extra, or changed files):

```bash
python tests/simulation/tools/generate_fixtures.py --check
```

Run only the independent closed-form checks against the committed fixtures:

```bash
python tests/simulation/tools/closed_form_checks.py
```

Both generator modes generate into a temporary directory and run the closed-form checks before anything is written or compared. Output is deterministic: the same sources produce byte-identical JSON, with LF line endings, 2-space indentation, and Python's shortest round-trip float formatting.

## Rules for changing fixtures

- **Never hand-edit generated JSON.** Change `fixture_content.py`, `reference_model.py`, or a script in `generate_fixtures.py`, then regenerate.
- **Editing any definition or scenario changes its hash**, so every manifest that lists it is regenerated automatically.
- **Add a matching closed-form check when you add a scenario whose totals can be derived by hand**, so the model cannot define correctness by itself.
- **The model also asserts save/load continuity:** an uninterrupted run and a restored run of `placement_and_save` must produce identical snapshots and saves.
- **The one engine-measured constant** is `RNG_STATE_BY_SEED` in `reference_model.py`. Godot 4.7.2 sets `RandomNumberGenerator.state` to `708718527385777908` after `seed = 42`. Re-measure it if the pinned engine changes.
