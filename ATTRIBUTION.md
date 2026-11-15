# Attribution and science sources

Record each asset's provenance before adding it to the repository. Scientific parameter references belong in `SCIENCE.md`.

## Current state

- **No external assets have been imported yet.** Every mesh, material and colour in the world scene is generated procedurally by scripts under `scripts/world/` or hand-authored as Godot primitives in `scenes/world/landing_ship.tscn`.
- `data/maps/landing_plain.json` is a **procedural blockout terrain** authored for this project. Its heights, ridge and crater are game abstractions. It is **not** derived from NASA Mars Trek, MOLA or any other NASA dataset, and no such derivation may be claimed until an entry below records it.
- No NASA logos, flags, mission identifiers or insignia are used anywhere in the project.

## Planned NASA-derived references (not yet imported)

When these are added, download them during development, ship them locally under `assets/nasa/`, and complete a record below for each file. The game must never fetch NASA data at runtime.

- Mars Trek WMTS tiles / MOLA topography for a terrain reference and heightmap.
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
