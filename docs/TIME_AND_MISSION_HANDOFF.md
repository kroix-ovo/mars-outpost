# Game pacing and independent shift

Controls are `>`, `>>`, `>>>`, plus pause and keyboard 1/2/3. At normal speed,
one game minute passes per real second: 24 game hours take 24 real minutes.
The HUD displays elapsed game hours:minutes without numeric speed multipliers.
All tutorial instructions use the same arrows.

The world bridge applies presentation pacing before advancing the deterministic
backend. Simulation speed selectors, saved-state schemas, one-second accounting,
physical rates and solar-day definitions are preserved. The configured Mars sol
retains its existing length. Faster presets are tuned for interactive play. The
backend yields between committed ticks after an 8 ms work budget; excess work
remains in its time backlog. Headless `advance()` keeps its deterministic API.

After the reference repairs, the debrief offers **Begin independent shift**.
The always-visible **Tasks** button beside CREW opens a checklist of mission
objectives and colony jobs. It explains the repair requirement and offers **Start
mission 2** when eligible, including with tutorial guidance hidden or disabled.
Mission 2 keeps a six-game-hour objective visible: keep everyone alive and finish
with oxygen, potable water and battery reserves. Crew loss fails immediately;
empty reserves fail at the deadline. Success/failure stays visible until dismissed
or restarted. The objective model only reads committed snapshots; it changes no
resources and awards no synthetic rewards. Mission progress is session-only.

EA's [The Sims 2 Legacy Collection control guide](https://help.ea.com/en/articles/the-sims/the-sims-2-legacy-collection/the-sims-2-legacy-controls/)
documents normal/fast/ultra speed on 1/2/3. Checked with the Firecrawl skill on
2026-11-15 as an interaction reference. The minute-per-second pace is the user's
requested design, not an inferred Sims timing ratio.

Validation: full headless suite; bridge timing/pause checks; live tutorial handoff;
arrow/clock checks; deadline, crew-loss and result-latching cases; rendered cards
at 1280x720 and 1600x900. Terminal-card screenshots use detached presentation
snapshots and do not represent a sustained six-hour colony run.

The HUD caches placement geometry independently of resource affordability. The
key includes the placement request, map, structural building data, site and
expedition records, and injected/occupied cells. Resource costs are checked fresh
on every refresh; changing geometry forces a new authoritative preview.
