# 031.003 — Slice 1: Native detail-host disappearance

## Context

The last amendment in `000-plan.md` limits this slice to sheet↔inspector migration
on top of the 002 fix. The maintainer's constraint is: **"don't make other devices'
appearance change."** Local implementation and commits are authorized; pushing and
slice 2 are outside this delivery.

Recovered implementation evidence: `9c69f26` staged a visible outgoing host until
its disappearance, but could wait forever if SwiftUI lost that callback. Its
inspector binding also predates 002's deferred dismissal handling. This amendment
reuses the model staging and relevant tests, not that older binding implementation.

## Change

- A visible outgoing host is marked as retiring and dismissed natively before the
  replacement host is created. Its content stays mounted during that transition.
  A host that never appeared does not need to wait for disappearance.
- The canonical detail and root-owned `EntryDetailSession` survive retirement.
  The latest requested host and entry win if selection or size class changes
  again. Pending edit requests detach from the retiring host and retarget to its
  replacement; stale close, edit, disappearance, and recovery callbacks cannot
  act on a newer generation.
- A cancellable, host-ID-scoped task bounds retirement to two seconds if native
  disappearance is lost. Recovery clears the outgoing sheet visibility gate only
  for that ID and respects migration blockers before reconciling the latest
  destination. Two seconds is a recovery budget, not a normal migration delay or
  a documented system animation duration.
- 002's local inspector-column state and next-main-actor-turn dismissal handling
  remain. The sheet visibility gate now records a presentation ID so an old
  disappearance cannot clear a newer sheet's gate.
- No toolbar, gallery, grid, layout policy, user-facing text, or styling changes.
  This is shared lifecycle handling; no device-specific visual treatment is added.

Rejected: immediate replacement of a visible native host (overlaps outgoing and
incoming presentation); an unbounded disappearance wait (can prevent future opens);
replacing 002's deferred inspector setter with the earlier synchronous setter
(loses its size-class-transition protection).

## Refs

- Base: the 002 fix on `main`; both were later squashed into one commit.
- Reused staging: `9c69f26` (reflog history, not cherry-picked wholesale).
- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryEntryInteractionStateTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/EntryDetailSessionTests.swift`

## Validation

Performed on 2026-10-22 using only the already-booted iPhone Duo simulator,
`15634C6F-DD0D-4B51-8D75-D4F53BE16311`, iOS 27.1. No other simulator was booted.

- `make test-app-sim BOOTED_SIMULATOR_ID=15634C6F-DD0D-4B51-8D75-D4F53BE16311 APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/EntryDetailSessionTests'`
  passed, both before and after strengthening pending-edit and session-retention
  assertions. Final xcresult summary: 41 tests / 43 runs including parameterized
  cases, zero failures, zero skipped tests. Coverage includes both retirement
  directions, latest entry/destination, stale callbacks, lost-disappearance
  recovery, migration blockers, and exact session reuse through retirement.
- `make run-sim BOOTED_SIMULATOR_ID=15634C6F-DD0D-4B51-8D75-D4F53BE16311`
  built, installed, and launched successfully.
- `sim-use ios fold closed|open --device <Duo UDID>`, taps, UI outlines after each
  action, and inspected screenshots exercised the following matrix. Inner display
  was landscape-left (951×669 pt); cover was portrait (466×678 pt).

| Path | Gallery | Grid | List |
| --- | --- | --- | --- |
| A: Inspector open → fold → cover sheet → unfold → populated inspector | ×2 | ×2 | ×2 |
| B: Inspector open → fold → Done on cover → unfold → no inspector column | Passed | Passed | Passed |
| C: Detail closed → fold → unfold → full-width library, no column | Passed | Passed | Passed |
| D: Detail closed → fold → open on cover → unfold → populated inspector → Done | Passed | Passed | Passed |

  One immediate outline on gallery path A's second unfold omitted Done while
  detail content was present, causing the local observation assertion to fail.
  A subsequent outline and screenshot showed Done restored and the inspector
  populated; no code change or replay was needed. Some outlines immediately
  after Done used sim-use's flat accessibility recovery; later outlines and
  screenshots confirmed the resulting closed/full-width state. No empty trailing
  column, stuck detail opening, or process-disappearance signal was observed.
  Screenshots and outlines were kept locally outside the repository.
- Targeted `swift format lint` for the four changed Swift files and
  `git diff --check` passed.

Unverified: non-Duo iPhone/iPad/macOS runtime appearance, inner portrait and
partially folded poses, nested modal continuity in the running app, and
fault-injected loss of an actual SwiftUI callback. Callback loss and blocker
recovery were tested deterministically in the interaction model; the running
app was not instrumented to prove whether any two-second recovery task fired.
002's deferred binding handling still relies on the observed main-actor ordering
described in that amendment.

## Current state

Slice 1 implemented and first-pass Duo validation complete; Claude Code review and
re-verification remain. The overall plan stays in progress. Slice 2 has not started.

## Review (Claude Code, 2026-10-22)

Accepted. Reviewed the slice against the slice constraints. It makes no styling or device-specific visual change. 002's deferred inspector handling is intact. Recovery only applies to the retirement it was started for, so a late callback can't affect a newer host. Re-verified independently on the same Duo simulator (list style, inner landscape-left), with a log stream filtered for presentation messages:

- Path A three times, then B and C. All passed.
- Zero "Attempt to present" or "presentation in progress" conflict messages.
- After the fold cycles, the toolbar filter menu opened normally. With the 002 fix alone, sim-use could not open a toolbar menu after fold cycles. That matches the presentation conflict this slice removes, but that state was not retested specifically to confirm it.
