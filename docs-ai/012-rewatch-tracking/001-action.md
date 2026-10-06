# 012 — Rewatch tracking and clocked progress resets: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-03 | Add rewatch schema, controls, sync, and exports | `b3cd028` |
| 2026-10-03 | Retain clocked zero progress resets | `d79926b` |
| 2026-10-03 | Refine controls, count chip, and compact badges | `4f7fd12`, `41b9b5a`, `a99b2cf` |

## Outcome and current state (as of 2026-10-07)

`CurrentSchema` is `SchemaV2_8_2`. Rewatch marker/count live in the versioned
model and `UserEntryInfo`; progress resets retain timestamped zero rows through
the sync snapshot. Visible progress semantics exclude zero-only summaries.
The existing regression covers reset winning over stale progress in both directions.

Key source files:

- `DataProvider/Sources/DataProvider/Models/V2/SchemaV2_8_2.swift`
- `DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift`
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`
- `DataProvider/Tests/LibrarySyncTests/LibraryEntrySyncTests.swift`

## Deviations from plan

The old correctness plan deferred D5; this later change implements its explicit
zero semantics. Editable count replaced more elaborate unknown-count/Undo ideas.

## Open questions

Older clients may omit or ignore reset markers and newer fields. No production
CloudKit deployment or mixed-version live round trip has been recorded.
The prior discussion explicitly declined a special workaround for one old-build pattern.
