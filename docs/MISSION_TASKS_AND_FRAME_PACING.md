# Discoverable missions and responsive simulation

The always-visible **Tasks** button beside CREW opens mission objectives, their
current checklist and colony jobs. It works with guidance hidden or disabled.
Mission 2 unlocks after the reference colony's starting repairs are complete.
Tasks explains that requirement, marks the ready state, and offers **Start mission
2**. Starting pauses the clock so the objective can be read. The guided debrief
still offers its original independent-shift handoff.

The frame-rate report reproduced two main-thread costs:

- Production HUD snapshot refresh repeated a large placement flood fill despite
  unchanged geometry: approximately 48 ms per refresh in the reference colony.
- Fastest mode requested enough simulation ticks that a stalled frame could run
  120 ticks before drawing again. Measured updates averaged about 101 ms with a
  nominal 60 Hz input, or 342 ms with a simulated 7 Hz catch-up input.

The HUD now reuses placement geometry until relevant input changes, while checking
resource affordability fresh. The interactive backend yields between committed
ticks after an 8 ms work budget, retaining all pending simulation time. Headless
`advance()` remains unchanged. Normal pacing remains one game minute per real
second; faster presets are tuned to avoid the previous excessive per-frame load.

On this machine, a bounded 3840x2130 Windows rendered probe (two 180-frame bands)
averaged 16.61 and 16.51 ms per frame, approximately 60 FPS. HUD refresh averaged
1.61 ms. These are local, short-probe results, not a universal FPS guarantee or a
long-duration gameplay run. The second band injects stalled-frame time to exercise
backlog handling. The profiler is `tests/world/profile_game_pacing.gd`; use
`-- --sustained` for the 180-frame bands (otherwise 12 samples).

Validation includes the full headless suite, exact equivalence after draining a
budgeted simulation's retained time, pause behavior, placement-cache invalidation,
fresh affordability checks, and mission availability with guidance off. Rendered
tutorial checks run at 1280x720 and 1600x900, including Tasks and Mission 2 ready
screens. See `docs/evidence/tasks-performance/validation.txt` for output.
