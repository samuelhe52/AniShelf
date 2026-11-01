# 040 — Per-entry library display updates: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-31 | Measured the rebuild split and wrote the plan. | [Plan](000-plan.md) |
| 2026-10-31 | Implemented per-entry display records with value-based ordering in a separate worktree from `d0cd873d`, moved onto `da484ada` after that commit was amended with a comparator fix for credit and episode order, and committed on `main` after two clean Codex reviews. | Source paths below |

## Outcome and current state (as of 2026-10-31)

`LibraryBrowseScope.display` assembles the window's list from per-entry records:

- **Entry record.** One `withObservationTracking` registration per library entry
  reads the row snapshot inputs, `trackingUpdatedAt`, the entry's
  `LibraryDisplayOrderInputs`, and the store's `libraryRevision` and
  `backgroundWriteRevision`. The record keeps the built `LibraryEntryDisplayItem`
  and order inputs. When the registration fires, only that record is rebuilt;
  the list is re-sorted only if its order inputs changed.
- **List registration.** One registration reads `store.library` and the window's
  filters, category, dropped-hiding, sort, reversal, and grouping. A change
  re-sorts from the cached inputs without reading entry properties.
- **Ordering.** `LibraryDisplayOrderInputs` holds every value any window's
  filters, category, grouping, or sort can use, so the registration's read set
  does not depend on the window's settings. `LibraryDisplayOrderDefinition`
  turns inputs into a `LibraryDisplayOrderKey` and compares keys without
  allocating. `filterAndSort` uses the same path, so the existing ordering tests
  cover it.

023's contract holds: unsaved edits invalidate through observation, the list is
cleared in the input's `willSet`, and the next read rebuilds in the caller's
transaction. A read during an invalidation returns an uncached list built from
current reads, as before. Changes reported while the list is being computed are
applied after the records are stored, so none is lost. `invalidateDisplay` bumps
the generation only when a cached list exists, so the 800 records firing together
on a revision bump produce one invalidation.

Key files:

- `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryDisplayOrder.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySortingAndDeletionTests.swift`
  (`testDisplayUpdatesRebuildOnlyTheChangedEntry`, and a row-build check in
  `testLibraryOnDisplayRespectsFiltersAndHiddenDroppedState`)

## Deviations from plan

The plan's separate row and order tiers, each with per-entry registrations that
a setting change would replace, were dropped during implementation:

- **Registrations cannot be cancelled.** Observation removes a registration only
  when it fires. Replacing 800 key registrations on every filter or sort change,
  or 800 row registrations on every revision bump, would leave the old ones
  attached to the models for the rest of the session. One registration per entry
  with a settings-independent read set avoids that; the plan's single-tier
  alternative was not considered until this surfaced.
- **Keeping registrations across a refetch missed edits.** An intermediate version
  kept a record's registration through a revision bump when its values were
  unchanged. After `refreshLibrary()`, editing an entry's runtime did not update
  its row: the refetch had handed out a new `AnimeEntryDetail` instance, and the
  registration observed the old one ([023.002](../023-library-display-cache/002-child-model-edits.md)
  describes the same SwiftData behavior). Reading both revisions in every
  record's registration makes a bump fire, and so remove, every registration,
  and each entry registers again on current instances. The refetch-then-edit
  case is now part of `testDisplayUpdatesRebuildOnlyTheChangedEntry`.
- Rows are built for every library entry, not only shown ones, because the shared
  registration needs the snapshot reads. Hidden entries add their snapshot cost
  to full rebuilds.

## Validation

Timing: a temporary test (removed) with 800 in-memory entries with details, run
in Debug on macOS against `main` (`d0cd873d`) in a temporary worktree and against
this branch. Each of four rounds edited a movie's runtime, toggled the sort
direction, and called `refreshLibrary()`, timing the next `displayItems` read.

| Read after | `main` | This branch |
| --- | ---: | ---: |
| Row-visible edit | 133–143 ms | 3.4–3.7 ms |
| Sort direction change | 136–142 ms | 10.4–10.9 ms |
| Revision bump after a refetch | 270–278 ms | 240–250 ms |

A separate breakdown on this branch (same fixture, values already loaded): row
snapshots and order inputs for 800 entries cost 82 ms without tracking, 92 ms
with one registration per entry, and 93 ms with one registration for the whole
list, so per-entry registration adds little. The revision case is dominated by
first reads after the refetch, in both versions. These are Debug in-memory
measurements of the read alone, not end-to-end frame times or a real library.

Tests and builds:

- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibrarySaveInvalidationTests MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/EntryDetailViewModelTests MyAnimeListTests/LibraryMetadataRefreshTests MyAnimeListTests/MacLibrarySelectionTests MyAnimeListTests/EntryDetailSessionTests'`
  passed, 100 tests, after the temporary timing test was removed. The first run
  of the new test failed only because the test environment's stored sort
  preference was reversed; the test now sets the direction inside
  `withRestoredLibrarySortingPreferences`.
- `make build-mac` and `make build` (iOS) passed.
- No app was launched; Mac arrow-key navigation with the inspector open and iOS
  runtime behavior were not checked.

## Open questions

- Edits made through a child-model instance that SwiftData hands out outside a
  revision bump, such as after a main-context fetch in the inspector's entry
  resolution, still rely on `trackingUpdatedAt` or a later bump. The previous
  design re-registered after every change and so recovered sooner.
- Revision bumps rebuild every record (about 240–250 ms here). Adding or deleting
  an entry bumps the revision; a membership change could instead rebuild only the
  inserted and removed records.
- `LibraryDisplayOrderInputs` costs about 27 ms for 800 entries, mostly from
  evaluating every filter and group rank into a set and dictionary per entry.
- Row snapshots could be shared across windows; each window still builds its own.
