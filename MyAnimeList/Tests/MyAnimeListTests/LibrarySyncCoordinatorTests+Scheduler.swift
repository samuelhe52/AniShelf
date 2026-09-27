//
//  LibrarySyncCoordinatorTests+Scheduler.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

extension LibrarySyncCoordinatorTests {
    @Test @MainActor func sharedScheduledFailureCountsAsOneRetryAttempt() async throws {
        let gate = SyncGate()
        var syncStarted = false
        var resumeSync: CheckedContinuation<Void, Never>?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            failureRetryIntervals: [1],
            hasPendingLocalWork: { true },
            syncOutcome: { _ in
                gate.begin(kind: .ordinary, ownerHandlesResult: true)
                syncStarted = true
                await withCheckedContinuation { resumeSync = $0 }
                gate.finish(.retryableFailure)
                return .init(.retryableFailure)
            }
        )

        scheduler.schedulePendingLocalSync()
        while !syncStarted { await Task.yield() }
        let foreground = Task { await gate.waitForRunningPass() }
        while !gate.consumeRerunRequest() { await Task.yield() }
        resumeSync?.resume()
        let shared = try #require(await foreground.value)
        while scheduler.retryState.failureRetryAttempt == 0 { await Task.yield() }
        #expect(shared.wasCoalesced)
        #expect(!shared.shouldHandleResult)
        if shared.shouldHandleResult {
            scheduler.recordExternalSyncResult(shared.result)
        }
        #expect(scheduler.retryState.failureRetryAttempt == 1)
        scheduler.resetRetryBackoff()
    }

    @Test @MainActor func replacedScheduledPassKeepsSharedFailureRetrying() async throws {
        let gate = SyncGate()
        var resumeOwner: CheckedContinuation<Void, Never>?
        var replacementWaiting = false
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            failureRetryIntervals: [5],
            hasPendingLocalWork: { true },
            syncOutcome: { _ in
                guard resumeOwner == nil else {
                    replacementWaiting = true
                    return await gate.waitForRunningPass() ?? .init(.skipped(.disabled))
                }
                gate.begin(kind: .ordinary, ownerHandlesResult: true)
                await withCheckedContinuation { resumeOwner = $0 }
                gate.finish(.retryableFailure)
                return .init(.retryableFailure)
            }
        )

        scheduler.schedulePendingLocalSync()
        while resumeOwner == nil { await Task.yield() }
        // A local edit replaces the running pass, and the replacement waits on it.
        scheduler.schedulePendingLocalSync()
        while !replacementWaiting { await Task.yield() }
        resumeOwner?.resume()
        for _ in 0..<100 { await Task.yield() }

        #expect(scheduler.retryState.failureRetryAttempt == 1)
        #expect(scheduler.retryState.nextRetryAllowedAt != nil)
        scheduler.resetRetryBackoff()
    }

    @Test @MainActor func bootstrapFailureAssignsOneQueuedRetryOwner() async throws {
        let gate = SyncGate()
        gate.begin(kind: .bootstrap, ownerHandlesResult: false)
        let first = Task { await gate.waitForRunningPass() }
        while !gate.consumeRerunRequest() { await Task.yield() }
        let second = Task { await gate.waitForRunningPass() }
        while !gate.consumeRerunRequest() { await Task.yield() }

        gate.finish(.retryableFailure)
        let firstOutcome = try #require(await first.value)
        let secondOutcome = try #require(await second.value)
        #expect(firstOutcome.wasCoalesced)
        #expect(firstOutcome.shouldHandleResult)
        #expect(secondOutcome.wasCoalesced)
        #expect(!secondOutcome.shouldHandleResult)
    }

    @Test @MainActor func skippedForegroundPassPreservesScheduledLocalRetry() async throws {
        var syncCount = 0
        let scheduler = LibrarySyncScheduler(
            failureRetryIntervals: [0.12],
            hasPendingLocalWork: { true },
            sync: { _ in
                syncCount += 1
                return .success
            }
        )

        scheduler.recordExternalSyncResult(.retryableFailure)
        scheduler.recordExternalSyncResult(.skipped(.disabled))
        #expect(scheduler.retryState.failureRetryAttempt == 1)
        try await Task.sleep(nanoseconds: 160_000_000)
        #expect(syncCount == 1)
        #expect(scheduler.retryState == .idle)
    }

    @Test @MainActor func remoteOnlyFailureRetriesAfterCloudKitMinimumDelay() async throws {
        var syncCount = 0
        let scheduler = LibrarySyncScheduler(
            failureRetryIntervals: [0.01],
            hasPendingLocalWork: { false },
            minimumRetryDelay: { 0.15 },
            sync: { _ in
                syncCount += 1
                return .success
            }
        )

        scheduler.recordExternalSyncResult(.retryableFailure)
        #expect(scheduler.retryState.failureRetryAttempt == 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(syncCount == 0)
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(syncCount == 1)
        #expect(scheduler.retryState == .idle)
    }

    @Test @MainActor func cloudKitQuotaNeedsUserActionAndRateLimitCarriesRetryHint() {
        let quota = CKError(.quotaExceeded)
        let rateLimited = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 30.0])

        #expect(quota.isPermanentLibrarySyncFailure)
        #expect(quota.librarySyncDegradedReason != nil)
        #expect(!rateLimited.isPermanentLibrarySyncFailure)
        #expect(rateLimited.librarySyncRetryAfterSeconds == 30)
        let recordID = CKRecord.ID(recordName: "partial", zoneID: CloudLibrarySyncClient.recordZoneID)
        let partial = CloudLibrarySyncPartialSaveFailure(
            savedRecordIDs: [], failedErrorsByID: [recordID: rateLimited]
        )
        #expect(partial.librarySyncRetryAfterSeconds == 30)
        #expect(!partial.isPermanentLibrarySyncFailure)
    }

    @Test @MainActor func localSyncSchedulerDebouncesLocalChanges() async throws {
        var syncCount = 0
        var hasPendingLocalWork = true
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.05,
            failureRetryIntervals: [0.1],
            hasPendingLocalWork: {
                hasPendingLocalWork
            },
            sync: { trigger in
                #expect(trigger == .localChange)
                syncCount += 1
                hasPendingLocalWork = false
                return .success
            }
        )

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 20_000_000)
        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 0)

        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(syncCount == 1)
    }

    @Test @MainActor func localSyncSchedulerBacksOffAfterFailure() async throws {
        var syncCount = 0
        var hasPendingLocalWork = true
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.08],
            hasPendingLocalWork: {
                hasPendingLocalWork
            },
            sync: { _ in
                syncCount += 1
                if syncCount == 1 {
                    return .retryableFailure
                }
                hasPendingLocalWork = false
                return .success
            }
        )

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 1)

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 1)

        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(syncCount == 2)
    }

    @Test @MainActor func localSyncSchedulerStopsAfterFinalIntervalRetryLimit() async throws {
        var syncCount = 0
        var retryStates: [LibraryCloudSyncRetryState] = []
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.001,
            failureRetryIntervals: [0.01, 0.02],
            maximumRetryAttemptsAtFinalInterval: 3,
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.schedulePendingLocalSync()
        for _ in 0..<200 where retryStates.last?.automaticRetriesExhausted != true {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(syncCount == 5)
        #expect(retryStates.last?.automaticRetriesExhausted == true)
        #expect(degradedReason != nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(syncCount == 5)
    }

    @Test @MainActor func successfulPassWithPendingEntriesRetriesQuietlyWithinLimit() async throws {
        var syncCount = 0
        var retryStates: [LibraryCloudSyncRetryState] = []
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            failureRetryIntervals: [0.01, 0.02],
            maximumRetryAttemptsAtFinalInterval: 1,
            hasPendingLocalWork: { false },
            hasPendingItemRetryWork: { true },
            sync: { _ in
                syncCount += 1
                return .success
            },
            retryStateDidChange: { retryStates.append($0) },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.recordExternalSyncResult(.success)
        for _ in 0..<100 where syncCount < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(syncCount == 2)
        #expect(retryStates.allSatisfy { $0 == .idle })
        #expect(degradedReason == nil)
    }

    @Test @MainActor func localSyncSchedulerResetRestartsFailureRetryPolicy() async throws {
        var syncCount = 0
        var retryStates: [LibraryCloudSyncRetryState] = []
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.001,
            failureRetryIntervals: [0.01, 0.02],
            maximumRetryAttemptsAtFinalInterval: 3,
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) }
        )

        scheduler.schedulePendingLocalSync()
        for _ in 0..<100 where retryStates.last?.automaticRetriesExhausted != true {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(syncCount == 5)
        #expect(retryStates.last?.automaticRetriesExhausted == true)

        scheduler.resetRetryBackoff()
        scheduler.schedulePendingLocalSync()
        for _ in 0..<50 where syncCount < 6 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(syncCount == 6)
        #expect(retryStates.last?.failureRetryAttempt == 1)
        #expect(retryStates.last?.automaticRetriesExhausted == false)
    }

    @Test @MainActor func localSyncSchedulerDoesNotRetryPermanentFailure() async throws {
        var syncCount = 0
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.02],
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .permanentFailure
            },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.schedulePendingLocalSync()
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(syncCount == 1)
        #expect(degradedReason != nil)
    }

    @Test @MainActor func localSyncSchedulerAwaitableFlushWaitsForSyncCompletion() async throws {
        var hasPendingLocalWork = true
        var syncStarted = false
        var syncContinuation: CheckedContinuation<Void, Never>?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            hasPendingLocalWork: {
                hasPendingLocalWork
            },
            sync: { _ in
                syncStarted = true
                await withCheckedContinuation { continuation in
                    syncContinuation = continuation
                }
                hasPendingLocalWork = false
                return .success
            }
        )

        let flushTask = Task {
            await scheduler.flushPendingLocalSyncAndWait()
        }
        while !syncStarted {
            await Task.yield()
        }

        #expect(!flushTask.isCancelled)

        syncContinuation?.resume()
        let outcome = await flushTask.value

        #expect(outcome == .completed(.success))
    }

    @Test @MainActor func localSyncSchedulerAwaitableFlushDefersExistingBackoff() async throws {
        var syncCount = 0
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            failureRetryIntervals: [1],
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .retryableFailure
            }
        )

        scheduler.schedulePendingLocalSync()
        while syncCount == 0 {
            await Task.yield()
        }
        while scheduler.retryState.nextRetryAllowedAt == nil {
            await Task.yield()
        }

        let outcome = await scheduler.flushPendingLocalSyncAndWait()

        #expect(outcome == .deferredByRetryBackoff)
        #expect(syncCount == 1)
    }

    @Test @MainActor func localSyncSchedulerAwaitableFlushPropagatesCancellation() async throws {
        var syncStarted = false
        var syncObservedCancellation = false
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncStarted = true
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    syncObservedCancellation = Task.isCancelled
                }
                return .retryableFailure
            }
        )

        let flushTask = Task {
            await scheduler.flushPendingLocalSyncAndWait()
        }
        while !syncStarted {
            await Task.yield()
        }

        flushTask.cancel()
        let outcome = await flushTask.value

        #expect(outcome == .cancelled)
        #expect(syncObservedCancellation)
        #expect(scheduler.retryState.failureRetryAttempt == 0)
    }

    @Test @MainActor func localSyncSchedulerResetCancelsInFlightSyncHandling() async throws {
        var syncCount = 0
        var syncStarted = false
        var syncContinuation: CheckedContinuation<Void, Never>?
        var retryStates: [LibraryCloudSyncRetryState] = []
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0,
            failureRetryIntervals: [0.01],
            hasPendingLocalWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                syncStarted = true
                await withCheckedContinuation { continuation in
                    syncContinuation = continuation
                }
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) }
        )

        let flushTask = Task {
            await scheduler.flushPendingLocalSyncAndWait()
        }
        while !syncStarted {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        scheduler.resetRetryBackoff()
        syncContinuation?.resume()
        let outcome = await flushTask.value

        #expect(outcome == .cancelled)
        #expect(syncCount == 1)
        #expect(retryStates.last?.failureRetryAttempt == 0)
        #expect(retryStates.last?.automaticRetriesExhausted == false)
    }
}
