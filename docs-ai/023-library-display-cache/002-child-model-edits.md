# 023.002 — Child-model edits missed the display cache

## Context

On 2026-10-18 the maintainer reported that episode progress edits made in the detail
inspector (Mac and iPad) did not update the progress badge in the library list beside
it. Score and watch status edits updated it at once. The badge caught up after a
variable delay: sometimes immediately, sometimes one or two seconds later, sometimes
only after closing the detail and waiting.

The display cache now lives per window in `LibraryBrowseScope`
([028](../028-window-state-ownership/000-plan.md)). It is still built inside
`withObservationTracking`, as this entry describes.

## Investigation

- A temporary unit test edited progress on unsaved season and series entries, including
  entries reloaded from an on-disk store. The cache invalidated every time, so the
  computation does read the progress values.
- The library fixture had no seasons, so it could not show progress at all. It now seeds
  seasons for every series and progress for watching series (see Refs).
- Temporary logging in the running Mac fixture app showed:
  - A progress edit (`setProgress`) fired no `onChange`. The first invalidation came
    about 3 s later, consistent with autosave, and the rebuild then showed the new value.
  - The `AnimeEntry` instance kept the same `ObjectIdentifier` throughout, but the
    `AnimeEntryEpisodeProgress` instances in `entry.episodeProgresses` had new
    identifiers at each rebuild and at each later edit, with no save in between.

Conclusion: the tracking registered on progress instances that SwiftData later
discarded. The inspector then mutated new instances whose observation registrars
nobody watched. `store.library` keeps entries alive, so entry properties are observed
reliably.

Unverified: exactly why SwiftData re-creates these instances. A test that read and
mutated inside separate `autoreleasepool`s still passed, so the churn was reproduced
only in the running app.

## Change

The tracking closure in `LibraryBrowseScope.display` now reads
`entry.trackingUpdatedAt` for every displayed entry. User tracking edits
(`updateEpisodeProgress`, `updateRewatchCount`, and the other `update…` helpers) end
with `markTrackingModified`, which stamps that clock on the entry. Every tracked edit
therefore invalidates the cache through the entry, even when the child-model write
goes unobserved.

Rejected or not taken:

- Holding the child models in `LibraryEntryDisplayItem` to keep their instances alive.
  This relies on SwiftData returning the same instance while one is alive, which is
  undocumented.
- Adding `trackingUpdatedAt` to `LibraryEntrySnapshot`. Rows never display it; a bare
  read in the tracking closure states the intent more directly.

Replay-style writes (`applyEpisodeProgressSnapshot` during sync import or restore) do
not stamp the clock. Those flows save and refresh `store.library`, which invalidates
the cache through the store. Detail-only changes on child models, such as
`EntryDetailSession.refreshEpisodeCountsIfEligible`, also save immediately.

## Refs

- `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`: the read and its comment.
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySortingAndDeletionTests.swift`:
  `testLibraryOnDisplayRespectsFiltersAndHiddenDroppedState` now checks that
  `markTrackingModified()` alone recomputes the list. Without the fix it failed
  (`displayComputeCount` unchanged); with it,
  `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryEntryInteractionStateTests'`
  passed.
- `MyAnimeList/Sources/App/LibraryFixture.swift`: series get one to three seasons with
  12 or 24 episodes, and watching series get progress. The values derive from the entry
  index rather than the generator, so the other fixture values are unchanged. Rows now
  draw progress badges, so benchmark results from before this change are not directly
  comparable ([026](../026-library-performance-benchmarks/000-plan.md)).
- `make build-mac` succeeded. The maintainer's visual check of the fixed build is pending.
