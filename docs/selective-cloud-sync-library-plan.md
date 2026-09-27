# Selective cloud sync library: specification and extraction plan

Created: 2026-09-27

Status: Proposed design. Implementation has not started. The product direction
comes from the extraction discussion; API names, storage details, and transport
choices below remain proposals.

## Purpose

Let adopters declare the application state worth syncing and define how that
state becomes a complete local object on another device.

AniShelf uses explicit CloudKit records because its local SwiftData store also
contains substantial fetched metadata. That metadata can be reconstructed and
does not belong in the synced payload. The library must preserve this separation:
sync selected authoritative fields, retain reconstructible data locally, and
give the adopter control over object reconstruction.

For example, an AniShelf record can carry a stable media identity, library
membership, watch status, notes, and episode progress. A receiving device uses
the identity to fetch metadata, builds a local object, and applies the synced
user state. An existing local object receives only the selected fields; its
cached metadata remains intact.

The same sync core must support SwiftData fields, registered UserDefaults keys,
and custom values that do not live in SwiftData.

## Scope

The initial implementation should support:

- Explicit selection of synced fields and stable cloud keys.
- Stable object identity independent of local SwiftData identifiers.
- Library-owned sync metadata, such as clocks and CloudKit system fields, stored
  outside adopter models.
- A library-defined record format, plus a custom record codec for adopters that
  must keep existing records. The codec is explicitly marked as failure-prone.
- Codable values with defined codecs, validation, and payload size limits.
- Independent fields and explicitly grouped fields for conflict resolution.
- Adopter-controlled creation of missing local objects.
- Durable receipt of remote state while local reconstruction is pending.
- Registered UserDefaults keys and custom storage adapters.
- Offline changes, retries, tombstones, cancellation, and account isolation.
- Observable delivery and reconstruction status for application UI.
- Migration of AniShelf without abandoning its existing cloud records.

The initial implementation does not include automatic relationship graph sync,
bulk asset transfer, public or shared CloudKit databases, non-CloudKit backends,
or automatic discovery of every UserDefaults key. It must not enable native
CloudKit mirroring on AniShelf's main SwiftData store.

## Existing extraction boundaries

These source locations provide the starting point, not a finished generic API:

| Existing component | Extraction direction |
| --- | --- |
| `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift` | Separate generic field representation from AniShelf identity, normalization, merge, and model application. |
| `DataProvider/Sources/LibrarySync/LibrarySettingsSyncSnapshot.swift` | Generalize registered settings values and their codecs. Preserve AniShelf's existing wire format during migration. |
| `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift` | Separate transport encoding from fixed container, zone, record types, and domain validation. |
| Importer, exporter, change-token store, and dirty queue in `LibrarySync` | Extract delivery and recovery mechanisms behind configurable contracts. |
| `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift` | Replace app-specific clock tracking with a documented SwiftData change-capture adapter. |
| `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator*.swift` | Separate orchestration from `LibraryStore`, bootstrap UI decisions, and metadata hydration. |
| `MyAnimeList/Sources/ViewModels/Library/LibraryPreferences.swift` | Move generic preferences mapping into an adapter; keep key selection and defaults in AniShelf. |
| `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift` | Existing transport protocol. Use it as the starting seam for the CloudKit transport. |
| `MyAnimeList/Sources/ViewModels/Library/LibrarySyncScheduler.swift` | Move debounce, backoff, and retry scheduling into the core. Keep trigger sources in the host app. |
| `MyAnimeList/Sources/ViewModels/Library/LibraryCloudSyncStateController.swift` and `LibraryCloudSyncStatus.swift` | Separate generic observable status from AniShelf's persisted UI state and copy. |
| `MyAnimeList/Sources/App/LibrarySyncNotificationBridge.swift` | Keep push registration in the host app. Expose a library entry point for "remote change notified". |
| `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator+BootstrapConflicts.swift` | Extract first-enable merging and user-directed conflict resolution as a core API. Keep the conflict UI in AniShelf. |
| `AnimeEntryDuplicateResolver` and `LibraryDuplicateRepair` | Keep duplicate repair in AniShelf. The SwiftData adapter needs a documented policy for several local rows with one identity. |

