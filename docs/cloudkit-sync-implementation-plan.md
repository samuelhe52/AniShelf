# AniShelf CloudKit Sync Plan

Created: 2026-05-30
Updated: 2026-05-31

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
- Stages 6-8 are still pending.

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

The current codebase already has the record schema boundary:

- one record per sync identity
- deterministic record names
- encoded episode progress payload
- schema-versioned decode checks
- persisted server change tokens keyed by container/account namespace

This is record mapping only. It is not yet a running sync loop.

### Local Dirty Worklist

The dirty queue now behaves as a durable per-identity worklist rather than a
planned future feature. User-owned local edits advance entry clocks, the
recorder observes `ModelContext.didSave`, and the queue persists pending upserts
or tombstones outside the main SwiftData store.

Deletes are explicit: the app records tombstones before deleting the local row,
including all-or-nothing handling for batch delete rollback.

## Remaining Work

DO NOT follow the stages below as strict implementation requirements. You can be flexible about the specific implementation details depending on the current project status and context.

### Stage 4. Import And Hydration

Status: Complete as of 2026-05-31.

Build the remote import path:

- fetch CloudKit changes from the custom zone
- decode them into `LibraryEntrySyncSnapshot`
- merge into existing local entries by sync identity
- hydrate missing entries through existing TMDb fetch flows. If this fails, we need to notify users; but that is UI/UX work, and we will push this off until the sync coordinator and rollout stages.
- apply tombstones only when newer than local clocks

Open point: offline duplicate adds still need a convergence policy. The current
local repository lookup is not enough once multiple devices can add the same
TMDb entry independently.

### Stage 5. Sync Coordinator

Status: Complete as of 2026-05-31.

Add one coordinator/service responsible for:

- remote import before local export
- consuming and acknowledging dirty queue entries
- suppressing recorder feedback while applying remote imports
- advancing change tokens only after local apply succeeds
- retrying transient CloudKit failures

### Stage 6. Settings And Rollout

Add the user-facing sync surface only after the coordinator exists:

- opt-in toggle
- iCloud availability and setup state
- import/export/degraded status
- last successful sync date
- manual retry / reset actions if needed

### Stage 7. Backup And Restore Policy

The current restore path only clears local queue state after restore. That is
not enough for a live sync feature.

Before rollout, restore needs an explicit policy. Initial direction:

- if sync is enabled, block raw SQLite restore unless the user first disables
  sync
- do not silently reconcile restored local data against CloudKit
- only clear or reset change tokens as part of an explicit restore flow

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
