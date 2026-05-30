# AniShelf CloudKit Sync Implementation Plan

Created: 2026-05-30

This document defines the implementation direction for AniShelf library sync.
It intentionally replaces the abandoned direction of mirroring the full
SwiftData store through SwiftData CloudKit integration.

For failure patterns from the earlier full-store mirroring attempt, see
`scratch-cloudkit-sync-review.md` in the repository root.

## Progress

- Direction chosen: manual CloudKit sync using transient snapshots and explicit
  merge rules.
- Rejected direction: a separate SwiftData snapshot/sync container created
  mainly to use builtin SwiftData+CloudKit mirroring.
- Stage 1 local sync contract, merge semantics, and clock ownership are
  implemented.
- Completed so far: `LibrarySync` target, deterministic sync identity,
  snapshot model, persisted optional `libraryUpdatedAt` / `trackingUpdatedAt`
  fields on `AnimeEntry`, lightweight schema migration, snapshot creation from
  entry-owned clocks, nil-clock merge/apply semantics, duplicate decoded
  progress normalization, stale custom-poster cleanup, tombstone/dateSaved
  protection for migrated nil-clock entries, and user mutation routing for
  clock stamping.
- Next: Stage 2 CloudKit record mapping. Stage 3 will add the durable dirty
  queue; until then the entry clocks are the local recency contract rather than
  a persisted upload queue.

## Direction

Use CloudKit directly for a compact sync model. Keep SwiftData as the local app
database and metadata cache.

Do not enable `ModelConfiguration(... cloudKitDatabase: .private)` for the
current `AnimeEntry` SwiftData graph.
Do not add a second SwiftData model container whose main purpose is mirroring a
duplicated snapshot model through builtin SwiftData+CloudKit integration.

The split is:

- SwiftData stores the local library, rich relationships, metadata cache, and
  app UI state.
- CloudKit stores compact user-owned library records in the private database.
- A sync layer imports and exports between CloudKit records and SwiftData
  models with explicit merge rules.

The local source of truth for sync recency is persisted on `AnimeEntry`
itself. `libraryUpdatedAt` and `trackingUpdatedAt` live in the main local
SwiftData model, are bumped when their owned domains change, and are serialized
into transient sync snapshots for upload and merge.

This avoids turning local implementation details into distributed sync state:
metadata child graphs, relationship faulting, backup SQLite files, and local
object identity should not become CloudKit conflict surfaces.

## Package Placement

All sync logic lives in a dedicated `LibrarySync` Swift Package target, added
to the existing `DataProvider/Package.swift`. Do not place sync code in the
`MyAnimeList` app target.

Rationale:

- The merge and conflict rules are the highest-value unit-testable logic in
  this feature. A Swift Package target lets them be tested with `swift test`
  and `make test` without a host app.
- Keeping sync out of the app target prevents the app from becoming a monolith
  of UI, networking, and sync orchestration.
- `LibrarySync` sits naturally alongside `DataProvider` as the sync layer on
  top of the local library substrate.
- A new top-level package would require additional xcodeproj configuration for
  a solo app; a new target inside the existing package is sufficient.

Target layout:

- `DataProvider/Sources/DataProvider/` — SwiftData models, migration,
  data handler. No CloudKit imports.
- `DataProvider/Sources/LibrarySync/` — sync identity, snapshots, merge rules,
  CloudKit client, dirty queue, change token store, sync orchestration.
- `DataProvider/Tests/LibrarySyncTests/` — unit tests for all sync logic.
- `MyAnimeList/Sources/` — UI, ViewModels, TMDb network layer, app lifecycle
  wiring. Imports `LibrarySync`; no sync business logic.

The existing `MyAnimeList/Sources/Sync/LibraryEntrySyncSnapshot.swift` was
created before this placement decision was made and should be moved into
`DataProvider/Sources/LibrarySync/` as part of the Stage 1 completion work.

## Sync State Persistence

Sync state is persisted outside the main `AnimeEntry` SwiftData store so it
is not swept up in library backups or schema migrations.

**Server change token** — stored in `UserDefaults` as an archived `Data` blob.
`CKServerChangeToken` serialises to `Data` via `NSKeyedArchiver`. One token
per custom zone (e.g. `AniShelfLibrary`). Advanced only after a successful
import application.

**Dirty queue** — a JSON file in a dedicated subfolder under the app's
Application Support directory, e.g.
`Application Support/AniShelf/Sync/dirty-queue.json`. The file stores a list
of dirty entries, each with:

- sync identity string
- dirty timestamp (when the entry was last modified locally)
- tombstone flag and timestamp (for deletions)

