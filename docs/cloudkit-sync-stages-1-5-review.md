# CloudKit Sync Stages 1–5 — Comprehensive Review

**Review Date:** 2026-06-02  
**Branch:** `feat/cloudkit-sync`  
**Scope:** Stages 1–5 (completed) per `docs/cloudkit-sync-implementation-plan.md`  
**Method:** Six parallel subagent reviews from independent perspectives (Data Consistency, Error Handling, Concurrency, CloudKit Integration, Test Coverage, Architecture), followed by manual code verification of every claimed issue. Corrected on 2026-06-02 after an additional scope pass against `docs/cloudkit-sync-implementation-plan.md`.

---

## Executive Summary

The implementation of Stages 1–5 is **architecturally sound and largely well-tested**, with strong adherence to the plan's core guardrails. The deterministic sync identity, tombstone-based delete handling, import-before-export sequencing, and recorder suppression are all correctly implemented.

No confirmed critical Stage 1–5 correctness issue remains after narrowing the earlier dirty-queue/tombstone concern to a naming and API-clarity problem rather than a demonstrated runtime data-loss bug. Several other findings are valid hardening or rollout-policy concerns, but they should not be counted as Stage 1–5 blockers because the staged plan explicitly leaves settings, restore policy, and manual validation to Stages 6–8.

| Severity | Count | Themes |
|----------|-------|--------|
| **🔴 Critical** | 0 | None confirmed |
| **🟡 Stage 1–5 Warning** | 8 | Retry behavior, token commit ordering, setup hardening, test gaps |
| **⚪ Out of Stage 1–5 Scope** | 5 | Account-change policy, restore recovery, rate/quota UX, rollout settings |
| **🟢 Positive** | 10 | Strong architecture, good test coverage on core logic, correct sequencing |

---

## 🟡 Valid Stage 1–5 Warning Issues

### WARN-2: TMDb API Key Guard Missing from Coordinator

**File:** `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift:277-308`  
**Status:** Partially valid

The plan states that app sync requests happen "when the TMDb API key is available." Launch, foreground, and CloudKit notification triggers are guarded at the app layer, but the coordinator and scheduler themselves do not have a key gate. `hydrateMissingEntry` calls `store.infoFetcher.latestInfo(...)`, and `InfoFetcher` can be constructed with an empty key. Without a key:
- Hydration fails for any missing remote entry
- The entire `apply()` phase throws
- The token is never advanced
- A local dirty-queue scheduler path can still trigger retries

**Fix:** Either enforce TMDb key availability in the sync scheduler/coordinator boundary, or make hydration gracefully defer missing rows when the key is unavailable.

---

### WARN-3: Scheduler Retries Without Distinguishing Recoverable vs. Permanent Failures

**File:** `MyAnimeList/Sources/ViewModels/Library/LibrarySyncScheduler.swift:70-78`  
**Status:** Confirmed valid

```swift
private func scheduleFailureRetryIfNeeded() {
    guard hasPendingDirtyWork(), !failureRetryIntervals.isEmpty else { return }
    let retryDelay = failureRetryIntervals[min(failureRetryAttempt, failureRetryIntervals.count - 1)]
    failureRetryAttempt += 1
    // ... schedules retry
}
```

Any failure triggers retry with backoff. If the failure is "no iCloud account" or another permanent failure, the scheduler keeps retrying while dirty work remains. Retries are **not** capped at 4; the code clamps to the last interval after the fourth failure and continues retrying indefinitely.

**Fix:** Distinguish transient failures (network, rate limit) from permanent failures (no account, disabled) in the coordinator's error reporting, and skip retries for permanent conditions.

---

### WARN-5: Pagination Loop Has No Page Limit

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncImporter.swift:148-168`  
**Status:** Valid low-probability hardening

```swift
repeat {
    let batch = try await database.fetchRecordZoneChanges(...)
    // ...
    if !batch.moreComing { break }
} while true
```

No maximum page count, timeout, or record limit. A buggy CloudKit response could set `moreComing = true` indefinitely.

**Fix:** Add a `maxPages` guard (e.g., 100) and throw if exceeded.

---

### WARN-6: `serverRejectedRequest` Treated as "Already Exists"

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift:232-235`  
**Status:** Confirmed valid

