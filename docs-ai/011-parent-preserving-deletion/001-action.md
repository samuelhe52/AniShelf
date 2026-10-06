# 011 — Parent-preserving library deletion: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-28 | Preserve series parents for surviving seasons | `c3b3a39` |

## Outcome and current state (as of 2026-10-07)

The repository branches selected entries into hide and delete operations.
It records deletion intent for the delete subset and restores deletion records
if the local transaction fails. This preserves season relationships while removing
the selected parent from the visible library.

Key source files:

- `MyAnimeList/Sources/ViewModels/Library/LibraryRepository.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySortingAndDeletionTests.swift`

## Deviations from plan

A parent can remain physically present after the user removes it from the
library. That is intentional relationship preservation, not incomplete deletion.

## Open questions

None.
