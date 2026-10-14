# 017 — CloudKit zone lifecycle and account error handling: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-14 | Implemented sections A–E of the plan, with the maintainer's added instruction to base **Upload This Library** on `LibraryStore.rebuildLibraryCloudSync()` and to make no live CloudKit writes. | `f2aa029` (section C), `9fe3a22` (section D), and the commit that adds this record (sections A, B, E) |
| 2026-10-14 | Added focused DataProvider and app tests, zh-Hans/ja strings, and a "Deleted" scenario in the iCloud Sync preview. Rendered the new card offscreen for a visual check. | Same commits |
| 2026-10-14 | Codex built-in review (`gpt-6-astra`, high effort) of the uncommitted tree reported no actionable regressions. | Codex thread `01a1366e-81d9-7582-8c8c-608570e5d9fa` |
| 2026-10-14 | The maintainer accepted the residual risk of the live-only open questions as low and marked them resolved. | Discussion |

## Outcome and current state (as of 2026-10-14)

**Transport (DataProvider).** `CloudLibrarySyncDatabase.ensureZoneAndSubscription`
now takes `recreatingUserDeletedZone`, and a protocol extension keeps the
two-argument form for callers that pass `false`. When the zone lookup returns
`.userDeletedZone` and recreation is not allowed, `CloudLibrarySyncLiveDatabase`
throws the new public `CloudLibrarySyncZoneDeletedByUserError`. When recreation is
allowed, it saves the zone through the existing path. `.zoneNotFound` and
`.unknownItem` still recreate the zone automatically.
`CloudLibrarySyncImporter.prepareRemoteSync(recreatingUserDeletedZone:)` forwards
the opt-in. `fetchChanges` treats `.zoneNotFound` with a stored token like
`.changeTokenExpired`: it clears the token, refetches from `nil`, and logs the
code. `CloudLibrarySyncImportBatch.isFullRefetch` is `true` for every fetch that
started without a token.

**Classification (app).** `Error.librarySyncBlockingCKError` unwraps
`CloudLibrarySyncExportFailure`, `LibrarySyncHydrationError`,
`CloudLibrarySyncPartialSaveFailure` (per-record and aggregate errors), and raw
`CKError.partialFailure`. It returns the highest-priority non-retryable code, with
account codes ranked first. `isLibraryCloudZoneDeletedByUser`,
`isPermanentLibrarySyncFailure`, `libraryCloudKitAvailability`,
`librarySyncFailureReason`, and `librarySyncDegradedReason` build on it, following
the plan's section D table. `LibraryCloudKitAvailability` gains
`.temporarilyUnavailable`. `recordPipelineFailure` persists any determined
availability, sets the deleted flag, and logs the code of any non-retryable
CloudKit error publicly.

**Deleted state.** `LibraryCloudSyncStatus.cloudLibraryDeletedByUser` persists
under `LibraryCloudSyncCloudLibraryDeletedByUser`. Only a deleted-zone failure
sets it. It is cleared by a successful pass (`recordLibraryCloudSyncSuccess`), by
disabling or cancelling enablement (`resetLibraryCloudSyncDisabledState`), by
backup restore (reset to `defaultValue`), and when the upload action starts. It is
not a policy block reason. The dirty queue, quarantine store, and local library are
left untouched.

**Upload.** `LibraryStore.rebuildLibraryCloudSync(recreatingDeletedZone:)` threads
the opt-in through `bootstrapLibraryCloudSyncEnablement`,
`LibrarySyncCoordinator.bootstrapFirstEnablementOutcome`, and
`SyncPass.recreatesUserDeletedZone` into `prepareRemoteSync`. The generic
**Rebuild** keeps the default `false`. The settings screen calls it through
`LibraryProfileSettingsActions.uploadLibraryToDeletedCloud()`, after a
confirmation alert.

**Re-seeding (section C).** The bootstrap's seeding step moved into
`LibrarySyncCoordinator.seedDirtyQueueDifferingFromRemote`. Bootstrap uses it, and
so does the ordinary pass whenever `importBatch.isFullRefetch` is set. The step
queues local snapshots that differ from the fetched remote change. Afterward,
`reconcileDirtyQueue` drops entries whose merged state matches the cloud, as it
already did for bootstrap. Conflict prompts remain bootstrap-only. The plan's
alternative, routing to bootstrap instead, was not needed.

