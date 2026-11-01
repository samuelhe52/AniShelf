# 040 — Per-entry library display updates: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-31 |
| Origin | Maintainer asked to replace per-window display rebuilds with per-entry updates after [039](../039-library-save-invalidation/000-plan.md) measured the remaining open-inspector cost. |
| Related | [023 display cache](../023-library-display-cache/000-plan.md), [023.002 child-model edits](../023-library-display-cache/002-child-model-edits.md), [039 save invalidation](../039-library-save-invalidation/000-plan.md) |

## Background

`LibraryBrowseScope.display` computes a window's whole display list inside one
`withObservationTracking` call: filter, sort, and one `LibraryEntrySnapshot` per
shown entry. Any tracked read that changes discards everything. After 039, the
common trigger in the Mac inspector is a first visit that saves row-visible
metadata, such as a movie's runtime. 039 measured about 175 ms of main-actor
work per such rebuild with 800 entries.

A temporary timing test on 2026-10-31 (Debug, macOS, in-memory store, 800
entries with details, default scope, four rounds, consistent within 2 ms) split
that cost:

| Work | Time |
| --- | ---: |
| `filterAndSort` over the library | ~101 ms |
| Building 800 `LibraryEntrySnapshot`s | ~52 ms |
| Reading 800 `libraryIdentity` values | ~2.7 ms |
| Whole rebuild after one movie's runtime changed | ~173 ms |

Edits to a series' runtime, which no row reads, caused no rebuild, so tracking
is already precise; the cost is what a rebuild redoes. Sorting dominates: its
comparator reads SwiftData-backed properties on every comparison (about 8,000
comparisons, several keys each) and builds an array of closures each time.
Per-entry snapshot caching alone would remove less than a third of the cost.

## Goals

- A change to one entry rebuilds only that entry's derived display values.
- A change that does not affect filtering or ordering keeps the order without
  re-sorting.
- A change that does affect them reorders from cached keys, without reading
  SwiftData properties for the other entries.
- Full rebuilds (filter, sort, group, category, membership, explicit refresh
  revisions) read each entry's properties once instead of per comparison.
- Keep 023's contract: unsaved edits invalidate like saves, invalidation happens
  in the input's `willSet`, and the rebuild runs on the next read in the
  mutating caller's transaction, so it keeps its animation.
- Keep 023.002's `trackingUpdatedAt` read for child-model edits and 039's
  `libraryRevision`/`backgroundWriteRevision` reads.

### Non-goals

- Moving display work off the main actor; SwiftData models stay main-actor.
- Sharing row snapshots across windows. Snapshots do not depend on the scope,
  so a store-owned row cache is possible later; this entry keeps per-scope
  caches to limit the change.
- SwiftUI List diffing, layout, or rendering costs.

## Design / approach

Split the per-window computation into three tiers inside
`MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`, keyed by the
entry's `PersistentIdentifier`:

1. **Row tier.** For each shown entry, a cached `LibraryEntryDisplayItem`
   built in its own `withObservationTracking` (snapshot reads plus
   `trackingUpdatedAt`). Its `onChange` marks only that entry's row stale.
2. **Order tier.** For each library entry, a cached value key for the current
   definition: whether it passes the category and filters, its group rank, its
   primary sort value, `dateSaved`, and `tmdbID`, built in its own tracking
   call. Its `onChange` marks only that entry's key stale. Sorting compares
   these plain values (`alphabetical` keeps `localizedStandardCompare` on the
   cached string).
3. **List tier.** Tracks the inputs shared by all entries: `store.library`,
   filters, category, sort, group, reversal, `hideDroppedByDefault`, and 039's
   two revisions. Its `onChange` discards every key; the revisions also discard
   every row, because their writes bypass observation.

Every `onChange` clears the assembled `LibraryDisplayCache` and bumps
`displayGeneration`, as today. The next read rebuilds stale rows and keys,
re-sorts only when a recomputed key differs from its previous value (or the
list tier was discarded), and assembles the cache from the order and rows. The
assembly stays O(n) over cached values.

A build counter for row snapshots (`rowBuildCount`) sits next to
`displayComputeCount`, so tests can assert how many rows a change rebuilt.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Cache sort keys as values | Sorting is about 60% of a rebuild. Caching only snapshots was the first idea; the timing split showed it would leave most of the cost. |
| Per-entry observation tracking | Keeps 023's Observation-based invalidation, including unsaved edits, rather than diffing save notifications, which miss unsaved edits and child-model instances. |
| Re-sort cached keys instead of moving one entry | A sort over 800 cached values is expected to cost little. A binary-search move is a later option if measurements say otherwise. |
| Keep caches per window | Smaller change; a shared store-owned row cache is noted as a follow-up. |

## Validation and acceptance criteria

- Focused tests in `MyAnimeList/Tests/MyAnimeListTests/LibrarySortingAndDeletionTests.swift`
  and `LibrarySaveInvalidationTests.swift`: a row-only change rebuilds one
  snapshot and keeps the order; a sort-key change reorders; a filter-relevant
  change hides or shows the entry; unsaved favorite toggles and
  `trackingUpdatedAt`-only edits still update; background writes and explicit
  refreshes still rebuild rows.
- Existing display-cache, sorting, grouping, category, and save-invalidation
  tests pass unchanged.
- Repeat the timing test: a row-only change should drop from ~173 ms to a few
  milliseconds, and a full rebuild should be well under 100 ms. Report Debug
  numbers and their limits.
- `make build-mac` and `make build`. Visual and interactive checks of Mac
  arrow-key navigation with the inspector open are for the maintainer.

## Amendments

- Updated 2026-10-31: Implementation replaced the row and order tiers with one registration per entry, because Observation registrations cannot be cancelled and a refetch can swap child-model instances — see [001-action.md](001-action.md#deviations-from-plan).