The queue is self-draining: entries are removed after CloudKit confirms a
successful upload. The queue is persisted so pending uploads survive app
termination. Under normal online operation the file is nearly always empty.

Metadata refresh must never write to the dirty queue.

**Snapshots** — not persisted. `LibraryEntrySyncSnapshot` is a transient
conversion bridge generated from the current `AnimeEntry` state at upload time,
and constructed from a `CKRecord` at import time. It is not stored in SwiftData
or on disk, and there is no separate SwiftData snapshot database.

## Non-Goals

- Do not sync the whole SwiftData database.
- Do not sync TMDb metadata child graphs such as characters, staff, seasons, and
  episodes.
- Do not treat metadata refresh as a sync event.
- Do not rely on CloudKit uniqueness constraints for library identity.
- Do not silently reconcile backup restore through CloudKit.

## Stage 1: Sync Contract And Local Merge Rules

Build the local data contract before introducing network sync.

Deliverables:

- Add a `LibrarySync` target to `DataProvider/Package.swift` and move
  `LibraryEntrySyncSnapshot.swift` from `MyAnimeList/Sources/Sync/` into
  `DataProvider/Sources/LibrarySync/`.
- Add persisted `libraryUpdatedAt` and `trackingUpdatedAt` fields to
  `AnimeEntry`, including the required SwiftData schema bump and migration.
- Add a deterministic library identity type in `DataProvider/Sources/LibrarySync/`.
- Add `LibraryEntrySyncSnapshot` for user-owned state.
- Add conversion from `AnimeEntry` to a sync snapshot, with clocks read from
  the entry itself rather than supplied externally.
- Add merge/apply helpers from a sync snapshot back to `AnimeEntry`.
- Add local mutation helpers or routing so sync-relevant edits reliably bump
  the correct persisted clock.
- Add tests for stale snapshot and conflict behavior.

Suggested identity format:

- Movie: `movie:<tmdbID>`
- Series: `series:<tmdbID>`
- Season: `season:<parentSeriesID>:<seasonNumber>:<tmdbID>`

Initial snapshot fields:

- sync identity
- TMDb ID
- parent series ID, when relevant
- season number, when relevant
- entry type
- `onDisplay`
- `dateSaved`
- `watchStatus`
- `dateStarted`
- `dateFinished`
- `isDateTrackingEnabled`
- `score`
- `favorite`
- `notes`
- `usingCustomPoster`
- user-selected poster URL, if custom poster state requires it
- episode progress snapshots, including per-season `updatedAt`
- `libraryUpdatedAt`
- `trackingUpdatedAt`
- deletion/tombstone timestamp

Merge rules:

- Same sync identity represents the same library entry across devices.
- Episode progress merges by `seasonNumber`, using each row's `updatedAt`.
- User fields should be merged by explicit field or domain clocks rather than
  by replacing a whole `UserEntryInfo` snapshot.
- `applySyncSnapshot` must be safe when given a raw remote snapshot; stale
  tracking fields must not overwrite newer local tracking state.
- Metadata fields such as title, overview, poster, backdrop, character, staff,
  season, and episode details are refreshed locally from TMDb.
- Deletion/tombstone wins only when newer than the relevant local modification.

Verification:

- Test that a stale favorite toggle does not wipe newer episode progress.
- Test that a stale remote tracking snapshot does not overwrite newer local
  tracking fields.
- Test deterministic identity for movie, series, and season entries.
- Test duplicate remote/local snapshots with the same identity converge.

## Stage 2: CloudKit Record Mapping

Add CloudKit storage without wiring it into app startup.

Deliverables:

- Add `CloudLibrarySyncClient`.
- Use the private CloudKit database.
- Use a custom record zone, for example `AniShelfLibrary`.
- Use deterministic `CKRecord.ID(recordName:)` derived from sync identity.
- Add record encode/decode for `LibraryEntrySyncSnapshot`.
- Persist server change tokens in `UserDefaults` (as archived `Data`) outside
  the mirrored SwiftData store, following the policy described in
  **Sync State Persistence** above.

CloudKit record notes:

- Prefer one record per library sync identity.
- Encode nested episode progress as stable JSON/Data unless a separate record
  type is demonstrably needed.
- Keep record fields small and user-owned.
- Store schema version on the record.

Verification:

- Unit-test snapshot-to-record and record-to-snapshot mapping.
- Test unknown future schema versions fail safely or are skipped.
- Test malformed records do not corrupt local state.

## Stage 3: Local Change Tracking

Route user-owned changes into a sync queue.

Deliverables:

- Add a local dirty queue persisted as JSON in Application Support, following
  the policy described in **Sync State Persistence** above.
