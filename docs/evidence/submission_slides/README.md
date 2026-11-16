# Slide screenshot pack

1920 x 1080 PNGs rendered by the actual Godot game. These are reproducibly staged
gameplay scenes, not painted mockups or evidence of an uninterrupted human playthrough.
No game feature code was changed to make this pack.

| Slide | Recommended image | Headline |
| --- | --- | --- |
| 1 | 01_title_clean.png | MARS OUTPOST |
| 2 | 02_build_placement.png | BUILD YOUR FIRST OUTPOST |
| 3 | 03_resource_tradeoffs.png | EVERY WATT HAS A JOB |
| 4 | 04_crew_work_closeup.png | PUT YOUR CREW TO WORK |
| 5 | 05_circuit_repair.png | SOMETHING WILL BREAK |
| 6 | 06b_dust_storm_active.png and 06c_solar_radiation_warning.png | MARS CHANGES THE PLAN |
| 7 | 07_established_clean.png | PLAY. DECIDE. UNDERSTAND. |

Alternates retain the actual HUD, show the dust forecast, or show active sheltered
radiation conditions. The radiation event is represented by the game's warning and
shelter decision; the game does not render a visible explosion in the sky.

The title and established clean variants hide the HUD at capture time. Other images
retain their actual gameplay UI. Weather uses the real simulation, including the
explicit dust-storm practice command. Radiation is a compressed educational health
model, not a medical dose calculation or live space-weather feed.

Reproduce using the project Godot version:

    godot --path . --resolution 1920x1080 --audio-driver Dummy --script tests/visual/capture_submission_slides.gd

The `-- framing` argument captures only the camp and crew variants without waiting
through the storm. Both passes write into this folder. Add slide text as editable
text over the screenshots; keep important gameplay controls and faces clear.
