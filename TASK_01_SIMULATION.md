# Task 01 — simulation and colony systems

**Required interface baseline:** [SHARED_SIMULATION_SPEC.md](SHARED_SIMULATION_SPEC.md). Implement its exact commands, state schemas, time/accounting rules, and persistence contract. Earlier interface sketches in planning documents defer to this spec.

## 1. Executive summary

Build the authoritative simulation that makes the outpost behave like connected engineering systems. Give the other owners stable state, commands, forecasts, and events so buildings, crew, and UI all act on the same colony.

Deliver a headless simulation harness before the finished world is available. The first milestone is a running habitat with resource reserves, powered life support, crew demand, and meaningful failure behavior.

## 2. Mission

Make every breath, unit of water, and watt traceable to a source or sink. Preserve deterministic behavior, explicit units, data-driven tuning, and atomic resource accounting.

## 3. Users

Serve the player making resource decisions and the two contributors building presentation and crew behavior. Provide understandable outcomes and predictable integration hooks.

## 4. Coverage

- [ ] Fixed-step clock, authoritative state, seed/RNG, commands, events, and snapshots.
- [ ] Oxygen, CO2 removal, water recovery, power/batteries, food, materials, and forecasts.
- [ ] Production, commissioning effects, wear, environmental hazards, crops, and technology effects.
- [ ] Save/load, schema checks, reproducibility, and resource invariants.

World geometry, crew movement, and UI belong to the other owners. This ownership boundary does not remove those features from the game.

## 5. User stories

1. As a commander, I want reserves and net rates so I can anticipate a shortage.
2. As a commander, I want production to respond to power loss so I can prioritize loads.
3. As a learner, I want water-to-oxygen dependencies so I can diagnose a stopped electrolyzer.
4. As an operator, I want separate CO2 safety so a full oxygen tank does not hide unsafe air.
5. As a returning player, I want active colony state restored so I can continue reliably.

## 6. Architecture and ownership

Own `scripts/simulation/`, `scripts/systems/`, `data/events/`, `data/tech/`, `SCIENCE.md`, and `tests/simulation/`. Publish shared definitions in `scripts/simulation/` first. Do not edit the main world scene or the other owners' scripts.

Follow `PRD.md` section 6. Coordinate tick order with Task 03, whose crew/task/EVA adapters contribute once per step. Consume Task 02's building definitions. Provide fixtures for a functioning habitat, a power shortage, and a salvage command lifecycle. Register save adapters rather than embedding scene nodes in saves.

## 7. Six work packages — 24 initial points

| Package | Deliverable | Initial points |
|---|---|---:|
| A1 | Clock, `GameState`, command validation/deduplication, snapshots, fixture/harness | 4 |
| A2 | Resource ledger, storage caps, units, electrical supply/load allocation and batteries | 4 |
| A3 | Oxygen/water/CO2 loops, crew-demand interface, verified science parameter entries | 4 |
| A4 | Data-driven building production, agriculture/ISRU/technology effects and forecasts | 4 |
| A5 | Wear, dust/radiation/event effects, emergency state, authoritative save/load | 4 |
| A6 | Headless invariants, deterministic replay, save continuity, integration debugging | 4 |

Points indicate relative planning effort. Rebalance with the team after A1/B1/C1 and the first integrated loop.

## 8. Stack

Use the shared pinned Godot 4 version and typed GDScript. Headless execution must not require a rendered scene. Put tunable definitions in data files and validate them when loaded.

## 9. Configuration and safety

Reject invalid numeric inputs, unknown entity IDs, duplicate commands, invalid units, and malformed save files. Keep scientific source records alongside explicit game assumptions. No secrets or hosted backend are required.

## 10. Interface

Implement `submit_command`, `get_snapshot`, `step`, and the signals specified in `PRD.md`. Emit explanatory rejection reasons. Distinguish queued acceptance from completed action. Resource spending and refunds must be atomic; completion rewards are idempotent.

## 11. Acceptance checks

- [ ] Production stops or degrades when required power/water is unavailable, without negative stockpiles.
- [ ] Crew metabolism, EVA use, and rewards are each accounted for once.
- [ ] Compare an explicit scenario resource balance against independently calculated expected totals.
- [ ] Match seeded command replay across rendering speeds at equal simulated times.
- [ ] Resume a saved active expedition and match an uninterrupted run's later state.
- [ ] Publish source-backed parameter records or clearly marked abstractions before dependent systems use them.

## 12. Phases

1. Publish A1 and draft schemas first; unblock both peers with fixtures.
2. Integrate A2–A3 with one placed building and six crew; validate rates independently.
3. Integrate A4–A5 with build completion, farming, EVA, hazards, and save adapters.
4. Complete A6 and support browser/native scenario checks.

Use the shared phase effort proportions; there is no fixed calendar estimate until team capacity is known.

## 13. Expansion

Extend the same accounting model for higher-closure oxygen recovery, richer crop cycles, nuclear power, thermal systems, and mission-specific tuning. Tell the user before launching deep research to advance this backend.

## 14. Risks

Scientific assumptions can create false realism: identify status and source. Tick coupling can double-charge resources: give each flow one owner. Heavy shared-state work can delay peers: deliver the contract and fixtures first.

## 15. Handoff

Use branch `feat/simulation`. Return changed paths, commands/checks run, known assumptions, and one reproducible scenario. Avoid editing shared contracts after agreement without coordinating affected owners. See `PRD.md` for overall requirements.
