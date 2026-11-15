# HUD and camera fixes from the screenshot playtest

The HUD uses a 1600x900 logical canvas instead of 1280x720. Crew width is 232 px; the context drawer is 320 px. Regular tutorial cards show the current instruction; Details expands the background explanation. Welcome/orientation keep their explanations visible. The Guide no longer duplicates the complete checklist while the tutorial is already visible.

UI highlights are drawn inside controls, without triangles over preceding text or crew rows. Crew stats use separate rows with the two strongest skills; all skills remain in the tooltip. Training names are presented as Astronaut A/B rather than internal fixture labels. Resuming updates the hidden notice immediately, and notices expire after 4.5 seconds.

Idle base crew are rendered inside the habitat (no exterior suit mannequin). Active workers and spacewalk crew remain visible. Group labels only include visible avatars. Simulation positions and balances are unchanged.

## Camera bindings

Based on the original [Cities: Skylines user manual, pages 4-5](https://steamcdn-a.akamaihd.net/steam/apps/255710/manuals/CitiesSkylines-UserManual_EN.pdf): edge scrolling and WASD/arrows pan; hold middle mouse to rotate/tilt; Q/E rotates; Home/End tilts; wheel or Z/X zooms. Right click cancels the current placement or selection. Space pauses; 1/2/3 choose the existing game speeds 1x/5x/20x. F recentres (our extension because Home now tilts). Edge scrolling is suppressed over HUD panels, outside the window, during an orbit drag, while typing and when the window is unfocused. Releasing middle mouse over a panel still ends orbit.

## Verification

Automated checks cover tutorial skip/resume notices, actual EVA return with exterior avatars hidden, layout bounds/highlights at 720p, 900p and 4K, and camera button/edge/selection/time bindings. The camera regression is part of the headless runner. No manual gameplay walkthrough was performed for this revision. Rendered checks use Dummy audio.
