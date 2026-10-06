# 005 — Adaptive library and detail ownership: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-14 | Introduce adaptive library | `0ecff8c` |
| 2026-07-15 | Restore genuine compact sheet hosting | `d188e10` |
| 2026-07-22 | Stabilize resize and simplify detail routing | `548c75e`, `511a41e` |
| 2026-07-24 | Archive completed OpenSpec change | `4746014` |

## Outcome and current state (as of 2026-10-07)

`LibraryView` owns the session store and stable sheet/inspector attachment.
`LibraryEntryDetailHostPolicy` selects an inspector only for regular horizontal
size class in every display mode; compact or unspecified traits keep the genuine
sheet and user's tap preference. Gallery fit remains a separate policy.
The source archived task list contains 47 checked tasks; canonical and archived
requirement files are preserved separately to avoid losing historical differences.

Key source files:

- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`
- `MyAnimeList/Sources/Models/Library/LibraryGalleryLayoutPolicy.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryEntryInteractionStateTests.swift`

## Deviations from plan

Early geometry/per-mode inspector eligibility is no longer the host contract.
The original design's optional condensed inspector was a fallback, not an
implemented product feature. Preserve those distinctions when reading old plans.

## Open questions

The old minimum-inspector-width and Gallery-neighbor tuning questions are
preserved in the original design and remain unresolved.
