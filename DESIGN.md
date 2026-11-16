# Colony HUD design

Mode: Operate. Players manage a camp and need to find the next useful action without obscuring the world. Interface references are The Sims and Cities: Skylines, as requested by the user.

- Background panels: dark slate `#182a36`; controls `#263e4d`; primary action/selection mint `#64d8ba`.
- Main text `#e8f1f5`, secondary `#a8becb`; warnings amber `#f3bb69`. Mint means action/selection, not hazard severity.
- Workhorse sans UI typography. Names and roles are separate labels, never concatenated strings.
- Four persistent resource groups across the top; full accounting on demand. Alert badge has reserved width and no ellipsis for the empty state.
- Bottom dock: Build, Crew, Jobs, Explore, Colony, Goals. One context panel at a time. Clicking an existing building opens inspection; Build opens construction.
- Compact left next-step card with a direct action through real simulation commands. Raw coordinates and job priority are advanced controls rather than default clutter.
- Playback is drawn geometry: pause bars, one triangle, two triangles, three triangles. No arrow characters or emoji.
- Crew portraits render the actual existing astronaut models once into 96px textures, displayed at 48px. No per-frame portrait rendering.
- Subtle storm haze stays under the UI and reads committed simulation state. It never creates random outcomes or changes resources.

The user supplied [Impeccable](https://github.com/pbakaus/impeccable). Its [Operate guidance](https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/operate.md) and [craft floor](https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/craft-floor.md) informed hierarchy, states, contrast, contextual disclosure and rendered verification. Its launcher was not installed/run; the Godot implementation is authored directly here.
