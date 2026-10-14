# 017 — CloudKit zone lifecycle and account error handling: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-14 |
| Origin | Maintainer report on 2026-10-14: iCloud Sync showed "Setup Failed" during `prepareZoneSubscription` with "Zone was purged by user", and Retry could not recover |
| Related | [009 deferred defect D10](../009-cloud-sync-correctness/historical/cloud-sync-correctness-fixes-plan.md) · [010 package design](../010-selective-sync-package/design.md) · [001 review WARN-9](../001-selective-library-sync/historical/cloudkit-sync-stages-1-5-review.md) |

## Background

A user can delete AniShelf's iCloud data from Settings › Apple Account › iCloud ›
Manage Storage. CloudKit then marks the `AniShelfLibrary` zone as purged. Every
later zone lookup returns `CKError.userDeletedZone` until a client saves the zone
again. The purged mark is server-side, so reinstalling, re-signing into iCloud, or
toggling sync off and on does not clear it.

Current behavior, verified by reading the source on 2026-10-14:

- `CloudLibrarySyncLiveDatabase.ensureZone`
  (`DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift`) recreates the
  zone only for `.unknownItem` and `.zoneNotFound` (`isCloudLibrarySyncMissingItem`).
  It throws `.userDeletedZone` unchanged.
- `Error.isPermanentLibrarySyncFailure`
  (`MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift`) does not
  know the code, so the pass counts as retryable. The scheduler retries until it
  runs out of attempts, then shows the raw CloudKit message. Ordinary sync, manual
  retry, Rebuild, and first-enable bootstrap all start with `prepareRemoteSync`, so
  none of them can get past the error.

Two related gaps share the same error-mapping layer:

1. **The zone was replaced while a device held a token (D10).** When
   `ensureZone` sees `.zoneNotFound`, it quietly creates an empty zone. When a
   change token is rejected, `CloudLibrarySyncImporter.fetchChanges` refetches from
   the beginning with `changeTokenExpired`. The ordinary pass then applies the
   fetch but never queues local entries that are missing from, or differ from, the
   new zone. The device ends up holding data the cloud never receives. After this
   plan ships, this also happens on every other device once one device re-uploads
   to a purged zone.
2. **Account and configuration errors are classified as retryable.**
   `libraryCloudKitAvailability` maps only `.notAuthenticated` and
   `.permissionFailure`. `isPermanentLibrarySyncFailure` adds only `.quotaExceeded`.
   `.accountTemporarilyUnavailable`, `.managedAccountRestricted`,
   `.incompatibleVersion`, `.badContainer`, `.missingEntitlement`, and
   `.badDatabase` all use up the retry budget, then show a raw English message
   with no hint about what to do.

## Goals

- When iCloud reports that the user deleted the library zone, stop retrying and
  tell the user what happened. Offer two actions: upload this device's library
  again, or turn off iCloud Sync.
- Recreate a user-deleted zone only after the user explicitly chooses to upload.
- After any fetch from the beginning that replaces an incremental fetch, queue the
  local entries whose state the cloud lacks or holds differently. A replaced zone
  then converges instead of drifting.
- Classify the account and configuration errors listed above, and show localized,
  actionable copy instead of the raw CloudKit text.

### Non-goals

- Item 3 from the 2026-10-14 audit: one failed record in
  `fetchRecordZoneChanges` (`try modificationResult.get()`) fails the whole page.
  It stays deferred.
- A `CKAccountChanged` observer. Recovery after the user fixes their account
  relies on the existing foreground trigger and manual retry (see Validation).
- Changing the wire format, `.allKeys` save policy, or transport (010 owns those).
- Deleting local data in response to a cloud deletion. The local library is always kept.

## Design / approach

### A. Transport: name the zone states (DataProvider)

- Add a public error type to `CloudLibrarySyncDatabase.swift` (proposed name
  `CloudLibrarySyncZoneDeletedByUserError`) or an equivalent typed signal.
  `ensureZone` throws it when the zone fetch returns `.userDeletedZone`, unless
  the caller explicitly allowed recreation.
- Extend `CloudLibrarySyncDatabase.ensureZoneAndSubscription` and
  `CloudLibrarySyncImporter.prepareRemoteSync` with an explicit opt-in (proposed:
  `recreatingUserDeletedZone: Bool = false`). Only when it is `true` does
  `ensureZone` take the existing save-zone path for `.userDeletedZone`. Update the
  test doubles that conform to the protocol.
- Keep creating the zone automatically for `.zoneNotFound` / `.unknownItem`. That is
  a first setup, or a zone removed by something other than the user's Manage Storage
  action, such as the CloudKit Console or a development reset. D10's harm was the
  missing re-upload, and section C fixes that, so no prompt is needed here.