- Mark entries dirty when user-owned state changes.
- Keep metadata refresh out of the dirty queue.
- Add an explicit tombstone path for deletes.

Sync-relevant actions:

- Add entry.
- Delete entry.
- Restore hidden entry to display.
- Update watch status.
- Update dates/date tracking.
- Update score.
- Toggle favorite.
- Update notes.
- Change custom poster state.
- Update episode progress.

Verification:

- Test each user action enqueues one intended sync snapshot.
- Test metadata refresh does not enqueue CloudKit writes.
- Test delete creates a tombstone instead of relying on local object deletion.

## Stage 4: Import And Hydration

Import remote records into SwiftData.

Deliverables:

- Add import pipeline that applies remote snapshots to local models.
- Hydrate missing entries with existing `InfoFetcher.latestInfo(...)`.
- Reuse existing parent-series generation for season entries.
- Keep failed hydrations pending instead of creating broken visible cards.
- Apply tombstones explicitly.

Import behavior:

- If local entry exists by sync identity, merge user-owned fields.
- If local entry is missing and remote is not deleted, fetch metadata and create
  the entry.
- If metadata hydration fails, keep the remote snapshot pending for retry.
- If remote tombstone is newer than local changes, hide/delete according to the
  chosen product policy.

Verification:

- Test remote add creates or hydrates a local entry.
- Test remote season add creates or links the hidden parent series.
- Test remote tombstone applies only when newer than local changes.
- Test pending hydration can retry after a network failure.

## Stage 5: Sync Orchestration And Status

Add the service that sequences import/export work.

Deliverables:

- Add `CloudLibrarySyncService`.
- Sequence remote import before local upload on first enable.
- Upload local dirty snapshots after merge.
- Save change tokens only after successful import application.
- Retry transient CloudKit failures.
- Add status model and logging.

Status model should track:

- iCloud availability/setup
- importing
- exporting
- idle
- degraded/error
- last successful sync date

Avoid collapsing sync state into a single last-event scalar. Import, export, and
setup can overlap conceptually and should not clobber each other in the UI.

Verification:

- Test status transitions.
- Test transient errors do not permanently pin sync as failed.
- Test change tokens are not advanced when local import application fails.

## Stage 6: Settings UI And Opt-In Rollout

Expose sync as an explicit user-controlled feature.

Deliverables:

- Add settings UI under the existing library profile/settings surface.
- Add an opt-in CloudKit sync toggle.
- Show iCloud availability, current sync status, last sync date, and retry.
- Add a reset local sync state action if needed.
- Use `LocalizedStringResource` for all user-facing SwiftUI strings.

Initial enable behavior:

1. Check iCloud availability.
2. Fetch remote changes.
3. Merge remote records into the local library.
4. Upload local dirty state.
5. Start normal background sync cadence.

Verification:

- `make build`
- `make lint`
- `make run-device` when visual inspection is needed.

## Stage 7: Backup And Restore Policy

Make backup restore explicit around CloudKit.

Deliverables:

- Prevent silent raw SQLite restore while CloudKit sync is active, or require an
  explicit "replace cloud with this backup" flow.
- Clear or reset sync tokens only as part of an explicit restore policy.
- Fix backup folder selection to be deterministic.
- Continue scanning candidate folders when one invalid or unreadable folder is
  encountered.

Recommended initial policy:

- If CloudKit sync is enabled, block restore and explain that sync must be
  disabled first.
- Add cloud replacement later as a separate deliberate feature.

Verification:

- Test restore is blocked when sync is enabled.
- Test restore works when sync is disabled.
- Test fallback folder selection is deterministic.
- Test unreadable invalid candidate folders do not abort valid restore.

## Stage 8: Manual Multi-Device Validation

Before production rollout, test with two physical devices on the same iCloud
account and the CloudKit development environment.

Required scenarios:

- Device A adds an entry; Device B imports it.
- Both devices add the same entry offline; sync converges to one entry.
- Device A updates episode progress while Device B toggles favorite from stale
  local state; both changes survive.
- Device A deletes while Device B edits offline; timestamp rule behaves as
  designed.
- Metadata refresh uploads no child-graph churn.
- Backup restore follows the explicit CloudKit policy.
- iCloud unavailable or throttled shows degraded status without corrupting data.

## First Implementation Slice

Start with Stage 1.

The first code change should add:

1. `LibraryEntrySyncIdentity`
2. `LibraryEntrySyncSnapshot`
3. Persisted `libraryUpdatedAt` and `trackingUpdatedAt` on `AnimeEntry`
4. Snapshot creation from `AnimeEntry`
5. Merge/apply helpers
6. Tests for deterministic identity and stale snapshot preservation

Only after these local semantics are tested should the CloudKit client be added.
