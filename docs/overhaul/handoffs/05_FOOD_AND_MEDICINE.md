# Package 5: Agriculture, injuries, treatment and workload coverage

## Fable 5.2 task

Implement this package in the existing repository. Read `AGENTS.md`, `docs/overhaul/DESIGN.md`, `docs/overhaul/CAMPAIGN_CONTRACT.md` and `docs/overhaul/FABLE_WORKFLOW.md` first. Preserve current work and use the real simulation/ledger. Complete this package and its review handoff, then stop before starting another package.

Prerequisite: Package 4 reviewed.

## Implementation

- Implement crop batches with planting, growth stages, tending labor, lighting/water/nutrient needs, harvest, spoilage and optional seed propagation. Begin with potato and lettuce; retain research/seed gates for later varieties.
- Use the authored catalog as initial game balance only. Add declared nutrient/seed/medicine accounts and units to the ledger/registry, with source/sink paths and capacities. Flag any useful deeper backend research to the user before undertaking it.
- Require a commissioned safe farm and botany labor. Shortages reduce/stop actual progress; no harvest is created by animation or tutorial acknowledgement. Propagation diverts harvest value.
- Implement seeded injury/illness episodes lasting one to seven days, medical severity, bed reservation, medication, treatment labor and recovery. Patients stop work and go to med bay; immobile patients require rescue.
- Add assign_treatment/request_rescue commands and emergency aid when beds are unavailable. Missing treatment worsens health by explicit policy; do not silently mark patients recovered.
- Reassign real vacant workload or leave backlog. Covering staff gain fatigue from extra labor; do not apply a blanket fatigue penalty.
- Implement death, release reservations/tasks, and allow commander succession. Preserve body/deceased record identity so references do not break.
- Add workshop common-part fabrication as a labor/resource conversion once installed, so local materials can support the initial 180-day interval. Keep specialist imports gated for package 9.
- Save crop/episode progress, treatment reservations and cargo/seed effects; register growth, meal, recovery and danger boundaries for fast-forward.

## Required verification

- Test full and deficient crop cycles, harvest once across reload, propagation tradeoff, full storage, spoilage, lost power and absent botanist.
- Test one-day and seven-day episodes, no bed, absent medic, rescue, medicine exhaustion, interrupted treatment, recovery and death.
- Compare covered workloads with uncovered backlog and verify fatigue follows labor. An injured engineer's absence must reach maintenance coverage data.
- Advance sustainable and failing farm configurations through fast-forward and detailed stepping; assert equivalent transitions. Add CAMPAIGN_BIO_PASS.

## Completion gate

Real food production and medical consequences tied to crew availability and resource accounting.

Write `docs/overhaul/reviews/05_FOOD_AND_MEDICINE_REVIEW.md` with behavior, interfaces, actual checks/evidence and limitations. Run the normal headless suite and relevant rendered checks. Do not commit, push, merge or deploy without a separate instruction.