- The coordinator classifies `.userDeletedZone` coming from any later call too
  (`fetchRecordZoneChanges`, `fetchRecords`, `save`, including inside
  `CloudLibrarySyncPartialSaveFailure` / `CloudLibrarySyncExportFailure`). This covers
  a purge that lands in the middle of a pass.

### B. Coordinator and status: a "cloud library deleted" state (app)

- Add an error predicate next to `isPermanentLibrarySyncFailure` (proposed:
  `isLibraryCloudZoneDeletedByUser`). It unwraps the same wrappers as the existing
  predicates. Such failures count as `.permanentFailure`, so the scheduler stops
  automatic retries (`LibrarySyncScheduler.runScheduledSync` already does this).
- Persist a status flag in `LibraryCloudSyncStatus` and `LibraryPreferences`
  (proposed: `cloudLibraryDeletedByUser: Bool`, default `false`). Set it in
  `recordPipelineFailure`. Clear it on any successful pass, on disable
  (`resetLibraryCloudSyncDisabledState`), on backup restore reset, and when the
  upload action starts.
- Keep the dirty queue, quarantine store, and local library unchanged while the
  flag is set.
- Foreground and manual triggers must still run a pass while the flag is set. If
  another device has already recreated the zone, the pass succeeds through
  section C and clears the flag with no prompt. The flag must not become a
  `LibraryCloudSyncPolicyBlockReason`.
- Upload action: reuse `LibraryStore.rebuildLibraryCloudSync()` with a parameter
  that allows recreating the deleted zone (proposed:
  `rebuildLibraryCloudSync(recreatingDeletedZone:)`). Thread it through
  `bootstrapLibraryCloudSyncEnablement` and `bootstrapSyncPass` into
  `prepareRemoteSync`. Rebuild already resets change tokens and
  `lastCompletedScope`. The bootstrap then fetches the empty zone and queues every
  local entry plus settings through `dirtyQueueSeeding`, and exports them. The
  generic **Rebuild** menu action must keep passing `false`, because its confirmation
  copy does not ask for consent to re-upload deleted data.
- Turn-off action: the existing `disableLibraryCloudSync()`.

### C. Re-seed after a fetch from the beginning (app + importer)

- `CloudLibrarySyncImporter.fetchChanges` also treats `.zoneNotFound` with a stored
  token as a token reset, alongside `changeTokenExpired`: it clears the token and
  refetches with `nil`. It marks the resulting batch (proposed:
  `CloudLibrarySyncImportBatch.isFullRefetch = true`). `fetchChangesFromBeginning`
  sets the same mark.
- In the ordinary pass, when `isFullRefetch` is set, run the same
  `dirtyQueueSeeding` step that bootstrap runs. It queues local snapshots whose
  merged state differs from the fetched remote change. Ambiguous-conflict prompts
  stay bootstrap-only: entries without clocks merge deterministically, as ordinary
  sync already does. (The implementer may instead route to bootstrap if sharing the
  step proves awkward. Record the choice in `001-action.md`.)

### D. Account and configuration error classification (app)

Extend `isPermanentLibrarySyncFailure`, `libraryCloudKitAvailability`,
`librarySyncFailureReason`, and `librarySyncDegradedReason`:

| CKError code | Result | Availability | User-facing reason (English source; localize) |
| --- | --- | --- | --- |
| `.userDeletedZone` | permanent + deleted flag | unchanged | Dedicated UI (section E) |
| `.accountTemporarilyUnavailable` | permanent | new `.temporarilyUnavailable` | Your Apple Account needs attention. Open Settings to verify it, then try again. |
| `.managedAccountRestricted` | permanent | `.restricted` | iCloud is restricted for this account. |
| `.incompatibleVersion` | permanent | unchanged | Update AniShelf to keep syncing with iCloud. |
| `.badContainer`, `.missingEntitlement`, `.badDatabase` | permanent | unchanged | iCloud Sync isn't available in this build. (Log the code.) |

The final wording is the implementer's to polish. Every new user-facing string needs
`zh-Hans` and `ja` entries in `MyAnimeList/Resources/Localizable.xcstrings`.
Write CJK and Latin text adjacent with no manual spaces (native typography adds the gap). Use `LocalizedStringResource`
or `String(localized:)`, matching the surrounding code.

### E. Settings UI

In the iCloud Sync card (`LibraryProfileDataManagementSections.swift`,
`LibraryProfileSettingsDisplaySupport.swift`, `LibraryProfileSettingsView.swift`),
when `cloudLibraryDeletedByUser` is set:

- Status title: something like "iCloud Data Deleted", orange or red, instead of
  "Setup Failed" / "Sync Failed".