```swift
fileprivate var isCloudLibrarySyncAlreadyExists: Bool {
    guard let ckError = self as? CKError else { return false }
    return ckError.code == .serverRejectedRequest || ckError.code == .constraintViolation
}
```

`.serverRejectedRequest` is a broad error code that can indicate many problems beyond "already exists." Treating it as success could mask real configuration errors during zone or subscription creation.

**Fix:** Only treat `.constraintViolation` and `.serverRejectedRequest` with the specific "already exists" reason as success, or log and inspect the error details.

---

### WARN-7: Token Commit Blocked by UI Refresh Failure

**File:** `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift:185-189`  
**Status:** Confirmed valid

```swift
currentPhase = .hydrationApply
_ = try await apply(importBatch, to: store)   // includes refreshLibrary()

currentPhase = .tokenCommit
importer.commit(importBatch)                   // ← only reached if apply() succeeds
```

Inside `apply()`:
```swift
try store.repository.save()        // local data persisted
store.rebuildSyncChangeTracking()  // in-memory baseline update
try store.refreshLibrary()         // UI refresh — could throw
```

If `refreshLibrary()` throws (e.g., UI state inconsistency), `apply()` throws, and the token is **not committed**. The local data has already been saved. On the next sync, the same remote changes are re-fetched and re-applied (idempotent, but wasteful). If `refreshLibrary()` consistently throws, the token never advances.

**Fix:** Commit the token after successful `repository.save()`, not after UI refresh.

---

## ⚪ Out-of-Scope / Rollout-Stage Findings

These findings are legitimate rollout hardening concerns, but the staged plan assigns settings, restore policy, and manual two-device validation to Stages 6–8. They should not be treated as Stage 1–5 correctness bugs.

### WARN-4: No `CKAccountChanged` Observer

**File:** Missing  
**Status:** Out of scope for Stages 1–5; valid Stage 6–8 policy gap

No `CKAccountChanged` observer exists. That is a real account-transition policy gap for rollout. However, the token-leakage risk is overstated because token namespaces include the current CloudKit account identifier resolved from `userRecordID()`. The unresolved question is what to do with local dirty work and tokens when the account changes, which belongs with the pending Stage 6 settings/rollout and Stage 7 restore/reset policy.

**Fix:** Define account-change policy during rollout work, then observe `NSNotification.Name.CKAccountChanged` and apply that policy.

### WARN-8: Partial Failure Details Discarded on Save

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift:143-153`  
**Status:** Valid limitation; out of Stage 1–5 scope

```swift
catch {
    guard let ckError = error as? CKError,
          ckError.code == .partialFailure,
          let partialErrors = ckError.partialErrorsByItemID
    else { throw error }
    let failedIDs = Set(partialErrors.keys.compactMap { $0 as? CKRecord.ID })
    return records.map(\.recordID).filter { !failedIDs.contains($0) }
}
```

Per-record failure reasons (`limitExceeded`, `quotaExceeded`, `notAuthenticated`, etc.) are discarded. The exporter cannot make intelligent retry decisions. This is not a Stage 1–5 correctness bug because the implemented plan only requires accepted records to be dequeued and partial failures to remain queued for retry.

**Fix:** Surface per-record error details through the `CloudLibrarySyncDatabase` protocol.

---

### WARN-9: No Handling of `zoneNotFound` / `userDeletedZone` During Fetch

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncImporter.swift`  
**Status:** Valid Stage 7/8 hardening; out of Stage 1–5 scope

If the user deletes the app's iCloud data (wiping the zone), `fetchRecordZoneChanges` returns `zoneNotFound` or `userDeletedZone`. The importer does not handle these specifically — they propagate as generic errors. Correct behavior would be:
- Reset the change token
- Re-create the zone
- Re-upload all local data (full sync)

The staged plan leaves restore/reset policy pending. Do not treat this as a Stage 1–5 defect until that policy exists.

**Fix:** Add specific error handling for zone deletion scenarios as part of the explicit restore/reset policy.

---

