# Cloud sync correctness fixes: defects and preliminary fixes

Created: 2026-09-27

Status: Phase 1/2 fixes implemented locally in commits `2993234` and `f8cb058`.
The V1 precision check was completed on 2026-09-27.

## Purpose

An audit of the current iCloud library sync found defects that can lose user
edits, leave devices permanently different, or stop sync entirely. This plan
describes each defect, how to trigger it, and a preliminary fix that keeps
AniShelf's existing CloudKit records compatible.

These fixes come before the reusable package work in
[selective-cloud-sync-library-plan.md](selective-cloud-sync-library-plan.md).
The package must not carry these defects into its public contract. Each fix is
labeled with where its rule belongs after extraction:

- **Library invariant:** the reusable package must guarantee this for every
  adopter.
- **AniShelf policy:** AniShelf's merge and field choices, which later live in
  AniShelf's adapter.

## Constraints

- Keep the current wire format: container, zone, record types, record names,
  field keys, and tombstone shape. Builds that are already released must keep
  syncing with fixed builds.
- Treat older released builds as permanent participants. A fix may make a new
  build behave better, but it cannot change what an old build does.
- Do not require users to erase iCloud data or re-enable sync.
- Follow the repository testing rules: add the smallest failing test for each
  defect, and run focused filters before broad simulator validation.

## Summary

| ID | Defect | Impact | Owner after extraction | Phase |
| --- | --- | --- | --- | --- |
| V1 | CloudKit date precision (resolved) | Tested submillisecond dates survived a development-container save and fetch unchanged | Library invariant | 1 |
| D1 | Queue reconciliation drops unsynced edits from another field group | Lost edit, permanent divergence | Library invariant | 1 |
| D2 | Uploads overwrite the cloud record without a conflict check | Cloud regression until a fixed build repairs it | Library invariant | 1 (mitigated by D1) |
| D3 | Merge ties depend on argument order | Devices can disagree forever | Library invariant | 1 |
| D7 | One bad record or failed hydration blocks the whole pass, including uploads | Sync stops | Library invariant | 2 |
| D6a | Settings decoding rejects unknown value types | Sync stops on older builds | Library invariant | 2 |
| D11 | Retry skips import-only failures and ignores CloudKit's retry-after | Slow recovery, throttling | Library invariant | 2 |

## Phase 1: Convergence

Ship V1, D3, and D1 together. D1's repair rule makes a device upload whenever
its merged state differs from the cloud. That is safe only when three
conditions hold. Otherwise two devices can keep uploading forever.

- Every device merges the same inputs into the same result (D3).
- The local row ends up equal to the merged result (D3, apply path).
- Clocks survive a CloudKit round trip unchanged (V1).

Merging, local application, and queue reconciliation must share one comparison
rule. Test the end state on two simulated devices, not only merge symmetry.

### V1: CloudKit date precision — resolved

Entry clocks travel as CloudKit `Date` fields (`libraryUpdatedAt`,
`trackingUpdatedAt`, `dateSaved`). The concern was that CloudKit might truncate
them to milliseconds, making a device treat its own upload as different on the
next fetch and repeatedly enqueue a D1 repair.

**Observed result (2026-09-27).** An authorized probe on the booted iPhone 18
Pro simulator saved and separately fetched a temporary `LibraryEntry` record in
the default zone of AniShelf's CloudKit development private database. The
`dateSaved`, `libraryUpdatedAt`, and `trackingUpdatedAt` fields were written
with fractional seconds `.123456`, `.654321`, and `.987654`, respectively.
Each fetched `Date` matched the value written with a measured difference of
0 microseconds. The temporary record was deleted. The probe ran twice because
Xcode suppressed the first run's printed measurements; both runs completed
cleanup.

This resolves the suspected millisecond truncation for the tested CloudKit
path. It does not assert identical precision in every environment. The fixed
build still normalizes comparison clocks to milliseconds and stamps monotonic
millisecond clocks. D3's tie-break handles ties these rules can create.

### D1: Queue reconciliation drops unsynced edits

**Current behavior.** `reconcileDirtyQueue`
([LibrarySyncCoordinator+DirtyQueue.swift](../MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator+DirtyQueue.swift))
removes a pending upsert when the incoming change's `latestSyncClock` is newer
than the upsert's `dirtyAt`. `latestSyncClock` is the newest clock across *all*
field groups, and the incoming change is the already-merged snapshot.

**Failure scenario.**

1. Device A edits notes at t=10, so `trackingUpdatedAt` = 10 and the queue holds
   an upsert with `dirtyAt` = 10. A is offline.
2. Device B hides the entry at t=20 through `updateDisplayState`, which advances
   only `libraryUpdatedAt`, and uploads. The cloud still holds the old tracking
   fields.