**Foreground recovery.** When `bootstrapState == .failed` and the deleted flag is
set (a first enable on a purged account), `performLibrarySyncResult` reruns the
bootstrap without the opt-in instead of letting the policy skip the pass as
`.bootstrapIncomplete`. The rerun succeeds only once another device has recreated
the zone. With a completed bootstrap, ordinary foreground and manual passes run
as usual and fail fast in `prepareZoneSubscription` while the zone stays purged.

**UI.** `LibraryCloudSyncStatus.showsCloudLibraryDeletedNotice` (enabled, flagged,
no pass running) drives the "iCloud Data Deleted" status (orange, `icloud.slash`),
the detail text, the hidden raw error line, and the hub status, where it outranks
the issue count. The notice also outranks restoration progress. A bootstrap
that hits the deleted zone in its restoration export or full fetch keeps
`status.restoration`, so otherwise the card would show the restored-entry count
with no explanation. The card replaces Retry with **Upload This Library** and
**Turn Off iCloud Sync** capsules. They sit in a `ViewThatFits` row that stacks
when the card is narrow. The upload alert lives on `LibraryProfileSettingsView`
with the other cloud alerts.

### Files added

- `docs-ai/017-cloud-zone-lifecycle/001-action.md`

### Files changed

- `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncImporter.swift`
- `DataProvider/Tests/LibrarySyncTests/CloudLibrarySyncImporterExporterTests.swift`
- `MyAnimeList/Resources/Localizable.xcstrings`
- `MyAnimeList/Sources/Extensions/String+Extensions.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryCloudSyncStatus.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryPreferences.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryProfileSettingsActions.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator+DirtyQueue.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator+Pipeline.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileCloudSyncController.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileDataManagementSections.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileDataManagementSections+Preview.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsDisplaySupport.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsView.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests+Bootstrap.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests+OrdinarySync.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests+Status.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTestsSupport.swift`
- `docs-ai/017-cloud-zone-lifecycle/000-plan.md`
- `docs-ai/README.md`

## Deviations from plan

- **`isFullRefetch` marks every fetch that starts without a token**, not only the
  token reset and `fetchChangesFromBeginning`. An ordinary fetch with no stored
  token also replaces the incremental state, and seeding is idempotent, so one rule
  covers all three cases (implementation decision).
- **The Rebuild row is hidden while the deleted notice is shown.** Without the
  opt-in, Rebuild would fail at the same purged zone, so it would be a dead end next
  to **Upload This Library**. The plan did not address this row (implementation
  decision).
- **Partial-save classification is broader.** Previously only `.notAuthenticated`
  and `.permissionFailure` among per-record errors made a pass permanent. Now every
  code in the blocking list does, and a raw `CKError.partialFailure` is unwrapped
  too. The unused `CloudLibrarySyncPartialSaveFailure.accountError` was removed.
- **Availability is recorded for every determined value**, including the new
  `.temporarilyUnavailable`, not only `.noAccount` and `.restricted`.
- `.notAuthenticated` and `.permissionFailure` still show CloudKit's own message.
  The plan's table does not list them.
- **The visual check used an offscreen render**, not `make run-sim`. Launching the
  app with sync enabled would have started real CloudKit passes, and the maintainer
  forbade live writes. See Validation.

## Validation

Every command below ran on 2026-10-14 against the uncommitted tree.