The `LibrarySync` target currently depends on `DataProvider`. The reusable core
must not depend on AniShelf models, TMDb, `LibraryStore`, or SwiftUI. AniShelf
should depend on the library and provide its domain-specific integration.

The current implementation has correctness defects that the package must not
carry into its public contract. Fix them first, following
[cloud-sync-correctness-fixes-plan.md](cloud-sync-correctness-fixes-plan.md).
Several of those fixes define invariants that the library must own for every
adopter.

## Proposed architecture

Use logical boundaries first; decide the final package and target layout during
implementation.

1. **Sync core:** schemas, identities, codecs, merge rules, durable incoming and
   outgoing work, retry state, and orchestration.
2. **CloudKit transport:** record encoding, fetch/send operations, server state,
   account events, and transport error classification.
3. **SwiftData adapter:** projection, durable change capture, lookup, insertion,
   application of selected fields, and deletion.
4. **UserDefaults adapter:** registered keys, typed reads and writes, local change
   detection, and reset semantics.
5. **Custom storage contract:** application-supplied read, apply, and change-reporting
   operations with documented durability requirements.
6. **Optional macros:** declarations that generate the same explicit schema used
   by the adapters.

The core should exchange immutable value snapshots across isolation boundaries.
SwiftData objects and contexts must remain within their owning actor or context.
Network reconstruction should return a transferable result that the storage
adapter can use when committing local changes.

## Adopter contract

### Identity and field schema

Each synced record declares a stable record type and an identity that resolves
to the same logical object on every device. AniShelf can retain its existing
domain-derived identities. Other adopters may use persisted UUIDs. Local
SwiftData persistent identifiers must not become cross-device record identities.

Each selected field declares:

- A stable cloud key and value codec.
- Validation and compatibility behavior.
- A conflict policy or membership in an atomic merge group.
- Its handling of absent values and explicit clearing.

Keys may initially default to property names, but published keys are part of the
wire contract. Renaming a Swift property must retain its old key or declare an
explicit migration. Registration must reject duplicate keys and incompatible
field definitions.

A field key does not imply one CloudKit record per field. Record layout and
merge granularity are separate decisions. Opaque Codable payloads merge as a
single value unless the adopter provides a finer-grained codec and merge policy.

### Responsibility boundary

The library owns every rule that affects correctness. Adopters declare policy
and supply domain operations.

| Owner | Responsibilities |
| --- | --- |
| Library | Change capture, sync clocks, CloudKit system fields, outgoing queue and acknowledgment, durable incoming queue and checkpoints, deterministic merging, preservation of unknown fields and records, transport, retry and throttling, account and zone lifecycle, and status. |
| Adopter | Record type, stable identity, synced fields and codecs, validation, field groups and merge primitives, reconstruction, delete semantics, and user-facing conflict and bootstrap UI. |
| AniShelf only | `LibraryEntryIdentity`, TMDb hydration, parent-series creation during season reconstruction, duplicate repair, and the compatibility codec for existing records. |

If an adopter can break a correctness rule by omitting a call, move that rule
into the library.

### Sync metadata ownership

Adopter models must not store sync metadata. The library stamps clocks from its
own change capture and stores them, with CloudKit system fields and the
last-known server record, in a library-owned metadata store. That store is
separate from the adopter's SwiftData container, so the library never adds
fields to adopter schemas or takes part in their migrations.

AniShelf currently breaks this rule. `AnimeEntry` stores `libraryUpdatedAt` and
`trackingUpdatedAt`, and app code must call `markLibraryModified` or
`markTrackingModified` for each user action. A missed call silently drops an
edit from sync. During migration:

1. Seed the library metadata store from the existing `AnimeEntry` clock fields.
2. Map the library's "library" and "tracking" group clocks to the existing
   record fields through AniShelf's compatibility codec, so older builds keep
   syncing.
3. Remove the clock fields and `mark*Modified` calls from the model in a later
   SwiftData schema version, after the metadata store is the only source of
   clocks.

### Merge primitives

The library provides a small set of merge primitives. Adopters assign one to
each field or field group:

- **Last-writer-wins value:** one clock for one field or an explicit group of
  fields. It supports an explicit clear that is distinct from "absent".
- **Map of last-writer-wins values:** one clock for each key, with a
  per-key clear. AniShelf's per-season episode progress uses this primitive.