3. A syncs. The merge takes library fields from B and tracking fields from A.
   The merged `latestSyncClock` is 20, which is greater than 10, so A drops its
   queued upsert.
4. A shows the new notes. B and the cloud never receive them.

No existing test covers this scenario.

**Preliminary fix.** Replace the clock comparison with a state comparison:

- After applying an import, compare each identity's merged local snapshot with
  the decoded remote record (`batch.remoteChanges`, which holds the change before
  merging).
- If they differ in any field group, keep or enqueue an upsert.
- Drop a queued upsert only when the remote record already contains everything
  the local snapshot has.
- Compare field values and clocks only, and exclude `schemaVersion`. A record
  written at schema version 1 would otherwise always look different.
- Clock comparison follows V1.

**Side effect: this mitigates D2.** A fixed build that holds newer state
re-uploads once it fetches a regressed record. Builds that are already released
keep the current behavior and do not repair records (see D2).

**Tests.** Add one coordinator test that reproduces the scenario above in
`LibrarySyncCoordinatorTests+RemoteChanges.swift`. Add one test that confirms
applying a record identical to local state does not enqueue an upload, so the
fix cannot loop.

### D2: Uploads overwrite the cloud record without a conflict check

**Current behavior.** `CloudLibrarySyncLiveDatabase.save(records:)` builds each
`CKRecord` from scratch and saves it with `.allKeys`
([CloudLibrarySyncDatabase.swift](../DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift)).
CloudKit performs no change-tag check. If device B uploads between device A's
fetch and A's upload, A's upload replaces B's newer fields in the cloud.

**Preliminary mitigation.** D1's repair rule gives eventual repair, not a
guarantee:

- The overwrite changes the record, so B fetches it. If B runs a fixed build,
  it finds a difference, queues an upsert, and uploads again. The queued upsert
  counts as pending local work, so the scheduler also retries it after a failure.
- If the newer state exists only on a released build, nothing repairs the
  record. The regression remains until someone edits that entry again.

Keep `.allKeys` for now. Add one test in which another device uploads between
this device's fetch and its upload, and confirm that a fixed build repairs the
record on its next pass.

**Deferred fix (library).** Store each record's CloudKit system fields, save
with `.ifServerRecordUnchanged`, and handle `serverRecordChanged` by merging
with the returned server record and retrying. This needs a per-record metadata
store, which the reusable package introduces. Do not build it in the app first.
This is the fix that prevents the regression. D1 only repairs it afterward.

### D3: Merge ties depend on argument order

**Current behavior.** With equal clocks, each rule keeps whichever side it
treats as `self` or "local":

- `LibraryEntrySyncSnapshot.merged(with:)` compares with a strict `>` and keeps
  `self` on ties.
- `LibraryEntrySyncRemoteChange.merged(with:)` returns the snapshot for
  `(snapshot, tombstone)` and the tombstone for `(tombstone, snapshot)` when the
  clocks are equal.
- `AnimeEntry.applySyncTombstone` keeps the local entry on a tie.
  `isNotNewerThanPendingDelete` lets the pending delete win on a tie.

Two devices with equal clocks can each keep their own value forever. The fixed
build's millisecond clock normalization makes deterministic tie handling
necessary even though the V1 probe found no CloudKit truncation.

**Preliminary fix.** Define one rule for each comparison and use it everywhere:

