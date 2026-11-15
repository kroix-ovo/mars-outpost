# Title and character polish

The title now uses bundled Russo One display lettering. The Space Apps badge centers
the original mark and wordmark by excluding uneven blue padding with an AtlasTexture;
the supplied PNG is preserved. Font license and badge presentation are documented in
`ATTRIBUTION.md`.

The designer calls the shared colour control **Eyebrows and facial hair colour**.
The existing shared tint still applies to hair and scarves too. **Sunglasses** adds
opaque blue lenses and dark frames, and survives profile saving and loading.

Training astronauts now use Inez Solis, Amara Okafor, Tariq Nasser, Nia Park, Jo Silva
and Luca Ivanov, matching the landing lineup and its designed appearances. The same
presentation mapping supplies roster entries, tutorial instructions and action buttons,
EVA suit summaries and world nameplates. Simulation fixture files and identifiers are
preserved. Custom names and the reference colony's authored names are preserved.

## Validation

- Godot 4.7.2, full headless runner: passed all suites and both scene boot checks;
  frontend 229 checks, crew UI 85, tutorial 92.
- Rendered frontend: 178 checks at each of 1280×720 and 1600×900, all passing.
- Rendered tutorial: 115 checks at each size, all passing.
- Reviewed the rendered title, sunglasses preview and named tutorial step at 1280×720.
- No manual gameplay session or listening test was performed.

Run the headless suite with `python tests/run_headless_checks.py --godot <Godot-console>`.
Run `tests/visual/run_frontend_layout.gd` and `tests/visual/run_tutorial_layout.gd` with
`--audio-driver Dummy --resolution 1280x720` or `--resolution 1600x900`.
The new checks cover title width, label bounds, sunglasses preview and profile persistence,
and continuity between landing characters and the training roster.

Evidence at each size:

- `docs/evidence/frontend/<size>/01_title.png`
- `docs/evidence/frontend/<size>/05_customizer_custom.png`
- `docs/evidence/tutorial/<size>/04_add_second_astronaut.png`

Full headless output and rendered results: `docs/evidence/character_polish/validation.txt`.

This change is based on the reviewed title/tutorial integration at `685dcc0`, on
`codex/title-review`. The PR contains only the requested typography, badge, customizer
and crew identity changes relative to that branch.