Every primitive must converge under repeated and reordered delivery and must
break ties without depending on which side is local. Group membership is part
of the declared schema, so coupling such as a progress edit advancing the
tracking clock is visible rather than a side effect.

### SwiftData declarations

The desired convenience API lets adopters mark fields on a model. The following
is illustrative syntax, not an implemented or compiler-validated API:

```swift
@SyncModel(recordType: "Book", identity: \.syncID)
@Model
final class Book {
    var syncID: UUID

    @SyncField(key: "notes")
    var notes: String

    @SyncField(key: "favorite")
    var isFavorite: Bool

    var cachedDescription: String
}
```

Develop an explicit schema API using typed key paths before committing to this
syntax. Prototype macro composition with `@Model`, defaults, optional values,
and versioned schemas. Macros should generate registration and projection code;
they must not become the sole mechanism for noticing durable changes.

### Reconstruction

For a missing object, the adopter provides a reconstruction operation that takes
the stable identity and available synced state. It may fetch metadata or read
another local cache. The adapter then creates the local object and applies the
latest merged user state.

Reconstruction must distinguish successful materialization, retryable failure,
and an outcome that requires application action. Missing credentials or an
unavailable metadata service must not discard received user state. A permanently
unavailable source object must remain inspectable until the adopter explicitly
resolves it.

If an object already exists, apply only registered fields. Metadata refresh alone
must not enqueue an upload. Reconstructing a missing object must not upload
fetched metadata or reset newer user state to initializer defaults.

### UserDefaults

Adopters register an allowlist of keys, types, local defaults, and cloud keys.
Unregistered keys remain local. Define distinct behavior for an absent cloud
field, removal of a local key, an explicit reset, and any supported null value.
Registered fallback defaults must not silently become first-launch user edits.

Incoming writes must update the application's preferences without being recorded
as fresh local edits. The adapter needs reconciliation on restart as well as
change notifications while running. Account for callers that write through
ordinary UserDefaults APIs rather than a library-specific setter.

New schemas should support independent preference merges. AniShelf's existing
settings snapshot uses a shared timestamp, so changing that behavior requires a
separate compatibility decision rather than an incidental extraction change.

### Custom values

A custom adapter supplies identity, schema, reads, remote application, and a way
to report changes. A getter and setter alone are insufficient for reliable sync.
The adapter must either expose durable changes or allow the core to reconcile
against a persisted baseline. Document when a reported change becomes durable
and how retries avoid applying it twice.

Custom fields may supplement a SwiftData-backed record or form standalone
records. Registration must define ownership so that two adapters cannot silently
overwrite the same field. Atomic merge groups that span different local stores
require a recovery protocol; do not promise a cross-store transaction by default.

## Delivery and consistency requirements

### Separate cloud receipt from local reconstruction

Use a durable incoming queue, or equivalent persisted state, to separate these
steps:

1. Fetch and validate remote changes.
2. Persist the accepted remote payload and pending local work.
3. Advance the cloud fetch checkpoint only after that persistence succeeds.
4. Reconstruct missing objects and apply the latest merged state.
5. Save local changes, then acknowledge completion of the pending work.

If a crash occurs between steps, replay must be safe. Cloud receipt can succeed
while reconstruction remains pending; public status must distinguish the two.
Invalid or unsupported payloads must either block checkpoint advancement or be
durably retained with an actionable error. They must not be silently skipped.

During asynchronous reconstruction, more remote changes, local edits, or a
tombstone may arrive. Recheck the latest state and account scope before insertion.
A stale reconstruction result must not resurrect a deleted record or overwrite
newer user edits.

### Capture local changes durably

Saving application data and recording outgoing work must have a recoverable
boundary. A crash between those operations must not permanently lose an upload.
Evaluate SwiftData history with persisted checkpoints and deletion identity
retention. Notifications can wake processing, but an in-memory observer alone
does not establish recovery after termination or changes from another process.

Provide a reconciliation path if history becomes unavailable or its checkpoint
expires. Define how reconciliation handles deletions as well as surviving rows.
Remote application must not produce an upload loop, and suppression must not
hide unrelated local edits made while a remote operation is awaiting work.

### Merge and delete behavior