- `make test-dataprovider DATAPROVIDER_TEST_FILTER='CloudLibrarySyncImporterExporterTests'`:
  17 tests passed. This includes `importerResetsRejectedTokenAndMarksFullRefetch`
  for both `.changeTokenExpired` and `.zoneNotFound`, which also checks that the
  next incremental fetch is not marked.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySyncCoordinatorTests'`
  on the booted iPhone 18 Pro (iOS 27.0) simulator. The first run hung after the
  Export tests: the host sat idle in XCTest's wait loop for about 15 minutes until
  I killed it, with no failing output captured. Four later runs of the suite
  passed in about 13 seconds each, so the hang did not reproduce and its cause is
  unknown. The passing runs covered:
  - `userDeletedCloudLibraryStopsRetriesAndKeepsLocalWork`, with the deletion in
    preparation, fetch, and export: `.permanentFailure`, flag set and persisted,
    dirty queue and local entry unchanged, raw error hidden, opt-in `false`.
  - `foregroundRecoversAfterAnotherDeviceRecreatesDeletedCloudLibrary`: a failed
    first enable on a purged zone, then a foreground pass after the zone exists,
    which completes the bootstrap and clears the flag.
  - `fullRefetchInOrdinarySyncQueuesLocalStateTheCloudLacks`: `.zoneNotFound` on
    the stored token, then a refetch from `nil`. The local-only and locally newer
    entries are uploaded; the entry that matches the cloud is not.
  - `uploadingAfterCloudDeletionRecreatesZoneAndExportsLibrary`: the opt-in is
    `true` for upload and `false` for the generic Rebuild that follows. Every local
    entry and the settings record are saved.
  - `nonRetryableCloudKitErrorsStopRetriesWithGuidance`: the section D table, for
    both a bare `CKError` and one wrapped in an export or partial-save failure.
  - `disablingLibraryCloudSyncClearsTransientStateAndPersists`, extended to cover
    the flag.
- `xcodebuild -scheme MyAnimeList -configuration Debug -destination 'generic/platform=iOS' build`
  succeeded. The simulator test runs above rebuilt the app after later edits.
- `make lint`: no warnings on changed lines. The remaining warnings predate this
  change.
- Visual check: a temporary test, removed afterward, rendered
  `LibraryProfileICloudSyncSection` in the deleted state with `ImageRenderer` in
  English (light and dark), Japanese, and Chinese. The status, detail text, and
  both actions render. The narrow card stacks the buttons vertically. The first
  render showed a gray **Turn Off iCloud Sync** that looked disabled, so its tint
  changed to `.primary`. Alerts and on-device layout were not checked visually.
- A final run of `LibrarySyncCoordinatorTests`, `LibraryCloudSyncPreferencesTests`,
  and `LibraryProfileSettingsStateTests` after the lint fixes and the
  `accountError` removal passed. The DataProvider `CloudLibrarySync` filter (35
  tests) also passed.
- Codex's built-in reviewer (`gpt-6-astra`, high effort, read-only sandbox)
  reported "No actionable regressions were identified in the current changes."
  It ran no commands, so it adds static review only.
- No live CloudKit checks were run.

## Open questions

### Resolved (2026-10-14)

The maintainer reviewed the first three questions below with me and accepted the
remaining risk as low. They need no live verification before release.

- **Which error rejects an old token after the zone is recreated.** The code has
  not observed it, but `changeTokenExpired` and `zoneNotFound` both reset the token
  and refetch. Any other code is still retried as an ordinary failure, as it was
  before this change.
- **Whether a Development zone can be purged.** This only limited live rehearsal.
  The Development environment never ships, and only Production users can purge.
  Detection rests on the maintainer's original report, which showed "Zone was
  purged by user" during `prepareZoneSubscription`. Apple documents that saving the
  zone again clears the purge, and if that ever failed, the upload would fail
  visibly without losing data.
- **Whether CloudKit could accept an old token against a recreated zone.** That
  would be undocumented and very unlikely, because the new zone has a new change
  history. If it happened, only the other devices' local-only entries would be
  missed. They are queued as soon as they are edited, and **Rebuild** always
  refetches from the start.
- **Plan question 3 (settings in a recreated zone).** Code reading and the upload
  test show that settings upload with the library. When the recreated zone has no
  settings record, `settingsSnapshotForExport` returns the local snapshot, or
  initializes its clock if it is unset.
- **Local edits while the flag is set.** With a completed bootstrap, each
  debounced local edit still schedules a pass, as it does normally. The
  maintainer dismissed this as a performance concern: the pass stops after one
  zone lookup in `prepareZoneSubscription`, which is fewer CloudKit requests than
  a normal pass, and it counts as a permanent failure, so the scheduler does not
  retry it. If another device has recreated the zone, the pass succeeds and
  clears the flag.

### Still open

- The cause of the single hang in the first test run is unknown.
