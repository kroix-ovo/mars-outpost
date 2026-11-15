# Title screen, astronaut designer and landing intro: review handoff

Branch `codex/title-intro`, based on `e0a4f79` (the tutorial handoff on `codex/tutorial-mission`). Local commit only: nothing pushed, merged or exported.

## What the player sees

1. **Title screen** (`scenes/frontend/front_end.tscn`, now the project's main scene):
   - the transit ship coasts toward a slowly turning Mars over a twinkling starfield;
   - the title reads **MARS OUTPOST / SURVIVAL**, with the subtitle *A Junior Astronaut Mission Trainer*;
   - a short story line says the lander is on final approach, and a status strip counts down to touchdown;
   - **New Game** is the one filled amber button, above **Load Game**, **Settings** and **Quit**;
   - the NASA Space Apps Challenge logo sits in the top-right corner;
   - the Pixabay track "Space" by mondamusic loops endlessly (`AudioStreamMP3.loop`) and fades out over 3 s as the colony loads. It is credited in the bottom-right corner.
2. **Design your astronaut.** A live 3D preview: drag to turn, plus Turn and Wave buttons. The options, in two columns:
   - name;
   - 10 skin tones;
   - 12 hair styles: short crop, buzz, bald, short curls, afro, top bun, ponytail, long, bob, braids, spiky, headscarf;
   - 12 hair or scarf colours;
   - 6 eye colours;
   - facial hair (none, mustache, goatee, full beard);
   - glasses (none, round, square);
   - build (slim, regular, broad);
   - height (short, average, tall);
   - 6 suit colours and 8 trim colours.

   **Surprise me** randomizes everything except the name. The look is saved to `user://astronaut_profile.json`.
3. **Meet your crew.** The commander stands in the centre, waving, between the six named crew who land with them. Each has a name and role tag.
4. **Landing intro**, about 30 s, skippable at any time (button or Esc):
   - the lander descends with a burning engine and kicks up dust;
   - after touchdown the hatch lights up;
   - the commander, then the six crew, walk down the steps, line up, wave and cheer.

   Captions:
   - arrival after about seven months in space;
   - final descent;
   - touchdown;
   - "Commander *name* steps onto Mars, followed by a crew of six";
   - "the first human outpost on Mars";
   - air, water and power must be made here, and help from Earth is months away;
   - a training shift comes first.

   It ends on **Begin training mission**.
5. **Colony.** The tutorial welcome now reads "Welcome, Commander *name*". The commander's astronaut stands beside the habitat with a "Commander (you)" tag. They are presentation only, not a simulated crew member, and cannot be selected.

## Crew designs

The nine roster crew (`data/crew/outpost_roster.json`) each have a designed look (`scripts/crew/crew_looks.gd`). Together they span nine skin tones and nine hair styles, and each design's role matches the crew member's `primary_skill`:

| Crew member | Role | Look |
| --- | --- | --- |
| Inez Solis | Engineer | Ponytail |
| Amara Okafor | Botanist | Afro, tall |
| Tariq Nasser | Engineer | Full beard, broad |
| Nia Park | Geologist | Bob, square glasses, orange suit |
| Jo Silva | Medic | Teal curls, round glasses |
| Luca Ivanov | Pilot | Blond buzz cut, mustache, sky-blue suit |
| Leila Mensah | Botanist | Headscarf, lilac suit |
| Ren Ito | Geologist | Spiky hair, round glasses, graphite suit |
| Maya Chen | Engineer | Top bun |

The colony view now uses the same astronaut for every crew member: `crew_avatar.gd` builds `astronaut_figure.gd`, which plays a walking animation while moving. Selection ring, nameplate and picking are unchanged. The training colony's "Fixture Crew A–I" get nine distinct fallback looks, and keep their fixture names.

## Load Game and Settings

- **Load Game** never pretends to restore what the simulation cannot:
  - the simulation reports `persistence: false`, so there are no colony saves yet, and the panel says so;
  - it offers the two scenarios directly: the training shift with the tutorial, or the reference colony in free play;
  - if `user://outpost_quick_save.json` ever exists, a "Continue your last saved colony" button appears and goes through the HUD's existing Load path (`load_saved_game()`). It will work once `export_save` and `import_save` are implemented.
- **Settings:** music volume (live), full screen, and whether New Game plays the intro. These are stored in `user://settings.cfg`.

## Files

**New:**
- `scripts/crew/astronaut_look.gd`: options, sanitizing, random looks.
- `scripts/crew/astronaut_figure.gd`: the cartoon astronaut and its poses (idle, walk, wave, cheer).
- `scripts/crew/crew_looks.gd`
- `scripts/frontend/`:
  - `front_end.gd`: flow and music;
  - `title_stage.gd`
  - `landing_intro.gd`
  - `astronaut_customizer.gd`
  - `space_art.gd`: starfield, Mars, transit ship and ground shaders;
  - `frontend_theme.gd`
  - `game_session.gd`: hand-over state and user files.
- `scenes/frontend/front_end.tscn`
- `assets/audio/music/` (track plus the Pixabay certificate) and `assets/branding/space_apps_challenge.png`.

**Changed:**
- `project.godot`: main scene changed to `front_end.tscn`, and the application name to "Mars Outpost Survival". User data now lives under that name; nothing was saved under the old one.
- `scripts/crew/crew_avatar.gd` and `scenes/crew/crew_avatar.tscn`: the old capsule is replaced by the shared figure.
- `scripts/world/main_world.gd`: `_apply_front_end_session()`. It runs only when the colony was reached from the title, so tests that open `main.tscn` directly behave exactly as before.
- `scripts/ui/outpost_hud.gd`: `set_commander()` and `load_saved_game()`, plus a `commander` field in the tutorial context.
- `scripts/ui/tutorial_mission.gd`: the welcome title uses the commander's name when there is one.
- `ATTRIBUTION.md`, `README.md`, `tests/visual/README.md`, `tests/run_headless_checks.py`.

No simulation, ledger, science data, fixtures or shared spec were touched.

## Verification

See the verification section appended below for the exact results. Evidence PNGs:
- `docs/evidence/frontend/1280x720/` and `docs/evidence/frontend/1600x900/`;
- `docs/evidence/frontend/crew_lineup.png` and `docs/evidence/frontend/customization_range.png`.

Not verified: human playtesting, how the music actually sounds through speakers (runs used the Dummy audio driver), and exported builds.

## Notes for review

- The music does not play in headless runs. The dummy mixer never retires a playback that is still open at exit, and the engine then reports a leaked resource. The HUD already skips its sounds headless for the same reason. Quit stops the track a frame before exiting.
- The training colony still shows "Fixture Crew A–F" names after the player has met the named crew. Renaming them means changing checksummed test fixtures, so it is left as a follow-up.

## Verification results (Godot 4.7.2 console, Windows)

- `python tests/run_headless_checks.py --godot <console> --benchmark`: `HEADLESS_PASS`. The suite now includes `FRONTEND_PASS checks=217` and boots both the title scene and the colony scene. All other markers are unchanged:

  | Check | Result |
  | --- | --- |
  | World | 679 |
  | A1 | 14,298 |
  | A2 | 41,144 |
  | A3 | 6,718 |
  | Integration | 54 |
  | Bridge | 17 |
  | Crew UI | 85/85 |
  | A3 crew | pass |
  | Tutorial | pass |
  | A1 benchmark | 36,570 |

- Rendered at 1280x720 and at 1600x900:
  - `run_frontend_layout.gd`: `FRONTEND_LAYOUT_PASS`, 170 checks at each size;
  - `run_tutorial_layout.gd`: `TUTORIAL_LAYOUT_PASS`, 115 checks at each size;
  - `run_hud_input_probe.gd`: `HUD_INPUT_PASS`, 18 checks at each size.
- `run_crew_lineup.gd`: `CREW_LINEUP_PASS`.
- `git diff --check`: clean.
- The tutorial evidence PNGs (`docs/evidence/tutorial/`) were regenerated: they now show the new crew astronauts in the colony.
