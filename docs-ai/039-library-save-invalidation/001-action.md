# 039 — Library membership changes drive save refreshes: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-31 | Recorded the maintainer's save-classification strategy before implementation. | [Plan](000-plan.md) |
| 2026-10-31 | Classified save identifiers, removed the inspector's global revision dependency and settling machinery, and retained session cancellation. | Source paths below; committed with the review follow-ups |
| 2026-10-31 | Profiled actual changed responses in the open inspector, including first-visit movie runtime changes. Removed temporary timing instrumentation afterward. | Measurements below |
| 2026-10-31 | Review follow-ups: kept saves flowing after a backup restore replaces the container, rebuilt row snapshots after background writes such as Refresh All, and made each detail model track what it last applied. | [Review follow-ups](#review-follow-ups-2026-10-31) |

## Outcome and current state (2026-10-31)

`LibraryStore` retains the visible candidates' persistent identifiers and domain
identities after each membership fetch. Save notifications now preserve their
inserted, updated, and deleted identifiers through deferred write scopes.

| Save input | Membership action |
| --- | --- |
| Inserted/deleted `AnimeEntry`, or invalidated-all notification | Refetch and bump `libraryRevision`. |
| Updated entry visibility or domain identity differs from the baseline | Refetch and bump the revision. Hidden entries are resolved too, so becoming visible is detected. |
| Existing duplicate group's child count, detail presence, saved date, or name changes | Refetch and resolve the preferred entry again. These match `AnimeEntryDuplicateResolver` inputs. |
| Ordinary singleton entry content, detail, cast, staff, seasons, or progress change | Keep membership. Observation still invalidates display inputs that actually changed. |
| Save from a context other than the container's main context (`LibraryMetadataRefreshWriter`) | Classify membership as above, and bump `backgroundWriteRevision` so every display cache rebuilds its row snapshots. |
| Notification from a container other than the provider's current one | Ignore. The comparison runs on the main actor against `dataProvider.sharedModelContainer`, so a backup restore that replaces the container keeps later saves flowing. |

Updated entry IDs are fetched individually through a fresh read context so a
background visibility save is not classified using an older UI object. Normal
child-only saves do not create this context or fetch entries. While duplicates
exist, entry/detail notifications also check duplicate ranking inputs, including
inverse-relationship effects. The baseline includes all visible duplicate
candidates, not just their current winner.

The inspector observes the selected entry's `ObjectIdentifier`. Replacing the
entry behind an identity resynchronizes the session; mutating that same object
or changing `libraryRevision` does not restart its task. Hidden inspector content
remains gated. The 120 ms debounce, selection hook/revision, `acceptsLoading`, and
`loadingRevision` were removed. A presented session owns its load tasks and
cancels them when replaced or cleared; view-task cancellation also propagates.
The detail model retains its request-generation and cancellation checks before
persisting a response. Cancellation cannot preempt synchronous work already on
the main actor.

The unchanged-response comparator avoids rewriting identical detail graphs. A
detail model skips reapplying display cards only when the response matches the
content that model itself last applied, not merely the shared stored detail. The earlier native List row
extraction remains. See [021.002](../021-mac-selection-model/002-hidden-inspector-work.md)
for the first hidden-inspector investigation.

Key implementation paths:

- `MyAnimeList/Sources/ViewModels/Library/LibraryMembershipSnapshot.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`
- `MyAnimeList/Sources/Utils/ModelContextSaveObserver.swift`
- `MyAnimeList/Sources/Mac/MacLibraryInspector.swift`
- `MyAnimeList/Sources/Mac/MacLibraryList.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`
- `MyAnimeList/Sources/ViewModels/Library/EntryDetailViewModels.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore+Entries.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`

### Sync and import boundaries

`LibrarySyncCoordinator+RemoteApply.swift` applies snapshots/tombstones through
the store's UI repository, saves, rebuilds sync tracking, and explicitly calls
`refreshLibrary()`. `LibrarySyncCoordinator+Pipeline.swift` also retains its
post-import refresh boundary. Backup restore in
`LibraryProfileSettingsActions.swift` explicitly refreshes after restoring and
rebuilding sync state. These deliberate import/reconstruction refreshes remain;
they do not depend on the save observer deciding that a child model is an entry.
The existing sync coordinator suite exercises remote application and passed.

An exploratory test wrote only a detail's runtime in a detached context and
expected the row to change after an explicit full library fetch. It did not. The
cause, established later (see the review follow-ups), is the display cache rather
than the models: the main context merges the background values into its
registered objects, but without observation. (Corrected 2026-10-31: this
paragraph first concluded that the UI child itself remained stale.)

### Separately reviewable staff-jobs repair

The staff graph correction is confined to two DataProvider paths and does not
depend on the app save classifier or unchanged-response guard:

- `DataProvider/Sources/DataProvider/Models/V2/AnimeEntryDetailBridgeV2_8_5.swift`
- `DataProvider/Tests/DataProviderTests/DataProviderTests.swift`

`replaceStaff` explicitly inserts replacement staff and their jobs, establishes
the job inverses, then attaches the new staff to the existing detail. Earlier
runtime diagnostics found stored replacement staff with zero jobs versus one
job in the fetched DTO, causing repeated changed responses. The existing package
regression now starts with a persisted detail, replaces it, saves, and verifies
job credits through a fresh context. This changes graph writing, not the schema
shape. These two paths were committed on their own as
`fix: Keep staff jobs when replacing a stored detail`.

## Profile

Native Debug app, macOS 27.2 (26B123), deterministic 800-entry in-memory fixture,
List view, inspector open. Temporary `ContinuousClock` spans logged synchronous
membership fetching, display projection cache misses, persistence (including
comparison and graph replacement), card preparation, session construction, and
view-value construction. An event immediately before graph replacement verified
that these were changed responses, not unchanged-response fast paths. All probes
were removed from the final source.

The labeled final pass used one library window showing all 800 entries. The
first restored movie load and a later Down-arrow selection of the previously
unloaded `学園剣学園` both introduced runtime metadata. Accessibility confirmed
the latter row changed from “Movie” to “127 min” and the inspector showed 127 min.

| Synchronous work | Restored movie | Down-arrow first movie visit |
| --- | ---: | ---: |
| Save-triggered `refreshLibrary()` | 0 calls / 0 ms | 0 calls / 0 ms |
| Display projection, 800 rows | 174.36 ms | 176.77 ms |
| Detail persistence | 12.30 ms | 10.27 ms |
| Detail-card preparation after persistence | 2.56 ms | 1.96 ms |
| Selected session construction | 0.72 ms | 0.29 ms |
| `EntryDetailView.body` evaluations around the load | 0.18–0.79 ms each | 0.17–0.78 ms each |
| Mac inspector content construction | 0.15–0.30 ms each | 0.14–0.24 ms each |

In the same final pass, the preceding series response really changed and saved:
9.90 ms persistence, 2.32 ms card preparation, and **no display projection**.
Its new inspector-only metadata did not touch row inputs. A prior 30-second
`sample` capture while navigating the open inspector likewise contained no
`refreshLibrary` or `LibraryBrowseScope.display` stacks for inspector-only
changed responses. Persistence and SwiftUI/AppKit work remained. The sampled
run's persistence/card spans were higher (28–54 / 8–23 ms); sampling and
accessibility inspection add overhead, so they are not pooled with the final
unsampled spans.

An earlier two-window pass showed approximately 35 ms for a 204-movie projection
and 171–175 ms for the 800-entry projection after a runtime change. The final
labeled one-window pass removes ambiguity about projection size. This cache is
per-window, not per-row: a row-visible mutation can still rebuild every snapshot
in each scope. Keeping that Observation behavior is required for correctness;
this change removes the additional blanket membership invalidation.

These are scoped elapsed measurements in a Debug fixture, not hardware
key-to-highlight latency, Release benchmarks, real-library acceptance, or total
SwiftUI layout/render time. View-construction spans exclude subsequent child
body evaluation, native control creation, layout, drawing, and accessibility work.
Do not add nested or repeated spans as an end-to-end frame time.

The largest measured remaining block is the 800-row display projection, not
card preparation. Background persistence could remove the measured 10–12 ms
save block but would not remove the 174–177 ms main-actor display projection.
Off-main detail-card preparation targets only about 2 ms in these movie cases.
No background persistence, off-main preparation, or display-cache redesign was
implemented.

## Validation

- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibrarySaveInvalidationTests MyAnimeListTests/LibrarySyncCoordinatorTests MyAnimeListTests/LibraryMetadataRefreshTests MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/EntryDetailViewModelTests MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/MacLibrarySelectionTests'`
  passed after removing probes: xcresult reports 190 tests, 208 expanded runs,
  zero failures/skips. New coverage checks child-only saves across two scopes,
  runtime/progress row updates, singleton entry changes, duplicate winner inputs,
  background visibility and child saves, foreign-container isolation, first detail
  insertion, and the explicit import boundary. Existing session replacement tests
  cover actually replaced entry objects; new tests cover obsolete responses and
  view-task cancellation.
- `make test-dataprovider DATAPROVIDER_TEST_FILTER='replaceDetailPersistsAggregateStaffJobs|entryDetailApplyPreservesDTOChildOrder|applyingDetailReplacesAndDeletesOldProductionCompanies'`
  passed all 3 package tests.
- `make build-mac` passed with all temporary probes removed.
- `make build` passed for iOS with probes removed.
- The clean-source native fixture process relaunched successfully. Computer Use
  then returned `cgWindowNotFound`, so its final visual recheck could not run.
  The successful open-inspector navigation and row-runtime checks above used the
  instrumented build of this implementation. Removing probes changed no product
  behavior; the final cancellation wrapper cleanup only inlined the same calls.
- Earlier checks: the first focused save/session run passed. A broader run failed
  only the exploratory background-child merge assertion discussed above. The
  initial target-membership compilation failure was corrected before those runs.
- No iOS simulator was booted and no physical-device tests ran.

## Deviations and open questions

The exploratory background-child merge assertion was replaced for the reason
above. The first new-test build also exposed missing synchronized-target
exceptions; `MyAnimeList.xcodeproj/project.pbxproj` now excludes the new test file
from the app and includes it in the test target. No other design deviation.

Open risk: main-context edits to child models that rows display, such as
`EntryDetailSession.refreshEpisodeCountsIfEligible` changing season episode
counts, now depend on observation alone. Before this entry their save also
refetched the library; see the review follow-ups for why that refetch only
invalidated rows by accident. Detail properties on the same object are covered
by `rowVisibleDetailAndProgressChangesUpdateWithoutMembershipRefresh`; season
summaries handed out as new instances ([023.002](../023-library-display-cache/002-child-model-edits.md))
were not tested.

Rapid physical-key repeat and full rendered-frame timing remain unmeasured.
Further performance work should distinguish per-window display projection from
framework layout and rendering; these measurements do not justify moving live
SwiftData objects across actors.

## Review follow-ups (2026-10-31)

Two Codex reviews of the uncommitted change and a Claude Code investigation found
three defects, fixed before the first commit.

**Backup restore stopped membership updates.** `ModelContextSaveObserver` held
the container it was created with. `BackupManager.restoreBackup()` calls
`DataProvider.reloadDataStore()`, which replaces `sharedModelContainer`, so the
filter rejected every later save until relaunch. The observer now records the
saving context's container and context identifiers; `LibraryStore` compares
them with the provider's current container and main context on the main actor
(`DataProvider` is main-actor isolated). Rejected: re-registering the observer
after a restore, which every future container swap would also have to remember.
`savesAfterReplacingTheContainerStillRefreshMembership` failed with the original
filter (no revision bump, empty library) and passes with the fix.

**Refresh All left rows stale.** A temporary test wrote through the real
`LibraryMetadataRefreshWriter` and, separately, through a detached context. In
both, the main context merged the new values into the registered UI objects
(the entry read the new name and runtime, and a main-context fetch returned the
same object), but no display cache recomputed: merged values bypass the models'
observation. On the previous commit, `refreshLibrary()` rebuilt rows only
incidentally. With 50 entries the rebuilt `library` array differed and the cache
recomputed; with one entry it did not, and that row stayed stale too. The
inference, not directly verified, is that `Dictionary(grouping:)` iteration
order changed the array. The maintainer confirmed on a simulator build from
before this entry that Refresh All updates rows in a real library.

Saves from any context other than the current container's main context now bump
the observable `LibraryStore.backgroundWriteRevision`, which each display cache
reads. The cache also reads `libraryRevision`: explicit import and restore
refreshes write replay values that observation can miss, and a same-order
`library` array would not invalidate the cache. Since this entry the revision
moves only for membership changes and those explicit refreshes. Deferred scopes record whether any of their saves were background writes.
Only `LibraryMetadataRefreshWriter` creates such contexts (Refresh All and
missing-parent repair), so inspector detail saves, which use the main context,
still skip the rebuild. `backgroundDetailSaveUpdatesRowsWithoutMembershipRefresh`
replaces the earlier test that only checked the revision; it uses one entry, so
it cannot pass by reordering.

**A second detail model could keep showing old detail.** The unchanged-response
shortcut skipped `apply` when the shared stored detail already matched and the
model had prepared the same request. If another model, such as a second window's
inspector, saved the same response first, this model kept its old title and no
logo. `EntryDetailViewModel` now stores the `LibraryMetadataRefreshDetailComparator.Content`
it last applied and reapplies when the fetched content differs. Persistence
still skips unchanged graphs. `testSecondModelAppliesResponseAnotherModelAlreadySaved`
covers two models.

Key paths: `MyAnimeList/Sources/Utils/ModelContextSaveObserver.swift`,
`MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`,
`MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`,
`MyAnimeList/Sources/ViewModels/Library/EntryDetailViewModels.swift`, and
`MyAnimeList/Sources/ViewModels/Library/LibraryMetadataRefreshDetailComparator.swift`.

Validation:

- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibrarySaveInvalidationTests MyAnimeListTests/EntryDetailViewModelTests MyAnimeListTests/EntryDetailSessionTests MyAnimeListTests/LibraryMetadataRefreshTests MyAnimeListTests/LibrarySyncCoordinatorTests MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/MacLibrarySelectionTests'`
  passed, 183 tests. An earlier run of the same command hung in
  `disablingStalledPreparationReleasesBootstrapWithoutCallback`, a CloudKit
  cancellation test that touches no save or display code; it passed in 0.009 s
  on the rerun, so the hang is recorded as unexplained flakiness.
- `make test-dataprovider DATAPROVIDER_TEST_FILTER='replaceDetailPersistsAggregateStaffJobs|entryDetailApplyPreservesDTOChildOrder|applyingDetailReplacesAndDeletesOldProductionCompanies'`
  passed 3 tests, and `make build` passed for iOS.
- The temporary background-write probes were removed. A row update after
  Refresh All in the running app was not rechecked with this build.
