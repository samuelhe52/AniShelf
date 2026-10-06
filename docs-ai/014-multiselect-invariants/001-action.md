# 014 — Library multi-selection rendering invariants: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-15 | Add multi-selection in list and grid views | `789ae36` |
| 2026-06-20 | Snapshot display items during multi-selection; restore native list selection | `2893549`, `94edc90` |
| 2026-07-14 | Row taps become simultaneous gestures for inspector focus (later found to block edit-mode row selection) | `75e8354` |
| 2026-07-25 | Library state refactor drops the selection snapshot | `d2a18bd` |
| 2026-07-25 | Restore the snapshot; gate row taps with `GestureMask` | `f2a3c36`, `72fef47` |

## Outcome and current state (as of 2026-10-07)

`LibraryView` holds `selectionDisplayItems` and `selectionEntriesByID`.
`refreshSelectionDisplayItemsIfNeeded()` runs on `libraryRevision`, filter, grouping,
sort, sort-direction, and hide-dropped changes. `AnimeEntryListRow` applies
`tapGestureMask` to its tap gestures.

Key source files:

- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView+MultiSelection.swift`
- `MyAnimeList/Sources/Views/Library/LibraryListView.swift`
- `MyAnimeList/Sources/Views/Gadgets/AnimeEntryListRow.swift`

## Deviations from plan

The snapshot regressed once (`d2a18bd`), and simultaneous gestures broke edit-mode
row selection (`75e8354`, released in `v1.96`). The regression and both fixes
first shipped together in `v1.96.2-hotfix`.

## Open questions

No automated test protects either invariant; protection relies on this record and review.
