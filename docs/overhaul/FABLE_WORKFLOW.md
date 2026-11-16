# Fable 5.2 workflow

Use one package per implementation session. Read its dependencies before editing. The repository's `AGENTS.md` applies, including telling the user when deeper backend research would help. Fable is used for coding; do not add model API calls to gameplay.

## Before implementation

1. Work in `C:/Users/Symok/Documents/Nasa_Space_Apps_Overhaul`, branch `overhaul/living-colony-pr10`, based on PR #10 merge `5d33c7b`. Inspect status, branch and worktrees. Preserve the uncommitted foundation/handoff files. The original `Nasa_Space_Apps` checkout retains older dirty HUD/camera/tutorial work; do not overwrite PR #10's integrated versions with those files.
2. Read the overhaul design, campaign contract and selected package. Confirm its prerequisite package has a review handoff with passing evidence.
3. Run the existing foundation and relevant baseline checks. Capture failures before making changes.
4. Name the concrete public interfaces the package will add. Update the contract when implementing them. Implement only this package.

## While implementing

- Extend the real facade, ledger and headless world service. Do not build a parallel gameplay inventory or a UI-only version of the mechanic.
- Keep the existing fixture profile stable. Campaign content/rules get their own profile and tests.
- Provide a production path that can be exercised by real commands. A mock scene, data table or hidden debug button alone does not complete a feature.
- Implement and validate save/load alongside the feature. Replace the foundation's empty-only partition guard when that subsystem becomes real. Record its migration/version policy.
- New commands must be queued, validated again on resolution, rollback-safe and deduplicated across reload. New economic effects go through retained receipts or bounded tick guards.
- Keep feature capabilities false until real implementation passes its checks.
- Add tests for behavior and failure/continuation boundaries. Register the suite in `tests/run_headless_checks.py` and document its success marker.
- Do not rewrite unrelated old tests, regenerate science fixtures to hide a changed result, or run destructive cleanup.
- Do not commit, push, merge, deploy or change a shared integration branch unless separately instructed.

## Required review handoff

Write `docs/overhaul/reviews/NN_<PACKAGE>_REVIEW.md` with:

1. Concrete behavior implemented and how to exercise it.
2. Public commands, snapshot/save schemas and content changes.
3. Actual changed paths and prerequisite package/version.
4. Tests run, exact commands, success markers, logs, and any baseline failures.
5. For UI work, rendered screenshots at 1280x720, 1600x900 and 3840x2160, plus input checks. State whether manual playtesting occurred.
6. Limitations and remaining work. Distinguish implementation from fixtures, rendered automation and human playtesting.
7. The next package that is now unblocked.

End the session with that review handoff. The user will return it for review before the next package starts. A failing required check leaves the package incomplete, even if the code compiles.

## Review checklist

- Does the feature run through normal user commands?
- Are resources spent and awarded exactly once, including cancel/reload/retry?
- Do all state changes survive saves? Are malformed loads rejected without partial replacement?
- Does the headless logical result agree with rendered activity?
- Does fast-forward process the same transitions and stop at the same threats?
- Are specialist, room and equipment capacities meaningful?
- Are the baseline checks still valid and passing?
- Are science claims and gameplay assumptions clearly separated?