Support independent field merges and explicit groups for related values, such
as status and completion date. Conflict policies must converge under repeated
and reordered delivery. Define deterministic ties and the treatment of device
clock skew before selecting a default last-writer policy.

Keep AniShelf's grouping and episode-progress rules in its adapter during
extraction, as corrected by the correctness fixes plan. Generic field-level
merging is not permission to change the meaning of existing records.

When a merged local state differs from the record in the cloud, the device must
upload it. Clearing queued work because a remote clock is newer is not enough.
The remote record may be newer in one field group and older in another.

Tombstones must define delete-versus-edit and recreation behavior. Do not garbage
collect them on an arbitrary timer that allows an offline device to resurrect
deleted data. Finalize retention and recovery rules before enabling cleanup.

An outgoing acknowledgment may clear only the revision actually sent. If a user
edits a record while its upload is in flight, that newer edit must remain pending.

### Account scope, lifecycle, and status

Namespace durable state by container, account, zone, and local store where
appropriate. Switching accounts must stop stale work from applying or uploading
into the new scope. The adopter must explicitly decide whether existing local
data is retained, cleared, or offered for import into another account.

Expose cancellation, retryable and terminal failures, pending reconstruction,
and configuration problems. The host app owns permissions, entitlements,
background execution integration, and user-facing bootstrap choices. The library
must not require app-specific UI or assume that background execution is unlimited.

## Wire format and record codecs

The wire format is how a synced object looks when it is stored in CloudKit: its
record type, record name, field names, and where sync metadata such as clocks
lives. Other devices and older app versions read this format, so it is a
compatibility contract, separate from the adopter's Swift model.

### Library record format (default)

By default, the library defines the record format. Adopters declare which
fields to sync, and the library produces the record:

- Each synced field is stored under its declared cloud key.
- Sync metadata is stored under reserved keys with a library prefix, for
  example a format version, field or group clocks, and a deletion marker.
  Registration rejects adopter keys that use the reserved prefix.
- The library applies changes to the last-known server record rather than to a
  fresh record. Fields written by newer clients therefore survive an upload
  from an older client.
- The format carries a version. A client that meets a newer format keeps the
  record intact and reports it, without failing the rest of the sync.

Most adopters use only this format and never write CloudKit record code.

### Custom record codecs (failure-prone)

Some adopters already have CloudKit records in their own format, as AniShelf
does. Migrating those records would require a dual-write period and
coordination with app versions that are already released. For these adopters
the library offers a custom record codec that maps between the library's
record state and a `CKRecord`. Illustrative shape, not a committed API:

```swift
protocol SyncRecordCodec {
    /// Writes the library's state into an existing server record.
    func encode(_ state: SyncRecordState, into record: CKRecord) throws
    /// Reads identity, field values, clocks, and deletion state from a record.
    func decode(_ record: CKRecord) throws -> SyncRecordState
}
```

`SyncRecordState` holds the identity, field values, field or group clocks,
and deletion state. The codec controls only the mapping. Change capture,
queues, merging, transport, and lifecycle stay in the library.

A custom codec can break sync guarantees that the default format protects. The
library must present it as failure-prone:

- Make it an explicit opt-in, for example a separately imported SPI or a type
  name that marks it as unsafe, rather than a peer of the default path.
- Document each guarantee the codec must uphold:
  - Preserve fields it does not own.
  - Round-trip clocks exactly at CloudKit's stored precision.
  - Represent explicit clearing and deletion.
  - Reject records whose identity does not match the record name.
  - Tolerate newer record versions without failing the whole sync.
- Ship a conformance test suite that adopters run against their codec. It
  covers round trips, unknown-field preservation, clock precision, clearing,
  deletion, identity validation, and idempotent encoding.
- Keep checks that don't need the codec's cooperation in the library. For
  example, the library passes the server record to `encode` instead of a fresh
  record, and validates the decoded identity against the record name.

AniShelf is the first codec user. Its compatibility codec keeps the existing
`LibraryEntry` and `LibrarySettings` records, maps library group clocks to
`libraryUpdatedAt` and `trackingUpdatedAt`, and keeps the legacy
`customPosterURL` field. The settings payload codec must preserve keys that this
build doesn't know (see defect D6a in the correctness fixes plan).

