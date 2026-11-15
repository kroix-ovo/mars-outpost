# Attribution and science sources

Record each asset's provenance before adding it to the repository. Scientific parameter references belong in `SCIENCE.md`.

## Current state

- **Two external files are imported, both for the title screen** (records below): the title music and the NASA Space Apps Challenge logo. Every mesh, material and colour in the game, including the astronauts, Mars globe, transit ship and intro terrain, is generated procedurally by scripts under `scripts/world/`, `scripts/crew/` and `scripts/frontend/` or hand-authored as Godot primitives in `scenes/world/landing_ship.tscn`.
- `data/maps/landing_plain.json` is a **procedural blockout terrain** authored for this project. Its heights, ridge and crater are game abstractions. It is **not** derived from NASA Mars Trek, MOLA or any other NASA dataset, and no such derivation may be claimed until an entry below records it.
- The only NASA-related mark is the NASA Space Apps Challenge logo in the title screen's corner, which identifies this as a Space Apps Challenge project. No NASA agency insignia, flags or mission identifiers are used, and the logo does not imply NASA endorsement.

- Authored module scenes under `scenes/buildings/` and the markers in `scripts/world/site_view.gd` are built from Godot primitive meshes only.

## Imported assets

```text
Asset name: "Space" (music track, Pixabay audio file ID 589110)
Repository path: assets/audio/music/mondamusic-space-589110.mp3
Creator / mission / organization: mondamusic (https://pixabay.com/users/mondamusic-54713575/)
Source URL: https://pixabay.com/music/ambient-space-589110/
License / usage terms: Pixabay Content License (https://pixabay.com/service/terms/). Download
  certificate kept beside the file: assets/audio/music/ambient-space-589110-license.txt
Required credit line: None required; credited on the title screen as
  "Music: "Space" by mondamusic (Pixabay)".
Modifications: None. Looped in code (AudioStreamMP3.loop) on the title screen.
Date accessed: 2026-11-15
```

```text
Asset name: NASA Space Apps Challenge logo
Repository path: assets/branding/space_apps_challenge.png
Creator / mission / organization: NASA Space Apps Challenge
Source URL: Supplied by the project team (430x226 PNG, white logo on blue)
License / usage terms: Used only to identify the project as a NASA Space Apps Challenge entry,
  per the challenge's brand use for participants. Confirm current Space Apps brand guidance
  before any public release outside the challenge.
Required credit line: None; shown in the title screen's top-right corner.
Modifications: Presentation uses an AtlasTexture region to exclude excess right-hand blue
  padding and center the original mark and wordmark. The source PNG is unchanged.
Date accessed: 2026-11-15
```

## Russo One display font

- Creator: Jovanny Lemonad; copyright 2011–2012, reserved font name Russo.
- Source: https://github.com/google/fonts/tree/main/ofl/russoone
- Local files: `assets/fonts/russo_one/RussoOne-Regular.ttf` and `OFL.txt`.
- License: SIL Open Font License 1.1; included alongside the unmodified font.
- Used for the title's display lettering. Downloaded 2026-11-15.

## Planned NASA-derived references (not yet imported)
When these are added, download them during development, ship them locally under `assets/nasa/`, and complete a record below for each file. The game must never fetch NASA data at runtime.

- Mars Trek WMTS tiles / MOLA topography for a terrain reference and heightmap. Pipeline ready: `tests/world/tools/heightmap_to_map.gd` turns a downloaded grayscale tile into a map JSON; the asset record below must be filled in first.
- SWIM subsurface ice maps for the landing-site selection screen.
- NASA Image and Video Library stills for loading screens and debrief cards (credit each image, e.g. "NASA/JPL-Caltech").
- Perseverance surface audio for ambience.

## Asset record template

```text
Asset name:
Repository path:
Creator / mission / organization:
Source URL:
License / usage terms:
Required credit line:
Modifications:
Date accessed:
```

Check the terms for each individual asset, including third-party material hosted by NASA. This independent project does not imply NASA endorsement.
