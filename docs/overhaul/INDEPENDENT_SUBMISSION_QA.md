# Independent submission review

This file is written by the reviewing assistant, separately from Fable's active source changes. Fable owns the implementation and SUBMISSION_REVIEW. Findings here are observations, not instructions to discard current work.

## Verified baseline

- At approximately 9:24 PM Eastern on November 15, `build/submission-validation.log` ended in `HEADLESS_PASS`. It included `REPAIR_FARM_PASS checks=38`, `CAMPAIGN_FOUNDATION_PASS checks=331`, and `CAMPAIGN_TIME_PASS checks=326`, plus the existing title/frontend/colony checks.
- This result covers the source snapshot tested by that run. It does not automatically cover the later storm, camp, role or tutorial edits now underway.
- The 9:13 PM Windows export opens its title screen. Independent UI inspection confirmed that title screen. New Game/camp gameplay has not yet been independently verified in the exported executable; input automation yielded when concurrent user input was detected.
- The existing source-level rendered walkthrough drives the real HUD handlers and simulation, but is distinct from physical input through the exported binary.

## Findings to address during the current finish pass

### High: Level 1 can claim stabilization without checking survival

In `scripts/ui/outpost_hud.gd`, `camp_progress()` currently sets `handled` when any fault is repaired OR locked and the session is closed. Thus a failed, locked component counts as stabilized without checking oxygen, CO2, power or battery state. The message can say "on backup equipment" without proving backup capacity exists.

Use an explicit achievable stability condition for the failed-repair path: critical life support served, safe current oxygen/CO2 state, and declared remaining reserves/backup coverage. Do not require one second of farm output plus an arbitrary failed repair as proof of safe camp operation. If this cannot be implemented safely, label the milestone "Setup complete; emergency unresolved" until the fault is repaired. Add one focused test with a locked fault and unsafe reserves that must NOT claim established/safe.

### High: Normal launch and exported input path

The 9:14 review requires F3 to access the farm. The current finish handoff already asks for normal-menu mission access and guided objectives. After implementation, re-export and drive that path from the actual menu; do not substitute a scene override or source-only handler test.

### Medium: Farm output is a supplement

The current greenhouse's authored maximum is 0.05 kcal/s, or 4,320 kcal per 86,400-second Earth day. The documented six-person reference food target is 18,000 kcal/day. Even at full output this supplies 24% of that target; limited inputs/power reduce it further. This is useful resource-management gameplay, but do not describe one greenhouse as food self-sufficiency. Display or explain that stored food is still needed. These crop rates remain authored gameplay assumptions, not NASA crop measurements.

### Medium: Save capability must match the live path

The live v2 submission route currently advertises persistence false. Retain the disabled save controls unless the new faults, cooldowns, injuries and storm state are genuinely serialized/validated. The separate v3 foundation's saves do not establish that the live v2 mission can save those systems.

### Medium: Keep challenge-time command volume bounded

The repair panel sends a transactional `repair_input: tick` every rendered frame. This may generate thousands of retained journal entries during a challenge. Verify frame responsiveness and journal growth during a real 75-second challenge. A bounded update cadence can reduce command volume, but preserve total active time and input ordering; never discard elapsed time merely to improve performance. This is a risk to measure, not a confirmed frame-rate regression.

## Final review gates

- Fable's active storm/camp/tutorial additions compile and pass their focused checks.
- The Level 1 message matches actual safety state.
- No required step uses F-keys, developer controls or an undocumented mouse action.
- The rebuilt executable's timestamp/hash match the final tested artifact.
- Exported New Game reaches the camp; farm placement/assignment, a repair and a storm choice work with normal input.
- Science attribution distinguishes reference physiology, static project data and authored game balance.
- Submission description lists only features actually present in that artifact.

No source files were edited by this review. No build was uploaded, submitted or published.