- Detail: "AniShelf's iCloud data was deleted in iCloud settings. Your library on
  this device is unchanged."
- Replace Retry with **Upload This Library**, behind a confirmation alert that
  explains it will re-create iCloud data from this device. Add **Turn Off iCloud
  Sync** as the alternative.
- Hide the raw CloudKit error line for this state.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Ask before recreating a user-deleted zone | Apple's guidance for `userDeletedZone` is to remove local data or ask before re-uploading, and the 010 design forbids silently recreating it. Rejected: adding `.userDeletedZone` to `isCloudLibrarySyncMissingItem`, which would quietly undo a deliberate deletion. |
| Keep local data; never delete it automatically | The purge removes only the cloud copy, and the local store is then the only copy. Rejected: mirroring the deletion locally. |
| Auto-recreate on `.zoneNotFound` with a token, but re-seed | No user consent is involved, and D10's actual harm was the missing re-upload. Rejected: prompting here too, because development resets and Console edits would show a confusing prompt. |
| Re-seed on every fetch from the beginning, including plain `changeTokenExpired` | Seeding only queues entries that differ, so it is idempotent. CloudKit does not tell us whether a token expired because the zone was replaced. Rejected: re-seeding only when the zone is known to be replaced, which we cannot detect. |
| Reuse Rebuild and bootstrap for the upload | They already reset the tokens and scope, fetch from the beginning, and seed every differing entry. Rejected: a new upload-everything export path that duplicates the seeding logic. |
| Deleted state counts as a permanent failure plus a flag, not a policy block | It stops wasted retries but still lets foreground and manual passes notice that another device has re-uploaded. |
| Defer the per-record fetch failure and the `CKAccountChanged` observer | The maintainer scoped this entry to the purge plus audit items 1 and 2 on 2026-10-14. |

## Validation and acceptance criteria

Focused automated tests. Extend the existing suites; avoid duplicating coverage:

- `DataProvider/Tests/LibrarySyncTests/CloudLibrarySyncImporterExporterTests.swift`:
  `.zoneNotFound` with a stored token clears the token and returns a batch marked as
  a full refetch. `changeTokenExpired` sets the same mark.
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests+OrdinarySync.swift`
  / `+Bootstrap.swift`, using the existing mock database:
  - `.userDeletedZone` from preparation sets the flag, returns `.permanentFailure`,
    and leaves the dirty queue untouched. The same holds when the error arrives
    during fetch or export.
  - The upload action passes the recreate opt-in, clears the flag, and exports
    every local entry and the settings record. Generic Rebuild does not pass the opt-in.
  - Disabling sync clears the flag.
  - A full-refetch batch in an ordinary pass queues local-only and locally differing
    entries, and does not queue entries already equal in the cloud.
- `LibrarySyncCoordinatorTests+Status.swift` or `LibraryCloudSyncPreferencesTests.swift`:
  the flag survives a reload, plus one table-style test for the section D
  classification.

Commands: `make test-dataprovider DATAPROVIDER_TEST_FILTER='CloudLibrarySyncImporterExporterTests'`,
then `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySyncCoordinatorTests'`
(and the preferences/status suite if touched). `make lint`. A `make run-sim` visual
check of the new card state, using a preview or debug fixture if one exists.

Confirm before finishing: a foreground trigger runs an ordinary pass while the flag
is set, including when `bootstrapState == .failed` (first enable on a purged
account). If `libraryCloudSyncPolicyBlockReason()` returns `.bootstrapIncomplete`
there, the foreground path must still be able to recover, or the gap must be
documented.

Live checks write to iCloud and need the maintainer's explicit authorization. See
the open questions below.

### Open questions

- Which error does CloudKit return when an old change token is used against a zone
  that was deleted and recreated: `changeTokenExpired` or `zoneNotFound`? The plan
  handles both. Record what is observed. *Resolved 2026-10-14: not observed, but
  both are handled, so the risk was accepted as low
  ([action record](001-action.md#resolved-2026-10-14)).*
- Can a Development-environment zone be put into the user-purged state (Manage
  Storage may only affect Production)? This decides whether the purge can be tested
  live before release. *Resolved 2026-10-14: the Development environment never
  ships, and detection matches the maintainer's Production report, so live
  rehearsal is not required ([action record](001-action.md#resolved-2026-10-14)).*
- Does the bootstrap settings reconciliation upload local settings when the
  recreated zone has no settings record? Verify in `+Settings` tests. *Resolved
  2026-10-14: yes, as covered by the upload test in `+Bootstrap`
  ([action record](001-action.md#resolved-2026-10-14)).*

## Amendments

None yet.