- **Snapshot against snapshot, equal group clock:** keep the side whose
  field-group values have the greater canonical encoding (sorted-key JSON of
  that group's fields). The rule is symmetric and needs no device identifier.
  Episode progress already breaks ties by the higher episode number. Keep that
  rule.
- **Snapshot against tombstone, equal clock:** the live snapshot wins, because
  losing data is worse than keeping a deleted entry. Apply this rule in
  `merged(with:)` for both argument orders, in `applySyncTombstone`, in
  `isNotNewerThanPendingDelete`, and in queue reconciliation.

**Apply path.** A symmetric merge is not enough on its own.
`AnimeEntry.applySyncSnapshot` updates a field group only when the incoming
clock is strictly newer. When a tie-break selects the remote group, the clocks
are equal, so that group never reaches the local row, and the device keeps its
own values while its peer switches. The import already computes the merged
snapshot from local and remote state. Apply that snapshot's group values
wherever they differ from the local row, instead of re-checking clocks during
application. `applySyncTombstone` must use the same tie rule as `merged(with:)`.

**Tests.**

- Add merge property tests in `DataProvider/Tests/LibrarySyncTests`:
  `a.merged(b) == b.merged(a)` for tie cases, covering snapshots and tombstones.
- Add one end-state test with two simulated devices that hold equal-clock,
  different values. After each device imports the other's record, both local
  rows must be equal, and neither device may queue another upload.

## Phase 2: Keep sync running

### D7: One failure blocks the whole pass, including uploads

**Current behavior.**

- `CloudLibrarySyncImporter.fetchChanges` rethrows the first decoding error. The
  pass fails and the change token never advances, so the same record fails on
  every later pass.
- A record from a newer build with a higher `schemaVersion` fails decoding in
  the same way. One newer device therefore stops every older device's sync.
- Outside bootstrap, a hydration failure (for example, a TMDb outage or a title
  removed from TMDb) makes `applyImportedChanges` throw.
- Export runs only after a successful import, so all three cases also stop
  uploads.

**Preliminary fix.**

1. **Quarantine undecodable records.** Decode each record separately. For a
   failure, persist the record name, record type, schema version, and error in
   a quarantine store, then continue. Commit the token only after the quarantine
   entries are saved. When the app version changes, fetch quarantined records by
   ID and try again. Show a count in sync status, so the problem is visible
   without being skipped silently.
2. **Keep failed reconstructions.** When hydration fails during ordinary sync,
   save the remote snapshot to a pending-reconstruction store before committing
   the token, then retry it on later passes. Reuse the restoration-failure shape
   that bootstrap already records. If the user later adds the same title
   locally, merge the pending snapshot into the new entry.
3. **Upload even when import fails.** When import fails for a reason other than
   network or account errors, still run export for queued entries whose identity
   is not affected by the failure.
4. **Never upload over a record this build cannot read.** The exporter builds a
   fresh record from local fields. For a quarantined identity, that upload
   would overwrite newer data and write back an older `schemaVersion`. Keep
   quarantined identities, and any identity last seen with a higher schema
   version, in the quarantine store. Skip their queued uploads, leaving them
   queued, until the record decodes and merges. Show those identities in sync
   status.

**Tests.**

- Add one importer test in which a bad record sits next to a good one. The good
  record must apply, the token must advance, and the quarantine entry must
  persist.
- In the same scenario, queue a local upsert for the quarantined identity.
  Export must skip it and keep it queued.
- Add one coordinator test in which a hydration failure still lets queued local
  edits upload.

### D6a: Settings decoding rejects unknown value types

**Current behavior.** `LibrarySettingsSyncSnapshot.Value` decodes only `Bool`,
`String`, and `[String]`. A future setting with another type, such as a number,
makes the whole payload fail with `corruptSettingsPayload`. Under D7 that stops
sync on every older build.

**Preliminary fix.** Decode the payload one key at a time. Keep values of
unknown types as raw JSON that is never applied locally. Preserving those
values on upload is deferred (see D6a part 2 under Deferred). Ship this before
any new setting type is added.

### D11: The retry policy misses cases

**Current behavior.** `LibrarySyncScheduler` schedules automatic retries only
when local work is pending, so a failed import retries only on the next trigger.
It uses fixed intervals and ignores `CKError.retryAfterSeconds`. It does not
classify `quotaExceeded`, `requestRateLimited`, or `zoneBusy`.

**Preliminary fix.**

- Schedule retries after import failures as well.
- When CloudKit returns a retry-after value, wait at least that long.
- Classify `quotaExceeded` as needing user action and show it in sync status.

## Deferred

The following defects are confirmed but out of scope for this plan. They either
require product decisions or belong to code that the reusable package replaces.
Revisit them when planning the package's queue, change capture, and settings
adapter, or when making the product decisions.

| ID | Defect | Reason for deferral |
| --- | --- | --- |
| D8 | A crash between the SwiftData save and the queue write loses the upload. The recorder rebuilds its baseline from the store at launch. | Replaced by the package's history-based change capture. |
| D9 | An unreadable or version-mismatched queue file is silently reset, which loses pending edits after a downgrade. User deletes remove the row, so a pending delete that exists only in the queue cannot be recovered. | Replaced by the package's durable queue. |
| D10 | A deleted or reset CloudKit zone is recreated empty, with no re-upload. `ensureZone` runs before any detection could happen. | Replaced by the package's zone lifecycle handling. Needs a user-facing prompt. |
| D4 | Episode progress edits advance the tracking clock, so a progress edit overwrites a concurrent notes or status edit. | Product decision on field grouping. |
| D5 | Clearing episode progress does not sync, and cleared progress comes back. | Product decision. Needs a zero-valued progress row that keeps its clock. |
| D6a (part 2) | Settings export erases keys that this build does not know. | Belongs to the package's settings adapter. Released builds keep erasing them regardless. |
| D6b | Settings upload on every successful pass. | Low impact. Fix with the settings adapter. |

## Open questions

- D3: confirm that a live snapshot should win over a tombstone with an equal
  clock.

## Validation

Use the Makefile and the smallest relevant filter first, for example:

- `make test-dataprovider DATAPROVIDER_TEST_FILTER='LibrarySyncTests'`
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySyncCoordinatorTests'`

Use an already booted simulator and ask before booting one. Checks that write to
CloudKit, including V1 and any multi-device verification, need separate
authorization.
