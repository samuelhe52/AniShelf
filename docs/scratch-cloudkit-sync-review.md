# Code review: CloudKit library sync

Scratch file — review of commits `4a02162` ("feat: Enable CloudKit library sync")
and `eec9aa7` ("fix: Align CloudKit schema with sync requirements"), reviewed
together as one feature. Generated 2026-05-30. Not committed; delete when done.

Both commits form one feature: `4a02162` adds the V2_7_9 synced schema + sync
monitor + entitlements, and `eec9aa7` loosens the schema (optional relationships,
defaults, no unique constraints) to satisfy CloudKit. Enabling `.private`
CloudKit mirroring on a store designed for single-device use is what exposes
most of these.

Note: scalar-default candidates (tmdbID=0, dateSaved/updatedAt=distantPast,
type=.movie, name="") were investigated and **refuted** — NSPersistentCloudKitContainer
imports each CKRecord's scalars atomically, both designated inits require those
fields, and the V2_7_8→V2_7_9 lightweight migration preserves existing values, so
a scalar default never materializes on a real record. A `childSeasonEntries`
cascade-delete fear was also refuted (rule defaults to safe `.nullify`). What
survived clusters on relationships (which fault separately during sync), the
backup/restore path, the sync-status monitor, and the schema itself.

## Top findings (most severe first)

### 1. Lost episode progress on cross-device edit
`DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift:269`

`updateUserInfo` does a full delete-and-rebuild of `episodeProgresses` from the
passed-in snapshot, so a watched-episode update synced from another device is
silently dropped when any unrelated edit is applied against a stale snapshot.

Failure: Device B marks 'watched through ep 8' → syncs into the entry. Device A
holds a `UserEntryInfo` snapshot built before that merge and toggles `favorite`.
`updateUserInfo` clears all `episodeProgresses` and repopulates only from device
A's stale snapshot (`filteredEpisodeProgresses`), wiping device B's ep-8 progress.
Read-modify-write data loss, newly reachable because CloudKit now writes the
entry from two devices.

### 2. Backup restore swaps files under a live CloudKit store
`MyAnimeList/Sources/Utils/BackupManager.swift:275`

`restoreSwiftDataStore` swaps the raw `.store`/`-shm`/`-wal` files underneath a
live CloudKit-mirrored container without resetting any CloudKit sync state, so
restore is reconciled away by the cloud on next sync.

Failure: With `cloudKitEnabled` true, restore removes/replaces the local SQLite
files (lines 308-310) then `reloadDataStore()` recreates the container still
CloudKit-enabled. No code resets record zones / change tokens / de-dups. On next
sync NSPersistentCloudKitContainer reconciles the swapped store against the
unchanged private zone: the pre-restore library re-imports (duplicating/
overwriting restored entries), or restored records never push because their
CKRecord metadata no longer matches. Restore appears to succeed, then iCloud
silently reverts or duplicates the library on every device.

### 3. Cross-device duplicate entries (no unique constraint)
`MyAnimeList/Sources/ViewModels/Library/LibraryRepository.swift:38`

The 'one AnimeEntry per tmdbID' invariant is enforced only by the local
`existingEntry` lookup returning `.first`; CloudKit cannot use `@Attribute(.unique)`
to compensate, so concurrent offline adds produce permanent duplicates with no
reconciliation.

Failure: Device A and Device B both add tmdbID 1399 while offline.
`existingEntry(tmdbID:)` sees only the local store, so each inserts a fresh
record. After sync both coexist; CloudKitSyncMonitor does no merge/de-dup. The
library renders two cards for one show, and edits/episode progress diverge
between the copies. (Note: tmdbID was never `.unique` in the prior schema — this
is a pre-existing limitation that enabling CloudKit promotes from theoretical to
routine.)

### 4. Full child-graph churn on every metadata refresh
`DataProvider/Sources/DataProvider/Models/V2/AnimeEntryDetailBridgeV2_7_9.swift:73`

`apply(dto:)` unconditionally deletes and recreates the entire
characters/staff/seasons/episodes child graph on every metadata refresh, which
CloudKit now mirrors as hundreds of record deletions+creations per refresh.

Failure: LibraryMetadataRefresher calls `replaceDetail` → `apply(dto:)`, which
calls `replaceCharacters/Staff/Seasons/Episodes` — each deletes every existing
child and inserts new ones with no id-based diffing (lines 79-115), even when
refreshed metadata is byte-identical. With `cloudKitDatabase: .private` active, a
routine refresh of an entry with hundreds of episodes uploads hundreds of
needless record deletions and creations to iCloud. Diff children by id and
mutate only what changed.

### 5. Unclamped episode progress during relationship fault-in
`DataProvider/Sources/DataProvider/Models/Other/AnimeEntryEpisodeProgressHelpers.swift:277`

`knownEpisodeProgressLimit` falls back to `episodes?.count ?? 0`; when
`episodeCount` is nil and the `episodes` relationship is unfaulted during CloudKit
hydration, it returns nil (no limit) so out-of-range progress is persisted
unclamped.

Failure: Detail has `episodeCount == nil` and a 12-element `episodes` relationship
that is transiently nil during fault-in. `knownEpisodeProgressLimit` returns nil →
`episodeProgressLimit` returns nil → `clampedEpisodeProgress(99)` returns
`max(0,99)=99` (floored only, never capped) → `setEpisodeProgress` persists
'watched through ep 99' on a 12-episode season and syncs it out. The non-optional
predecessor was always in-memory, so this window is a CloudKit-introduced
regression.

### 6. Orphaned episode-progress rows when relationship is unfaulted
`DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift:267`

