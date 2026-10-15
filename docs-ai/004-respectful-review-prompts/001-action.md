# 004 — Respectful review prompts: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-11 | Add the eligibility controller and system review host | `cad7b84` |
| 2026-09-27 | Limit global prompts to one window | `f114e82` |

## Outcome and current state (as of 2026-10-07)

The controller owns local engagement state and resets the cycle immediately
before a system request attempt. The app host uses the two-second delay and
rechecks eligibility. Multi-window follow-up prevents several scenes from trying
to present the same global prompt.

Key source files:

- `MyAnimeList/Sources/Utils/AppReviewPromptController.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- `MyAnimeList/Tests/MyAnimeListTests/AppReviewPromptControllerTests.swift`

## Deviations from plan

This record was reconstructed later; no pre-implementation spec was requested
for the original change. The original discussion excluded OpenSpec artifacts.

## Open questions

System presentation remains outside the app's control. Static source inspection
cannot establish when StoreKit actually displays its prompt.