### WARN-10: No Rate Limit / Quota Handling

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift`  
**Status:** Valid rollout hardening; out of Stage 1–5 scope

CloudKit can return `.rateLimited`, `.requestRateLimited`, or `.quotaExceeded`. None of these are handled specifically.

Stage 6 owns degraded status and user-facing setup state. Stage 1–5 can reasonably propagate these errors as sync failure.

**Fix:** Add exponential backoff for rate limits and user-facing messaging for quota exceeded during rollout/status work.

---

### WARN-11: `containerIdentifier` Falls Back to `Bundle.main.bundleIdentifier`

**File:** `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift:41-43`  
**Status:** Mostly overstated; test/custom-client cleanup

```swift
public var containerIdentifier: String? {
    container?.containerIdentifier ?? Bundle.main.bundleIdentifier
}
```

When `container` is nil (tests), this falls back to the app's bundle identifier. In the live async path, `changeTokenNamespace()` returns `nil` when there is no container, so this is not an app Stage 1–5 bug. It is a cleanup concern for manually constructed namespaces in tests or custom client usage.

**Fix:** Consider returning `nil` when `container` is nil and keeping test namespaces explicit.

---

## 🟡 Additional Valid Stage 1–5 Warning Issues

### WARN-12: Combine Publisher for `didSave` Not `@MainActor`-Isolated

**File:** `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift:287-294`  
**Status:** Valid under strict concurrency

```swift
private func observeSaves() {
    notificationCenter
        .publisher(for: ModelContext.didSave)
        .sink { [weak self] notification in
            self?.processSaveNotification(notification)  // ← no @MainActor dispatch
        }
        .store(in: &cancellables)
}
```

Under **Swift 6 strict concurrency checking**, calling a `@MainActor` method from a non-isolated closure is a compile error. Under current relaxed mode, SwiftData's `mainContext` posts on the main thread, so this works in practice. However, it is a latent migration risk.

**Fix:** Wrap the sink body in `Task { @MainActor [weak self] in ... }`.

---

### WARN-13: Brittle Timing in Scheduler Tests

**File:** `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`  
**Status:** Confirmed valid

`dirtyQueueSchedulerDebouncesLocalChanges` and `dirtyQueueSchedulerBacksOffAfterFailure` use hardcoded nanosecond sleeps (`20_000_000`, `30_000_000`, etc.). These are inherently flaky on slow CI runners.

**Fix:** Inject a controllable clock or use `Clock` protocol conformance.

---

### WARN-14: No Test for Partial Export Failure in Coordinator

**File:** `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`  
**Status:** Confirmed valid, with lower-level coverage caveat

No test simulates a scenario where the exporter saves 2 of 3 records and verifies that:
- The 2 successful identities are removed from the dirty queue
- The 1 failed identity remains queued

`CloudLibrarySyncExporter` has lower-level partial-success coverage, but the coordinator's dirty-queue removal behavior after a partial export is not directly tested.

**Fix:** Add a test with a fake database that reports partial success.

---

## ⚠️ Partial / Overstated Findings

These findings contain some truth but were overstated in severity or description by the review subagents:

| # | Original Claim | Reality | Verdict |
|---|---------------|---------|---------|
| CRIT-2 | Hydration failure leaves orphaned parent series entries because child `insert` can throw after parent `insert` | The exact claim is wrong: `repository.insert(_:)` is non-throwing and the throwing boundary is the later save/apply phase. The broader cleanup/idempotence concern is still worth testing if staged hydrated inserts are saved after a later failure. | Downgraded / Partial |
| P-1 | `processSaveNotification` "silently drops" errors | Errors are logged; baseline is rolled back for retry on next notification. Reasonable for a notification handler. | Overstated |
| P-2 | Disabled database doesn't distinguish error types | Partly true for disabled/test plumbing. The original rationale was wrong because scheduler retries are not bounded; they repeat at the last interval while dirty work remains. | Partial |
| P-3 | Episode progress JSON blob prevents field-level merge | Design trade-off for current scale. Acceptable for typical anime (1-5 seasons). | Trade-off |
| P-4 | `episodeProgresses` could exceed CloudKit record size | Theoretical. 1MB record limit is far away for typical episode progress data. | Theoretical |
| P-5 | `.allKeys` save policy causes silent overwrite of concurrent changes | Intentional for full-snapshot-replacement model. Conflict resolution happens at merge layer. | By design |
| P-6 | No account status check before sync | Error is caught and returns false. Missing error categorization, not missing handling. | Partial |
| P-7 | Export "poison pill" — repeated failures never escalate | Valid. Retries are not capped; they repeat indefinitely at the last configured interval while dirty work remains. | Promoted to WARN-3 |

---

## ❌ Invalidated Findings

These findings were **incorrect** upon manual verification:

| # | Original Claim | Why Invalid |
|---|---------------|-------------|
| INV-1 | `applyInitialSyncSnapshot` nil clocks cause baseline problems | Hydrated entries get nil clocks until next local edit, which then sets clocks. Baseline is rebuilt after apply. Safe. |
| INV-2 | `rebuildSyncChangeTracking()` and `refreshLibrary()` outside suppression block cause spurious enqueue | `rebuildSyncChangeTracking()` only updates in-memory dictionary. `refreshLibrary()` only fetches and assigns to `@Published`. Neither triggers saves. |
| INV-3 | `withSuppressedRecordingAsync` suppression depth not restored on throw | Swift `defer` runs on **all** exit paths including throws. Correct by design. |
| INV-4 | `isSyncing` flag race without await boundary | `@MainActor` serializes all accesses. Safe. |
| INV-5 | `NSLock` re-entrancy deadlock in dirty queue store | Call graph audit confirms no re-entrant `withLock` calls. Safe. |
| INV-6 | No test for `restoreDeleteRecords` bulk-delete rollback | Stale. `testLibrarySyncRecorderRestoreDeleteRecordsRewritesPriorQueueOnce` covers the rollback rewrite. |

---

## ✅ Verified Positive Findings

All 10 architectural strengths identified by the review subagents are **confirmed valid** through manual code inspection:

### Architecture

1. **Main store correctly on `cloudKitDatabase: .none`**  
   `DataProvider.swift:96-106` — Both persistent and in-memory configurations explicitly use `.none`.

2. **Import-before-export sequencing is correct**  
   `LibrarySyncCoordinator.runSync` phases: prepare → namespace → remote fetch → apply → token commit → reconcile → export. Remote changes are fully incorporated before any local dirty work is exported.

3. **Delete handling uses explicit tombstones throughout**  
   - `LibrarySyncChangeRecorder.recordDeletion` queues tombstones before local delete  
   - `CloudLibrarySyncClient.record(from tombstone:)` clears all user-state fields, sets `deletedAt`  
   - `CloudLibrarySyncImporter` ignores raw CloudKit deletes (line 161)  
   - `AnimeEntry.applySyncTombstone` hides entry (`onDisplay = false`) rather than deleting, preserving metadata

4. **Dirty queue is treated as sync work, not backup payload**  
   The queue stores only identities and timestamps. Export materializes the actual payload from the current local store (`localSnapshotsByIdentity`). This does **not** mean queue entries can be arbitrarily dropped: removal is safe after CloudKit accepts equivalent work, but reconciliation drops must use the same conflict outcome as remote application.

5. **Recorder suppression is depth-counted**  
   `suppressionDepth` supports nested `withSuppressedRecording` / `withSuppressedRecordingAsync` calls without premature re-enabling. The `defer` pattern ensures depth is always decremented.

### Data Integrity

6. **Deterministic record IDs prevent duplicates**  
   `LibraryEntrySyncIdentity` derives `rawID` from `entryType` + `tmdbID` (+ season context). Every device addresses the same CloudKit record for the same anime without relying on CloudKit uniqueness constraints.

7. **Clock-based LWW merge per-domain**  
   `LibraryEntrySyncSnapshot.merged(with:)` uses `libraryUpdatedAt` for membership/display fields and `trackingUpdatedAt` for tracking fields. Episode progress merges per-season by progress clock. This prevents cross-domain overwrites.

### Resilience

8. **Token namespace isolation prevents cross-account leakage**  
   `CloudLibrarySyncChangeTokenStore.Namespace` combines `containerIdentifier` + `accountIdentifier`. Tokens from one iCloud account are never reused for another.

9. **Token expiry handled with automatic retry**  
   `CloudLibrarySyncImporter.fetchChanges` catches `.changeTokenExpired`, clears the stored token, and retries from the beginning of the zone. One retry is attempted.

10. **Concurrent sync requests are serialized**  
    `LibrarySyncCoordinator.sync(trigger:)` uses `isSyncing` + `syncWaiters` to serialize concurrent calls. The `repeat { ... } while syncRequestedWhileRunning` loop handles requests that arrive while a sync is finishing.

---

## Test Coverage Assessment

| Category | Count | Confidence |
|----------|-------|------------|
| Well-tested core logic (snapshots, merges, tombstones, codec) | ~20 tests | **High** |
| Importer/exporter integration | 4 tests | **High** |
| Coordinator integration | 7 tests | **Medium-High** |
| Remaining important gaps (coordinator partial export, direct suppression test, deterministic scheduler tests) | 3-4 gaps | **Medium — should be addressed before rollout** |
| Rollout/manual-validation paths | Pending Stage 6-8 | Medium |

### Must-Add Tests Before Rollout

1. **Partial export failure in coordinator** — verify only successful identities are dequeued
2. **Recorder suppression** — verify `processSaveNotification` is skipped when `suppressionDepth > 0`
3. **Duplicate save notification deduplication** — verify identical clocks don't flood the queue
4. **`applyInitialSyncSnapshot` direct unit coverage** — coordinator integration covers fresh nil-clock materialization, but a focused method-level test would be useful

Already covered: bulk delete rollback is tested in `LibraryPreferencesAndActionsTests`.

---

## Top Priorities to Fix

### Before Stage 6 (Settings & Rollout)

1. **WARN-7:** Commit change token after successful local save, not after UI refresh
2. **WARN-3:** Stop indefinite poison-pill retries or classify permanent failures
3. **WARN-2:** Enforce TMDb key availability at scheduler/coordinator boundaries, or make hydration gracefully defer missing rows
4. **WARN-6:** Narrow `.serverRejectedRequest` handling so CloudKit setup errors are not masked
5. **WARN-12:** Add `@MainActor` dispatch in Combine sink for future Swift 6 compatibility
6. **Hydration cleanup:** Add coverage or cleanup for staged hydrated inserts if later apply/save fails; this is a downgraded partial finding, not a confirmed critical orphan bug

### Before Stage 8 (Manual Validation)

9. **WARN-4:** Define account-change policy, then add `CKAccountChanged` observer behavior
10. **WARN-5:** Add pagination page limit
11. **WARN-8:** Surface per-record CloudKit error details if rollout needs smarter retry/status
12. **WARN-9 / WARN-10:** Add specific handling for `zoneNotFound`, `userDeletedZone`, rate limits, and quota exceeded as part of restore/status policy
13. **All remaining must-add tests** (see Test Coverage section above)

---

## Files Reviewed

**Implementation:**
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncChangeTokenStore.swift`
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncDirtyQueueStore.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncImporter.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncExporter.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncDatabase.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncDecodeError.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncScheduler.swift`
- `MyAnimeList/Sources/App/LibrarySyncNotificationBridge.swift`
- `DataProvider/Sources/DataProvider/DataProvider.swift`
- `DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift`
- `DataProvider/Sources/DataProvider/Models/Other/AnimeEntryEpisodeProgressHelpers.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryRepository.swift`

**Tests:**
- `DataProvider/Tests/LibrarySyncTests/LibraryEntrySyncTests.swift`
- `DataProvider/Tests/LibrarySyncTests/CloudLibrarySyncClientTests.swift`
- `DataProvider/Tests/LibrarySyncTests/CloudLibrarySyncImporterExporterTests.swift`
- `DataProvider/Tests/LibrarySyncTests/LibraryEntrySyncDirtyQueueStoreTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncCoordinatorTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibrarySyncNotificationBridgeTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryPreferencesAndActionsTests.swift`
