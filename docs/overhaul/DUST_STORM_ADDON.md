# Small submission add-on: random dust storm

Implement this in the live submission path, after leaving current work compiling. This is a bounded feature for the current deadline, not a general random-event framework. Preserve the active Fable changes and existing test results. Re-export after implementation.

## Purpose and audience

The supplied challenge brief targets ages 7–12 and prioritizes understandable engineering tradeoffs. Make the storm a short choice about electricity, batteries, oxygen equipment and farming. Show at most three relevant values: solar output, battery reserve, and oxygen reserve. Explain causes in plain language.

Suggested warning: "A dust storm is approaching. Your solar panels will make less electricity. Keep the farm growing, or save power for breathing equipment?"

## Event lifecycle

- Opt in only the live submission/reference profile. Keep ordinary fixture/oracle runs free of unexpected new random draws. Do not enable this globally in every simulation configuration.
- Enable after the camp's initial essential construction/repair objective is stable. First eligibility check 30 simulated minutes later; then check every 30 simulated minutes with 25% probability until selected. Use the simulation RNG, in a fixed tick phase. Seed controls timing and duration.
- One storm at a time. Choose its duration once: two to four mission hours. After it clears, use a 12-mission-hour cooldown before checking again. These are deliberately compressed gameplay values, not claimed NASA measurements.
- On selection, record a pending forecast, pause once, and show the choice. Forecast lead time is 15 simulated minutes after the player resumes. The pause gives a young player time to read regardless of speed.
- At arrival, reduce solar generation to 25% of its normal available output. Ramp visuals if desired, but keep the mechanical modifier and timestamps unambiguous. Show an active-storm badge and time remaining.
- At the recorded end, remove the storm's modifier and any temporary load-shedding policy exactly once, announce recovery, and enter cooldown. Do not permanently dirty or break panels in this small version.

## Two real choices

1. **Save power for breathing.** Temporarily shed farm power demand while the storm is active. Food output stops/reduces through the real production logic. Life support keeps its normal priority; batteries still cover any actual deficit. Clearly state that this choice costs food production.
2. **Keep the farm running.** Leave ordinary priorities unchanged. Solar falls, batteries cover the deficit while charge remains, and existing shortages follow if they run out. Preview remaining battery time when calculable; otherwise say the estimate is unavailable.

Neither choice grants free electricity, oxygen or food. Use the existing ledger and power dispatch. If backup generation actually exists in the live profile, it stays available with its existing costs; do not add a fake generator button or unlimited emergency power.

Use a temporary policy/override rather than losing the player's building enabled settings. Allow a player to change their response during the storm; policy changes are committed commands. Ending the event must not undo unrelated manual changes or enable a building the player intentionally disabled.

## Integration details

- `scripts/systems/power_system.gd` currently applies `power_generation` modifiers to all generation. Add an explicitly validated solar-only modifier/scope, preserving the existing global modifier semantics and tests. Identify solar using stable definition metadata/IDs, not by assuming every generator is a solar panel. Do not let the storm reduce non-solar backup generation.
- Keep state authoritative: status, check time, warning/start/end ticks, cooldown, chosen response, and active temporary policy. No frame-based rolls or wall-clock expiry.
- Freeze storm progression when colony time is paused or a repair challenge is open. The warning pause fires once, not every refresh.
- Publish storm state through a detached facade/bridge view, following the existing repair view if needed. UI/particles read state and never decide outcomes.
- If any active submission save route exists, persist/validate this state and add a roundtrip test. If that route cannot support storms, disable that unsupported route honestly; do not silently clear an active storm on load. The v3 scheduler/oracle must either handle its transitions correctly or keep this live-profile feature disabled.
- Use restrained warm haze/particles and a badge; preserve text contrast. Avoid flashing or camera shaking. A readable banner is required even if particles are skipped.

## Focused acceptance checks

- Same seed and command sequence give the same forecast/start/duration. No storm overlaps or repeated warning pauses.
- At the start boundary, solar is reduced by exactly the configured factor, non-solar generators are unchanged, and battery charging/discharging follows actual net demand.
- Saving power really stops farm production and removes its load; keeping it running can consume more stored energy. Oxygen production follows actual served power.
- Pause, challenge pause, faster speeds, cooldown and clearing boundaries behave correctly. Existing fixtures/oracles are unchanged when the feature is disabled.
- After clearing, solar and normal priorities recover exactly once and independent player settings remain intact.
- Drive the actual HUD warning and both response buttons. Re-export and reach a storm in the exported game. A clearly labeled Storm practice action may demonstrate the same real event, but normal random eligibility must also work.

Register a small focused test suite/marker, run affected power/repair/UI checks, and update SUBMISSION_REVIEW with the shipped behavior and limitations. Avoid another long unchanged scheduler oracle just to validate this isolated opt-in feature.

## Science wording

Use a short explanation: "Less sunlight means less solar electricity. Batteries help for a while, so you must choose which equipment to keep running." Label the 25% output, event timing and duration as game settings. Use existing project science attribution for established resource models. Do not label this live weather or imply the settings came from NASA. If adding measured dust opacity or real storm statistics later, tell the user before undertaking deeper backend research as required by AGENTS.md.
