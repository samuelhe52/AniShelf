# 023 — Store-owned library display cache: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-17 | Plan written; store cache, root-owned selection pruning, and tests implemented on `feat/native-macos` | `80300c5` |

## Outcome and current state (as of 2026-10-17)

`LibraryStore` memoizes the display list. The private `libraryDisplay` getter
builds a `LibraryDisplayCache` (items, IDs, and identity→entry lookup) inside
`withObservationTracking`. Its `onChange` calls `invalidateLibraryDisplay()`,
which clears the `@ObservationIgnored` cache and bumps the observed
`libraryDisplayGeneration`. `libraryDisplayItems`, `libraryDisplayIDs`,
`libraryOnDisplay`, and `displayedEntry(for:)` all read through it.

The iOS `LibraryView` no longer holds `selectionDisplayItems`,
`selectionLayoutIDs`, or `selectionEntriesByID`. It renders
`store.libraryDisplayItems` and passes `store.libraryDisplayIDs` as layout IDs.
Selected entries resolve through `store.displayedEntry(for:)` in both
`LibraryView+MultiSelection.swift` and `LibraryToolbar`. The renamed
`pruneSelection()` only intersects the selection with the shown IDs.

`LibraryWindowBehaviors` no longer observes store inputs or takes a
`scopeDidChange` hook. `LibraryView` prunes on `onChange(of: store.libraryDisplayIDs)`.
`MacLibraryView` prunes on `onChange` of the IDs it renders after Find, which
also replaces its separate `libraryFindQuery` observer.

Key source files:

- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntrySnapshot.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView+MultiSelection.swift`
- `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`
- `MyAnimeList/Sources/Views/Library/LibraryWindowBehaviors.swift`

## Deviations from plan

`LibraryDisplayCache` lives in `LibraryEntrySnapshot.swift` next to
`LibraryEntryDisplayItem` rather than in the store file.

The first cut kept a shared `scopeDidChange` hook driven by
`store.libraryDisplayIDs`. Code review caught a Mac regression: with Find
active, a saved edit to notes or metadata can stop an entry matching without
changing the store's IDs. The removed `libraryRevision` observer had pruned
that case, so the hidden entry stayed selected and the inspector and
single-entry commands still targeted it. Pruning moved into each root, against
the IDs that root renders. This also prunes after unsaved edits that change a
Find match, which the old hook missed.

## Validation

- `make build`: succeeded.
- `make build-mac`: succeeded.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryEntryInteractionStateTests'`
  on the already-booted iPad Pro 13-inch (M5) simulator, iOS 27.0: both suites
  passed. `LibrarySortingAndDeletionTests` now also checks that an unsaved
  favorite toggle under the favorites filter changes `libraryOnDisplay` both ways.
  `LibraryEntryInteractionStateTests.selectionTogglesReuseTheCachedDisplayList`
  reads the store's `libraryDisplayComputeCount` to check that entering,
  toggling, and exiting multi-selection never recompute the list, and that one
  input change followed by two reads recomputes exactly once. Re-run with the
  same command after adding it: both suites passed.
- `make lint`: no warnings on changed lines. Pre-existing warnings remain in
  these and other files.
- After the pruning fix: `make build`, `make build-mac`, and the same two test
  suites again, all passing. No test covers Mac Find pruning.
- Visual pass: the maintainer reported on 2026-10-17 that they had completed the
  plan's visual checks on the simulator and Mac builds, including the Mac Find
  pruning scenario. The agent did not observe it and has no per-check detail.
- Not run: any selection-latency measurement on a large library.

## Open questions

- The getter assumes nothing reads the display list synchronously between an
  input's `willSet` and its store, apart from the store's own invalidation
  callback, which the getter guards. No such reader is known; this is inferred
  from how SwiftUI observers behave, not tested.
