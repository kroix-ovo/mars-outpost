# Living colony design

## Player experience

The player is one of six astronauts and commands the others. Productive routine days alternate with difficult periods caused by tight resources, wear, weather and injuries. Preparation should let the player recover; neglect and severe incidents can kill crew. Manual saves and three rotating autosaves allow recovery. Select a surviving successor if the commander dies. The campaign ends if no crew remain.

Commander mode moves the player astronaut. Overview mode pans the camera, builds and assigns jobs. Tab and a visible mode button switch modes. Do not let WASD move both the camera and astronaut at once. Remote orders remain available. The operator selected for a repair temporarily supplies its skills; this does not replace the commander.

## Ship and camp

The ship is distinct from the camp: communications, arrival cargo and temporary shelter. Its consumables and shelter capacity are finite. Begin with a pre-landed cache and a deployable core. Habitat wings have a 6 by 6 metre floor grid; connect them through authored doorway sockets, then furnish their interiors. Use a 64 by 64 metre logical campaign map for the initial camp, landing area and exploration approaches. Keep the existing fixture maps unchanged.

Interior essentials: bunks, cafeteria, farms, med bay, workshop, oxygen/CO2 support, water recycler and storage. Exterior essentials: solar, backup generator, batteries, utility routes, landing pad and extraction. Furniture occupies room cells, not the exterior footprint a second time. Each wing needs a clear door-to-door walking route. Preview build failures before spending.

Construction, sealing, connection and commissioning are separate states. A connected atmosphere zone has volume, oxygen reserve, CO2 inventory and safety status. Isolation doors split zones and utility service explicitly. Reuse the ledger for gas transfers; do not copy a common gas reserve into every wing. Ship shelter is a separate zone. Label this as a simplified game model.

## Daily loop

One mission day is 86,400 simulated seconds. A mission month is 30 days. Every 180 days supplies arrive. This is a campaign-calendar abstraction, not a claim about Mars orbital delivery windows or sol length. Normal speed targets 120 simulated seconds per real second: about 12 real minutes per mission day. Pausing never advances survival time.

Default meals are at hours 7, 13 and 19, with two-hour meal windows. Default sleep is 22:00–06:00. Missed meals draw on nutrition reserves; health loss follows prolonged deficit rather than a missed button press. At meals, transfer food from shared stock into the astronaut's nutrition reserve. Metabolic use drains that reserve, never shared food a second time. Oxygen/water and waste remain accounted separately. AI manages its own needs; the commander acts manually during ordinary play and uses visible meal/sleep standing orders only during requested fast-forward. Expeditions carry prepaid meal portions and cannot also debit cafeteria food.

Engineering staff inspect and maintain equipment; medics staff treatment; botanists tend crops; geologists survey/extract/research; pilots/logistics staff handle deliveries and expedition readiness. All jobs require actual travel and equipment access. Work queues and bed/meal capacities must be authoritative. Immediate danger and medical needs outrank scheduled meals/sleep, which outrank normal work. Overtime is explicit, temporary and shows its fatigue cost.

Illness/injury episodes are seeded, one to seven days, with severity, treatment needs, recovery progress and prognosis. Injured staff go to med bay; immobile staff require rescue. Covering actual missed work increases others' fatigue. An absent engineer leaves inspections undone and increases documented fault risk. Cap combined risk multipliers.

## Repairs

Routine maintenance is automatic. Corrective repair requires an assigned operator's travel and preparation, then a component-specific challenge. The player plays through that operator. Engineering skill affects hints, stages, speed and tolerances; high skill is useful without guaranteeing success. Use original interfaces inspired by Among Us tasks.

| Component | Interaction |
|---|---|
| Electrical distribution/battery | Trace labeled circuits and connect matching terminals |
| Solar tracker | Align drifting indicators and lock calibration |
| Generator | Stabilize temperature, then synchronize ignition |
| Airlock | Isolate leakage and equalize chambers in sequence |
| Oxygen equipment | Balance flow controls within a safe mixture |
| Water recycler | Route through clean filters and flush dirty branches |
| Farm irrigation | Find a blockage and restore flow without flooding |
| Medical equipment | Calibrate a scan signal and validate its setup |

On failure set condition to zero and lock the component's corrective repair for 86,400 simulated seconds. Other crew and routine maintenance cannot bypass the lock. Spent attempt materials remain spent. Isolation, backup machinery and building redundant equipment remain available. Show the exact retry time.

