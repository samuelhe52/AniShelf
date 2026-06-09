# AniShelf CloudKit Sync Plan

Created: 2026-05-30
Updated: 2026-06-03

This document tracks the accepted library sync direction and the remaining work.
It replaces the abandoned idea of mirroring AniShelf's full SwiftData graph
through SwiftData's built-in CloudKit store integration.

For failure patterns from the earlier full-store mirroring attempt, see
`docs/scratch-cloudkit-sync-review.md`.

## Current Status

- Main-store CloudKit mirroring is disabled. `DataProvider` still creates the
  main `ModelConfiguration` with `cloudKitDatabase: .none`.
- The `LibrarySync` package target exists and already owns the local sync model
  and CloudKit record codec.
- Stage 1 is complete:
  - deterministic sync identity
  - `LibraryEntrySyncSnapshot`
  - persisted `libraryUpdatedAt` / `trackingUpdatedAt` on `AnimeEntry`
  - snapshot merge/apply rules and tests
- Stage 2 is complete:
  - `CloudLibrarySyncClient`
  - deterministic `CKRecord.ID` mapping in custom zone `AniShelfLibrary`
  - snapshot encode/decode
  - `CloudLibrarySyncChangeTokenStore`
- Stage 3 is complete:
  - persisted JSON dirty queue in Application Support
  - `ModelContext.didSave`-based local change recorder
  - explicit delete tombstones, including batch-delete rollback handling
- Stage 4 is complete:
  - remote CloudKit import loop
  - zone-delta decode and merge by sync identity
  - hydration of missing rows through TMDb
  - tombstone resolution against local clocks
- Stage 5 is complete:
  - `LibrarySyncCoordinator`
  - remote-import-before-export sequencing
  - recorder suppression around remote applies
  - token advancement only after local save succeeds
- Stage 6 is complete:
  - persisted opt-in sync setting, defaulting off
  - first-enable bootstrap with CloudKit preparation and conflict choice handling
  - sync policy gating for enabled state, bootstrap completion, and TMDb API key
  - settings UI for enable/disable, bootstrap state, last sync time, and manual retry
- Stage 7 is complete:
  - restore is blocked while iCloud sync is enabled or actively syncing
  - successful restore keeps CloudKit untouched, resets local sync state, clears
    dirty queue work, and clears stored change tokens
- Stage 8 is still pending.

## Plan Maintenance

- Agents must update this document when a numbered stage is completed.
- When marking a stage complete, update both the status summary above and the
  relevant stage section below so the plan stays consistent.

## Accepted Direction

Keep the existing SwiftData store local and sync only a compact user-owned
library projection through explicit CloudKit records.

The split is:

- SwiftData stores the local library, metadata cache, and app UI state.
- CloudKit stores only compact library sync records in the private database.
- Sync code maps between `AnimeEntry` and transient snapshots with explicit
  merge rules.

Do not:

- enable CloudKit on the main `AnimeEntry` SwiftData store
- mirror TMDb metadata child graphs into CloudKit
- treat metadata refresh as a sync event
- rely on CloudKit uniqueness constraints to deduplicate entries

## Implemented Foundations

### Local Sync Contract

Local recency lives on `AnimeEntry` through `libraryUpdatedAt` and
`trackingUpdatedAt`. Those clocks are serialized into
`LibraryEntrySyncSnapshot`, and snapshot merges already protect newer local
tracking data from stale remote payloads.

### CloudKit Record Codec

The current codebase has the record schema boundary:

- one record per sync identity
- deterministic record names
- encoded episode progress payload
- schema-versioned decode checks
- persisted server change tokens keyed by container/account namespace

This codec is used by the live import/export path. AniShelf still avoids
SwiftData CloudKit mirroring; sync runs through explicit CloudKit records in
the custom library zone.

### Local Dirty Worklist

The dirty queue now behaves as a durable per-identity worklist rather than a
planned future feature. User-owned local edits advance entry clocks, the
recorder observes `ModelContext.didSave`, and the queue persists pending upserts
or tombstones outside the main SwiftData store.

Deletes are explicit: the app records tombstones before deleting the local row,
including all-or-nothing handling for batch delete rollback.

### Running Sync Loop

`LibrarySyncCoordinator` now owns the end-to-end sync pass:

- prepares the custom CloudKit zone and silent subscription
- resolves the current iCloud account namespace automatically
- imports remote changes before exporting local dirty work
- suppresses the local recorder while remote changes are applied
- commits the server change token only after local apply succeeds
- reconciles dirty queue entries after remote conflict resolution
- exports only the CloudKit-accepted dirty entries and leaves partial failures
  queued for retry

The app requests sync on launch, foreground activation, and CloudKit remote
notifications only when the user has enabled sync, first-enable bootstrap has
completed, and the TMDb API key is available. Settings now expose opt-in,
bootstrap, status, conflict choice, manual retry, and explicit restore
guardrails.

## Remaining Work

DO NOT follow the stages below as strict implementation requirements. You can be flexible about the specific implementation details depending on the current project status and context.

### Stage 7. Backup And Restore Policy - Complete

Restore is local-only and does not silently reconcile against CloudKit:

- if sync is enabled or currently active, block raw SQLite restore and tell the
  user to turn off iCloud Sync first
- after restore, keep CloudKit records untouched, reset local sync state to
  disabled/not-started, clear dirty queue work, and clear stored change tokens
- users can turn iCloud Sync on again after restore; re-enable uses the existing
  first-enable bootstrap and conflict policy

### Stage 8. Manual Validation

Before any real rollout, validate on two physical devices in the CloudKit
development environment:

- add on Device A, import on Device B
- conflicting edits on different devices preserve both newer domains
- delete vs. offline edit follows the tombstone clock rule
- metadata refresh does not enqueue sync work
- restore follows the explicit sync policy

## Guardrails

- Keep the main SwiftData store on `cloudKitDatabase: .none` until a full sync
  coordinator and rollout policy exist.
- Keep metadata refresh out of the dirty queue.
- Keep delete handling explicit through tombstones.
- Treat the dirty queue as persisted sync work, not backup payload.
