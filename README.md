# Mars Outpost

We started Mars Outpost for NASA Space Apps because we wanted space survival to feel like a set of decisions we could actually make. It is easy to say astronauts need oxygen, water and food. We wanted to see what happens when those systems share a limited power supply, something breaks, and keeping one part running means giving up something somewhere else.

Our game puts us in charge of a small outpost on Mars. We build a farm, give our crew jobs, watch our reserves and deal with equipment failures and environmental events. We built it in Godot 4.7.2 with a 3D world and a simulation underneath it that accounts for resources as time moves forward.

## Getting our first camp running

We began with the systems that keep the crew alive: oxygen generation, carbon dioxide removal, water recovery, solar power and batteries. We kept those calculations separate from the world and interface so a button changes the simulation through a command, rather than changing a number on the screen.

Once those pieces were connected, we needed something to do with them. Our current mission starts from the title screen and walks us through placing a greenhouse, assigning an engineer to build it and assigning a botanist to tend it. The farm uses water, carbon dioxide and electricity to produce food and oxygen. After we get it working, an equipment incident gives us our first repair. Finishing that loop establishes our Level 1 camp.

One problem we found while playing the exported build was that our scrubber could take the carbon dioxide before our farm got any. The farm then stopped producing and the objective could get stuck. We changed the resource routing so the farm uses available carbon dioxide before the remaining gas is scrubbed. We kept electrical priority separate, so that change does not put farming ahead of life support for power.

## Giving our crew something to do

We wanted our astronauts to matter beyond being names in a list. Engineers take construction work, and our botanist has a real tending job at the greenhouse. Engineering skill also changes the repair challenges, giving a specialist an easier task than someone without that training.

We added two kinds of repair. Circuit repairs ask us to connect lettered leads to matching shapes. Solar repairs ask us to stop a moving indicator inside an alignment band. A failed attempt fully breaks that component and locks another attempt for one mission day. Some repair mistakes can injure the astronaut, with a recovery period before they can return to work.

We still have more to do here. Our medic, pilot and geologist have specialties, but we have not finished a complete daily job system for every role. We also have not built the med bay treatment loop or the full eating and sleeping routines.

## When Mars changes our plans

Once our camp is established, dust storms can reduce solar generation. We can pause the farm to protect our power reserves or keep food production running and draw on the batteries. The storm has a forecast, a duration and a cooldown, so it becomes a decision we have time to respond to.

We also added a solar radiation event. We can shelter the crew to reduce the health penalty, but their work pauses while they are sheltered. That is the trade we wanted to show: protecting our astronauts costs us progress on the jobs outside. Our radiation numbers are a simplified game model, not a medical dose calculation or a live space-weather feed.

## Making the game easier to read

As we added systems, our interface started competing with the game. We moved toward dark panels, a small resource bar and a bottom navigation dock. We keep most details behind the relevant tab and give the current objective a direct action button. Our crew panel uses close portraits and separate lines for names and specialties. Playback uses drawn pause and speed icons so we can find time controls quickly.

We took inspiration from how colony and city-building games keep common actions nearby while letting the world take up most of the screen. Our [design notes](DESIGN.md) record the visual choices. Our [screenshot pack](docs/evidence/submission_slides/README.md) shows the actual game, including construction, crew work, repairs and the two environmental events.

## What we checked

Our final local headless regression run passed, including 46 farm and repair checks, 29 dust-storm checks, 16 radiation checks, 331 campaign-foundation checks and 318 scheduler checks. Our menu, tutorial, world, simulation and compatibility checks passed too. We also ran focused native interface checks and captured the game through Godot's renderer. GitHub CI passed tests and Web, Windows and Linux exports for our submission PR.

We kept the long campaign oracle out of the final submission-night rerun. The quick scheduler checks and a full detailed-day oracle are different checks, and we do not treat one as proof that we reran the other. Our [submission review](docs/overhaul/reviews/TAKEOVER_SUBMISSION_REVIEW.md) separates those results and records the remaining limits.

## Running our game

We open `project.godot` in Godot 4.7.2 and run the project to start at the title screen. New Game takes us through crew setup and the landing introduction into the camp mission. The repository's GitHub Actions workflow builds Web, Windows and Linux artifacts.

For the headless regression checks, we run:

```sh
python tests/run_headless_checks.py --godot /path/to/godot --quick
```

Removing `--quick` also runs the longer detailed-day campaign oracle. Our authored fixture checks and science notes live alongside the tests so we can trace where our numbers came from.

## Where we go next

Our playable build is the first camp loop. Our larger plan includes connected habitat interiors, medical treatment, daily crew routines, upgrades and supply deliveries. We built a separate campaign save and scheduler foundation to support that work, but it is not yet the live mission. Save and Load stay unavailable in the current camp rather than pretending to preserve events they cannot restore.

We keep the full direction in our [overhaul plan](docs/overhaul/README.md). Our next step is to connect those systems carefully enough that the camp feels like a place our crew lives in, while keeping the decisions understandable for younger players.

## Science and credits

We use NASA reference crew rates in the authored landing scenario and label our gameplay assumptions separately. Our crop conversion, storm timing, repair difficulty and radiation health penalties are simplified mechanics. [SCIENCE.md](SCIENCE.md) explains the sources and assumptions, and [ATTRIBUTION.md](ATTRIBUTION.md) lists external assets and credits. This is an independent project and does not imply NASA endorsement.

## Tools we built with

We used agentic tools, including Anthropic's Claude, OpenAI's Codex and Cursor, while building this project. These tools helped us develop code, work through implementation ideas, write documentation and run checks. We made the project decisions and reviewed the results as we brought our game together.