The colony pauses during a challenge. Only active, focused challenge time advances its timer. Save/resume the same challenge and random state. Keyboard alternatives, symbol labels, non-color cues and a slower accessibility mode are required. Closing a modal cannot silently succeed or clear the failure rule.

## Events and replayability

Seeded authored events have prerequisites, weight, warning, duration, cooldown, choices, effects and resolution. Initial families: machinery faults, injuries, illness, dust fronts, crop problems, exposed cargo and research discoveries. Limit concurrent major events to two and normally require two quiet days between major incidents. Tutorial scripts temporarily control pacing.

Risk comes from condition, use, environment and maintenance coverage. Explain the causes in UI. A disabled machine is not eligible for a use-related incident. Positive discoveries matter too. Vary terrain resources, salvage, traits, contracts and research opportunities within authored safe bounds. Cross-training improves secondary skill through training labor, with a cap below the native specialist level.

## Progression

| Camp level | Required capabilities | Unlocked direction |
|---|---|---|
| 1: Established | Safe camp, power, first crop planted, beds, meals, treatment and tutorial repair resolved | Surveys and first research |
| 2: Reliable | Backup power/life support, a completed harvest and seven safe days | Broader crop production and resilience |
| 3: Productive | Working workshop and extractor, two crop types, trained backup specialist | Common-part fabrication and specialization |
| 4: Resilient | Laboratory, shielding, automation and expanded treatment | Larger operations and more ambitious contracts |
| 5: Settlement | Day 720, all prior capabilities and recovery from a major disruption | Ending milestone, then endless play |

Evaluate levels from real capability flags and persist earned level/unlocks. Temporary damage does not revoke earned research. Later arrivals offer parts, not automatic level increases. The first shipment occurs at day 180; initial materials plus local production must support survival to then.

Research uses surveys, experiments, crop trials and milestones. Cargo brings scarce seeds and hardware. Local materials and installation labor finish the upgrade. Each component has Mk I–III hardware and one replaceable specialization slot. Upgrades require downtime. Show costs, output, utility use, labor and maintenance changes before committing. Replacement recovers only authored salvage.

Farm branches: yield, water efficiency, disease resistance. Solar: output, dust resistance, cleaning automation. Generator: fuel efficiency, peak output, maintenance resilience. Batteries: capacity, discharge rate, containment. Life support/recycler: throughput, efficiency, redundancy. Med bay: beds, recovery support, diagnosis. Workshop: throughput, material efficiency, fabrication range. All benefits must have a real simulation effect and a corresponding cost or opportunity cost.

Crop content starts with potatoes and lettuce, then beans, tomatoes and medicinal plants. Growth requires water, nutrients, lighting and tending; seeds, propagation, harvests and spoilage are accounted. Seed propagation diverts part of the harvest. Medicinal plants are a game crafting ingredient, not a medical efficacy claim. Perks such as preventive maintenance and careful crop handling improve named processes, never create free resources.

Shipments arrive on days 180, 360, 540, 720 and every 180 days thereafter. The ordering deadline is 30 days before arrival. A manifest has 12 cargo-space points, plus a modest guaranteed baseline allocation. Default discretionary manifest: four parts packs, two seed banks, two medical packs, two fuel packs and one food pack (12 points). Preview and confirm changes before deadline; freeze the manifest then. Cargo overflow remains in a visible unloading queue. Logistics staff move it into storage without duplication or silent loss.

## Tutorial

One persistent campaign: arrive → meet crew/control modes → inspect cache → deploy core/airlock → build living/farm/service wings → furnish beds/cafeteria/farm/med bay → install generator/solar/battery/utilities → seal and commission → move in/assign roles → eat/sleep/plant → resolve a controlled fault → inspect supply plan → Level 1.

Trigger the scripted fault once near the end. Provide enough backup capacity to live through a failed attempt and its full one-day lockout. Teach load shedding/isolation, then allow a real retry. Advance from committed outcomes and accept work done early. Cancellation, invalid placement, depleted materials and reload must leave a recovery route. Skip tutorial constructs a defined Level 1 start through the same accounting rules. Do not switch from training to a reset colony halfway through.

## Evidence

Report simulation tests, rendered automated checks and manual playtests separately. Do not claim this design is implemented because a catalog, mock scene or fixture exists. Before release, validate multiple seeds and both efficient and resilient upgrade strategies, then play the actual exported build.
