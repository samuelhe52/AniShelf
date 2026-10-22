# 023 — Store-owned library display cache: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-17 |
| Origin | Maintainer request (2026-10-17) after reviewing the multi-selection snapshot from [014](../014-multiselect-invariants/000-plan.md); the view-held copy of store state did not feel like the right layer |
| Related | [014-multiselect-invariants](../014-multiselect-invariants/000-plan.md), [022-mac-library-root-split](../022-mac-library-root-split/000-plan.md) |

## Background

`LibraryStore.libraryDisplayItems` is a computed property. Each read filters,
sorts, and builds a `LibraryEntrySnapshot` for every entry in the library. Entry
[014](../014-multiselect-invariants/000-plan.md) kept selection toggles cheap on iOS
by copying the result into `LibraryView` state (`selectionDisplayItems`,
`selectionLayoutIDs`, `selectionEntriesByID`) while multi-selecting. A view
modifier listed the store inputs that refresh that copy.

That arrangement has three problems:

- It only covers iOS multi-selection. Normal browsing, the iOS gallery (three
  reads per body), and the Mac roots still recompute on every body evaluation.
- The dependency list lives in a view modifier (`LibraryWindowBehaviors`), away
  from the inputs it mirrors, and it has to be kept in sync by hand.
- The copy looks redundant at the call site. Refactors have removed it twice
  (see 014).

## Goals

- Compute the display list once per change to its inputs, for every reader, on
  both platforms.
- Keep the observable behavior of the computed property: rows reflect entry
  mutations immediately, including mutations not yet saved (favorite toggles,
  batch actions, open detail edits).
- Remove the view-held snapshot from `LibraryView`.
- Keep the existing category-switch animation, which every iOS setter already
  wraps in `withAnimation(.snappy)`.

### Non-goals

- The list-row `GestureMask` from 014 is unrelated and stays as is.
- No change to filtering or sorting rules.

## Design / approach

1. **Memoize in the store.** `LibraryStore` keeps an `@ObservationIgnored`
   cache holding the display items, their IDs, and an identity→entry
   dictionary. The getter computes the cache inside `withObservationTracking`.
   The tracking's `onChange` clears the cache and bumps an observed
   `libraryDisplayGeneration`, which every getter reads so views re-render.
   The tracked dependencies are exactly what the computation reads: `library`,
   the filter, sort, group, category, and preference properties, and every
   `AnimeEntry` property that filtering, sorting, or snapshot construction
   touches. No hand-maintained input list.
2. **Readers.** `libraryDisplayItems`, `libraryDisplayIDs`,
   `libraryOnDisplay`, and `displayedEntry(for:)` read the cache. Existing call
   sites keep their names.
3. **iOS root.** `LibraryView` renders `store.libraryDisplayItems` directly.
   Batch actions and the toolbar resolve selected entries through
   `store.displayedEntry(for:)`. The three snapshot `@State` properties and
   `refreshSelectionDisplayItemsIfNeeded()` are deleted.
4. **Selection pruning.** Each root prunes its selection against the IDs it
   actually renders, and `LibraryWindowBehaviors` drops its seven per-input
   observers and the `scopeDidChange` hook. The iOS root observes
   `store.libraryDisplayIDs`. The Mac root observes its Find-narrowed
   `visibleDisplayItems` IDs, because Find matches entry content: an edit can
   hide an entry from one window without changing the store's IDs. (Corrected
   during implementation; see the action record's deviations.)
5. **Animation.** Because the getter recomputes on first read after the
   mutation, the new list renders in the transaction of whoever mutated the
   input. Category switches keep `.snappy` from their call sites, and
   `LibraryEntryPage`'s `.animation(.default, value: layoutIDs)` is unchanged.
   The old `withAnimation(.snappy)` around the snapshot refresh existed only
   because the snapshot updated a frame late; it goes away.

Key files: `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`,
`MyAnimeList/Sources/Views/Library/LibraryView.swift`,
`MyAnimeList/Sources/Views/Library/LibraryView+MultiSelection.swift`,
`MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`,
`MyAnimeList/Sources/Views/Library/LibraryWindowBehaviors.swift`.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Cache in the store, not the view | A view-held copy covers one root and one mode, and refactors remove it. A store cache serves every reader and is the only source, so it cannot be dropped as redundant. |
| Invalidate through `withObservationTracking` | An eager `didSet` on each input was the first proposal. It misses mutations to the entries themselves: favorite toggles (`DataHandler.toggleFavorite`) and `LibraryBatchAction` change models without saving, so `libraryRevision` only moves at autosave. Rows would show stale state until then. Observation tracking sees those mutations because the computation reads them. |
| Lazy recompute on read | `onChange` fires in the input's `willSet`, before the new value is stored, so recomputing there would read the old value. Clearing the cache and recomputing on the next read avoids that, and coalesces several input changes into one recompute. |
| Keep `withAnimation` at the call sites | The maintainer finds `withAnimation` more stable than `.animation(_:value:)` for these transitions. The store mutation happens inside the caller's transaction, so no extra animation plumbing is needed. Must be confirmed visually. |

## Risks

- **Read between invalidation and store.** If something reads the display list
  synchronously after `onChange` fires but before the input's new value is
  stored, it would cache the old value and miss the change. SwiftUI's observers
  only mark views dirty, so no known reader does this. The getter refuses to
  cache while the store's own invalidation callback is running.
- **Tracking scope.** Nested `withObservationTracking` merges the entry reads
  into the outer body's tracking on the render that recomputes. That render
  depends on the same values the computed property already exposed, so it is no
  broader than today.

## Validation and acceptance criteria

- Build: `make build` and `make build-mac`.
- Tests: extend `LibrarySortingAndDeletionTests` so an unsaved favorite toggle
  under the favorites filter changes `libraryOnDisplay`. The existing filter,
  hide-dropped, and category tests already read after each input change, so
  they cover stale-cache regressions on those inputs. Run
  `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryEntryInteractionStateTests'`
  if a simulator is already booted.
- Visual (maintainer, `make run-sim` and `make run-mac`):
  - Selection toggles in list and grid stay responsive on a large library.
  - Switching categories while selecting animates as before, and the selection
    keeps only still-visible entries.
  - Favorite toggles from row menus update the row at once.
  - Batch actions update rows and exit selection as before.

## Amendments

- Updated 2026-10-18: child-model edits such as episode progress missed observation; the tracking also reads `entry.trackingUpdatedAt` — see [002-child-model-edits.md](002-child-model-edits.md)