## CloudKit compatibility and transport

First extract behavior while preserving AniShelf's container, zone, record names,
record types, field keys, codecs, tombstones, legacy decoding, and merge rules,
through AniShelf's compatibility codec. Do not require users to erase cloud data
or reconstruct it through a full re-upload merely to adopt the package.

Inventory persisted local state as well as cloud records:

- Change tokens in UserDefaults under `AniShelf.LibrarySync.ChangeToken.*`.
- The pending-upload queue at
  `Application Support/AniShelf/Sync/library-entry-sync-dirty-queue.json`.
- The settings clock `libraryCloudSyncedDefaultsUpdatedAt`.
- Sync status keys under `LibraryCloudSync*`, including the completed scope,
  bootstrap state, restoration failures, and the reconciled settings clock.
- The clock fields on `AnimeEntry`.

The transport must also handle:

- Conflicting server writes, by storing CloudKit system fields and saving with a
  change-tag check. The current transport overwrites records without a check.
- Zone deletion and reset (`userDeletedZone`, `zoneNotFound`). It must not
  silently recreate an empty zone.
- `retryAfterSeconds`, `requestRateLimited`, `zoneBusy`, and `quotaExceeded`.
- Records it cannot decode. Quarantine them durably so they don't stop the rest
  of the sync, including uploads.

Evaluate `CKSyncEngine` against the existing transport in a separate spike. Assess
state persistence, account events, retries, cancellation, conflict handling, and
compatibility with existing records. Do not combine transport replacement and
wire-format changes in the initial extraction.

Any new wire representation needs a versioned rollout plan that explains how
older clients coexist with newer clients. Receiving a schema that a client does
not understand must not let that client erase unknown fields during an upload.

## Implementation plan

All stages below are pending. Complete each stage's exit criteria before treating
its behavior as available to adopters.

Prerequisite: complete the
[correctness fixes plan](cloud-sync-correctness-fixes-plan.md). Characterization
tests written for those fixes become compatibility fixtures for Stage 5. The
package's queue, change capture, zone lifecycle, and settings adapter must
address the defects listed there under "Deferred".

### Stage 1: Inventory contracts and prototype integration

- [ ] Map domain dependencies, record formats, persisted state, and existing tests.
- [ ] Specify identity, field, merge-primitive, adapter, and reconstruction contracts.
- [ ] Specify the library record format and the custom record codec contract.
- [ ] Prototype the library-owned metadata store and clock stamping from change capture.
- [ ] Sketch a small second domain that doesn't use AniShelf, to test the API
  against more than one adopter early.
- [ ] Prototype explicit SwiftData schema registration and change recovery.
- [ ] Probe macro composition separately to establish feasible declaration syntax.
- [ ] Record the supported platform floor and the transport-spike result.

Exit criteria: A small model demonstrates selective projection and reconstruction;
the change-capture approach has a documented crash-recovery boundary. Unresolved
API and compatibility choices are recorded before extraction begins.

### Stage 2: Extract the core and CloudKit boundary

- [ ] Introduce generic schemas, transport contracts, and durable work storage.
- [ ] Extract retry, cancellation, merge, acknowledgment, and account scoping.
- [ ] Implement the library record format and the opt-in custom codec path.
- [ ] Ship the codec conformance test suite.
- [ ] Keep AniShelf codecs and domain rules in a compatibility adapter that
  passes the conformance suite.
- [ ] Establish durable receipt before advancing cloud checkpoints.

Exit criteria: The core builds without AniShelf or SwiftData dependencies, and
focused tests demonstrate replay and preservation of edits during upload.

### Stage 3: Implement SwiftData and reconstruction support

- [ ] Add projection, lookup, local apply, deletion, and durable change capture.
- [ ] Add reconstruction scheduling, retries, and actionable blocked states.
- [ ] Handle concurrent edits and tombstones during reconstruction.
- [ ] Preserve context isolation and prevent remote-apply feedback loops.

Exit criteria: A fresh local store reconstructs an object from selected cloud
state; reconstruction survives interruption without losing or duplicating data.
Metadata-only changes produce no outgoing user-state change.

### Stage 4: Implement preferences and custom storage adapters

