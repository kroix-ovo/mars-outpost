# Science parameters

This file is the single source of truth for simulation quantities. Populate entries from verified primary sources before introducing scientific constants into game data or scripts. Distinguish measured results, proposed systems, and game abstractions.

The A3 reference profile adopts the parameters below with their stated scope. Synthetic fixture values remain synthetic and unchanged. Source-backed physiology does not make the authored equipment ratings or the whole game flight-validated. Research and implementation decisions are in [A3 research and solution](docs/A3_RESEARCH_AND_SOLUTION.md).

## A3 reference entries — verified 2026-11-15

| ID / parameter | Reference and game use | Status and context | Primary source |
|---|---|---|---|
| A3-CREW-O2 | 0.895 kg/crew/Earth day; divide by 86400 for runtime | NASA reference model, BVAD Table 3-31, 82 kg astronaut with specified exercise schedule. Uniform daily average is a game simplification. | [BVAD 2022](https://ntrs.nasa.gov/api/citations/20210024855/downloads/BVAD_2.15.22-final.pdf) |
| A3-CREW-CO2 | 1.085 kg/crew/Earth day, same conversion | Same reference model; not a universal measured rate for every crewmember or activity. | [BVAD Table 3-31](https://ntrs.nasa.gov/api/citations/20210024855/downloads/BVAD_2.15.22-final.pdf) |
| A3-CREW-WATER | 3.217 kg potable water/crew/Earth day | Reference includes drinking, food preparation and exercise-associated water; excludes separate water in supplied food. | [BVAD Table 3-31 and notes](https://ntrs.nasa.gov/api/citations/20210024855/downloads/BVAD_2.15.22-final.pdf) |
| A3-WASTE-COLLECTION | 1.420 + 2.946 = 4.366 kg/crew/Earth day | Derived urine + respiration/perspiration water. Perfect collection into one account is a game abstraction. Food moisture/metabolic water are boundary sources; fecal water and hygiene excluded. | [BVAD Table 3-31 and Figure 3-4](https://ntrs.nasa.gov/api/citations/20210024855/downloads/BVAD_2.15.22-final.pdf) |
| A3-FOOD | Reference 12.778 MJ/crew/day; game target 3000 kcal/crew/day | Rounded gameplay target, not a new claim that 3000 kcal equals the table's exact energy. Food inventory models energy, not food mass. | [BVAD Table 3-31](https://ntrs.nasa.gov/api/citations/20210024855/downloads/BVAD_2.15.22-final.pdf) |
| A3-SOL | 88775.244 SI seconds per mean solar sol | NASA astronomical reference. Calendar parameter only; does not replace the 86400-second Earth-day rate denominator. | [NASA GISS Mars24](https://www.giss.nasa.gov/tools/mars24/help/notes.html) |
| A3-ELECTROLYSIS | Water -> O2 + H2; rounded mass fractions 8/9 and 1/9 | Derived stoichiometry using rounded atomic masses. Absolute throughput/power remains game sizing, not NASA equipment performance. | [NASA-hosted electrochemical life support paper](https://ntrs.nasa.gov/api/citations/20200002346/downloads/20200002346.pdf) |
| A3-RECOVERY | Game recycler recovery 0.90, loss 0.10 | Explicit game abstraction. ISS reports ~98% for a linked processing chain; different feed/collection boundaries prevent assigning that result to this one module. | [2026 ISS water report](https://ntrs.nasa.gov/api/citations/20260004140/downloads/2026%20Status%20of%20ISS%20Water%20FINAL.pdf), [2024 comparison](https://ntrs.nasa.gov/api/citations/20240005472/downloads/ICES%202024-317%20Status%20of%20ISS%20Water_Final.pdf) |
| A3-CO2-ALERT | Reference: <=3 mmHg one-hour average; game: instantaneous 400 Pa warning | NASA-STD-3001 Vol 2 Rev F V2 6004, approved 2026-07-14. Game warning is not exposure averaging, medical prediction or compliance testing. | [Rev F standard](https://www.nasa.gov/wp-content/uploads/2025/05/nasa-std-3001-vol-2.pdf) |
| A3-ATMOSPHERE | Game V=100 m3, T=295.15 K; R=8.314462618 J/(mol K), M(CO2)=0.0440095 kg/mol | Volume/temperature are game assumptions; p=mRT/(MV) is a well-mixed ideal-gas approximation. Derived mass alert threshold is 400*V*M/(R*T). The rendered map is not a volume measurement. | [NASA gas law](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/equation-of-state/), [NIST R](https://physics.nist.gov/cgi-bin/cuu/Value?r), [NIST CO2](https://webbook.nist.gov/cgi/cbook.cgi?ID=C124389&Units=SI) |
| A3-DESIGN-MARGIN | Six crew, 20% nominal throughput margin; existing module kW | Game sizing rule derived from reference demand. No claim of measured machinery performance, validated reliability or continuous safety. | This game's design; calculations in [solution](docs/A3_RESEARCH_AND_SOLUTION.md) |
| A3-OFF-NOMINAL | CO2 scales with O2 service; collected wastewater with min(water,food) service; overflow lost explicitly | Game abstraction to avoid modeled output with empty inputs. Human reserves, illness, death and recovery require later hazard/crew integration. Suit hardware, leakage and injury coefficients are not adopted. | This game's boundary policy, not a physiological source |

## Entry template

```text
Parameter:
Value/range:
Game value:
Source:
Status: NASA-demonstrated / proposed / game abstraction
Rationale:
```

Record units and time bases explicitly, including the distinction between an Earth day and a Martian sol. Include source context and verification date with each completed entry.