`episodeProgresses?.forEach { delete }` is skipped when the relationship is nil,
but the following `episodeProgresses = []` still detaches the persisted rows,
leaking orphaned `AnimeEntryEpisodeProgress` records into the store and CloudKit.

Failure: `updateUserInfo` runs while `episodeProgresses` is an unfaulted nil
to-many (realistic during sync). The per-row delete loop is skipped; `= []` then
detaches the existing rows by nulling their inverse without deleting them. The
relationship's `.cascade` rule only fires on parent deletion, not on reassigning
the to-many, so SwiftData cannot cascade-delete children it never faulted in —
they persist as orphans and propagate to iCloud.

### 7. Restore can pick the wrong store folder
`MyAnimeList/Sources/Utils/BackupManager.swift:344`

`backupStoreFolderURL`'s fallback returns the first subfolder from an unordered
`contentsOfDirectory` that passes validation, so with more than one store-like
folder it can restore the wrong store.

Failure: A restore directory contains two store-like subfolders (e.g. a renamed
store plus a leftover/rollback store). `validateSwiftDataStore` only checks for
the presence of `mal.store`/`-shm`/`-wal` filenames, so both pass; the for-loop
returns whichever `contentsOfDirectory` (no ordering guarantee) yields first.
Restore then overwrites the live store (lines 308-310) with the wrong folder's
files.

### 8. Non-invalid error aborts the whole restore
`MyAnimeList/Sources/Utils/BackupManager.swift:338`

The fallback folder-scan loop only catches `BackupError.swiftDataStoreInvalid`;
any other error from `resourceValues` or `contentsOfDirectory` aborts the entire
restore even when a valid folder exists later.

Failure: While scanning candidate folders, `try folderURL.resourceValues(forKeys:)`
(line 338, outside any catch) or the `contentsOfDirectory` inside
`validateSwiftDataStore` throws a permission/IO CocoaError on one subfolder (e.g.
a protected or `.Trash` dir). The only catch is `catch
BackupError.swiftDataStoreInvalid`, so the error propagates out, is caught at
line 320, and fails the whole restore as `restoreFailed` — even though a valid
store folder sits later in the list.

### 9. Sync status collapsed into a single last-event scalar
`MyAnimeList/Sources/Utils/CloudKitSyncMonitor.swift:49`

Sync state is collapsed into a single last-event scalar recomputed from the most
recent notification, so concurrent phases clobber each other, a missing event key
clears a prior error, transient errors stick, and unordered `@MainActor` Tasks
can leave status stuck.

Failure: `status(from:)` returns `.idle` for any event with `endDate != nil` and
for setup/missing-key events (lines 38-58). During an active export, a completing
import or setup event flips status to `.idle` so the settings UI shows
'Idle'/checkmark while data is still uploading; an `.error` is surfaced for any
`event.error` (transient network/throttle included) and stays red until some
later status-changing event arrives; and each notification spawns an unstructured
`Task { @MainActor }` (line 31) with no FIFO guarantee, so a reordered
import-begin after import-end pins status on `.importing` forever. Phases
(import/export/setup) should be tracked independently, errors filtered for
transience, and updates serialized.

### 10. Dead migration-marker fields baked into the synced schema
`DataProvider/Sources/DataProvider/Models/V2/AnimeEntryV2_7_9.swift:48`

`cloudKitMigrationMarker` (and the adjacent `cleanupMigrationMarker`) is never
read or written anywhere, baking permanent dead attributes into a CloudKit-backed
record type.

Failure: grep shows `cloudKitMigrationMarker`'s only occurrence is its
declaration; neither init assigns it and the V2_7_8→V2_7_9 stage is
`.lightweight`, so nothing ever sets it. On a CloudKit `@Model` it materializes as
an unused `CD_AnimeEntry` attribute, and once the schema is promoted to the
CloudKit production environment, fields cannot be removed — the dead column is
locked in permanently. Drop the field before first production sync.

## Lower-severity (verified but below the top 10)

- **hasSiblingSeasonEntry** (`EntryDetailViewModels.swift:240`) — PLAUSIBLE: a nil
  `childSeasonEntries` during hydration returns `false`, but the primary
  `visibleLibraryEntries()` query catches visible siblings first, so only hidden
  siblings in the sync window are affected.
- **`cloudKitContainerIdentifier` hardcoded** (`DataProvider.swift:29`) — the
  `iCloud.com.samuelhe.MyAnimeList` literal is duplicated against the entitlements
  and `String.bundleIdentifier`; a rename that misses it points `.private(...)` at
  an ungranted container → `fatalError` at launch.
- **CloudKit-readiness guard tests** (`MigrationTests.swift:13, 724`) — validate
  constraints via source-text grep against a hardcoded V2_7_9 filename list rather
  than inspecting the actual `Schema`/`ModelContainer`; a future model file or
  attribute-spelling variant slips past, shipping a CloudKit-incompatible schema.
- **`backupStoreFolderURL` double validation** (`BackupManager.swift:296`) — the
  fallback path validates the folder, then the caller validates it again
  (redundant directory enumeration).
- **DataProvider CloudKit auto-enable** (`DataProvider.swift:66`) — inferred from
  `url == persistenStoreURL` identity rather than an explicit config; mitigated
  today by the new `cloudKitEnabled` override and the fact that no production path
  uses a non-default URL.
- **Five parallel switch properties** (`LibraryProfileSettingsSections.swift:558`)
  — title/subtitle/image/badge/tint each re-switch the Status enum; adding a case
  means editing five consistent sites.