- [ ] Add typed UserDefaults registration and restart reconciliation.
- [ ] Define and implement missing, removal, and reset semantics.
- [ ] Add custom standalone records and supplemental custom fields.
- [ ] Document cross-store recovery limits and ownership validation.

Exit criteria: Both adapters operate through the same core, preserve unsent edits,
and apply remote changes without echoing them as new local changes.

### Stage 5: Migrate AniShelf and verify compatibility

- [ ] Replace app-specific infrastructure with the adapters in bounded steps.
- [ ] Keep identity, TMDb hydration, normalization, and UI policy in AniShelf.
- [ ] Migrate local sync state through a documented recoverable transition.
- [ ] Seed the library metadata store from `AnimeEntry` clocks, then remove the
  clock fields and `mark*Modified` calls in a later SwiftData schema version.
- [ ] Verify existing record fixtures, legacy decoding, and bootstrap behavior.
- [ ] Run focused tests and applicable simulator runtime checks.

Exit criteria: AniShelf uses the library without changing its existing cloud
contract, and its metadata remains local. Document operational rollback limits
before any separately authorized release.

### Stage 6: Add declaration conveniences and adoption documentation

- [ ] Add macros that generate the established explicit schema API.
- [ ] Diagnose duplicate keys and unsupported declarations at registration or build time.
- [ ] Complete the second domain example from Stage 1, covering reconstruction,
  defaults, and custom values without importing AniShelf.
- [ ] Document the custom record codec as failure-prone, including its
  guarantees and the conformance suite.
- [ ] Document setup, lifecycle integration, schema evolution, and failure handling.

Exit criteria: The second example demonstrates that the API is reusable, and
adopters can use the explicit schema API without macros.

## Validation strategy

Reuse existing sync tests where they protect the same behavior. Add focused tests
for distinct generic-library risks:

- Selected-field round trips and exclusion of reconstructible metadata.
- Stable keys across a local property rename and preservation of unknown fields.
- Deterministic conflict resolution, atomic groups, and explicit clearing.
- Crash recovery around local save, queue persistence, checkpointing, and apply.
- Missing-object reconstruction failure, restart, retry, and eventual success.
- A newer edit or tombstone arriving while reconstruction or upload is in flight.
- Account changes with pending work from the previous account.
- UserDefaults reset, first-launch defaults, and remote-apply echo prevention.
- Custom-adapter replay and ownership conflicts.
- Compatibility with AniShelf's existing record and persisted-state fixtures.
- Custom codec conformance: unknown-field preservation, clock precision,
  clearing, deletion, and identity validation.
- Upload of merged state that differs from the cloud record, without an upload loop.
- Zone deletion and quarantine of records that fail to decode.

Use the repository Makefile and the smallest relevant test filters first. Run
broader simulator validation when integration scope warrants it. Use an already
booted simulator; obtain explicit permission before booting another. This plan
does not authorize cloud writes, publication, or source-control actions. Live
multi-device CloudKit checks require separate authorization for their remote
writes and must distinguish delivery from completed local reconstruction.

## Decisions to resolve before API stabilization

- Package name, module layout, and deployment targets.
- Explicit schema syntax and supported `@Model` macro composition.
- Change-history checkpointing, deletion identity retention, and reconciliation.
- Durable incoming/outgoing storage and recovery across separate local stores.
- Default conflict ordering, clock-skew handling, and merge-group representation.
- Reconstruction result types, retry controls, and unresolved-object presentation.
- Codec limits, custom-value encoding, and asset support after the initial scope.
- Tombstone retention and explicit recreation semantics.
- Whether to retain the current CloudKit transport or adopt `CKSyncEngine` later.
- Reserved key prefix and version marker for the library record format.
- How the custom codec is opted into (separate SPI import or unsafe type name),
  and the final `SyncRecordState` shape.
- Storage technology and location for the library metadata store.

## References

- [Cloud sync correctness fixes plan](cloud-sync-correctness-fixes-plan.md)
- [Existing AniShelf CloudKit implementation plan](implemented/cloudkit-sync-implementation-plan.md)
- [Apple: Track model changes with SwiftData history](https://developer.apple.com/videos/play/wwdc2024/10075/)
- [Apple: CloudKit sync engine sample](https://github.com/apple/sample-cloudkit-sync-engine)
