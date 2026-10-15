# 007 — Background sync suspension safety: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-25 | Protect library sync during backgrounding | `c53e994` |
| 2026-08-27 | Cancel when background-task acquisition fails | `2714a67` |

## Outcome and current state (as of 2026-10-07)

The controller owns one protected operation and cancels on expiration.
Coordinator request counts encompass work outside the sync gate. Remote apply
contains explicit cancellation boundaries and requires detached hydration.

Key source files:

- `MyAnimeList/Sources/App/LibrarySyncBackgroundExecutionController.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator+RemoteApply.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`

## Deviations from plan

This is a retrospective rationale record. It does not assign the historical
suspension lock to a specific save without evidence.

## Open questions

The historical crash report identified a termination class, not the exact save
holding the lock. The crash has not been reproduced.
