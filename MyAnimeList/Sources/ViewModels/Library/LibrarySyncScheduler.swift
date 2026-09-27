//
//  LibrarySyncScheduler.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import Foundation
import os

fileprivate let librarySyncSchedulerLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibrarySync.Scheduler"
)

/// Coalesces local sync work before asking CloudKit to sync.
@MainActor
final class LibrarySyncScheduler {
    enum FlushOutcome: Equatable {
        case noPendingWork
        case deferredByRetryBackoff
        case completed(LibrarySyncCoordinator.SyncResult)
        case cancelled
    }

    private let localDebounceInterval: TimeInterval
    private let failureRetryIntervals: [TimeInterval]
    private let maximumRetryAttemptsAtFinalInterval: Int
    private let hasPendingLocalWork: @MainActor () -> Bool
    private let hasPendingItemRetryWork: @MainActor () -> Bool
    private let minimumRetryDelay: @MainActor () -> TimeInterval?
    private let sync: @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncOutcome
    private let retryStateDidChange: @MainActor (LibraryCloudSyncRetryState) -> Void
    private let degradedStateDidChange: @MainActor (String) -> Void

    private var scheduledTask: Task<LibrarySyncCoordinator.SyncResult?, Never>?
    private var scheduledTaskID: UUID?
    private var nextRetryAllowedAt: Date?
    private var failureRetryAttempt = 0
    private var automaticRetriesExhausted = false
    private var needsRemoteRetry = false
    private var itemRetryAttempt = 0

    var retryState: LibraryCloudSyncRetryState {
        .init(
            failureRetryAttempt: failureRetryAttempt,
            nextRetryAllowedAt: nextRetryAllowedAt,
            automaticRetriesExhausted: automaticRetriesExhausted
        )
    }

    convenience init(
        localDebounceInterval: TimeInterval = 1.5,
        failureRetryIntervals: [TimeInterval] = [30, 60, 120, 300],
        maximumRetryAttemptsAtFinalInterval: Int = 3,
        hasPendingLocalWork: @escaping @MainActor () -> Bool,
        hasPendingItemRetryWork: @escaping @MainActor () -> Bool = { false },
        minimumRetryDelay: @escaping @MainActor () -> TimeInterval? = { nil },
        sync: @escaping @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncResult,
        retryStateDidChange: @escaping @MainActor (LibraryCloudSyncRetryState) -> Void = { _ in },
        degradedStateDidChange: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.init(
            localDebounceInterval: localDebounceInterval,
            failureRetryIntervals: failureRetryIntervals,
            maximumRetryAttemptsAtFinalInterval: maximumRetryAttemptsAtFinalInterval,
            hasPendingLocalWork: hasPendingLocalWork,
            hasPendingItemRetryWork: hasPendingItemRetryWork,
            minimumRetryDelay: minimumRetryDelay,
            syncOutcome: { trigger in .init(await sync(trigger)) },
            retryStateDidChange: retryStateDidChange,
            degradedStateDidChange: degradedStateDidChange
        )
    }

    init(
        localDebounceInterval: TimeInterval = 1.5,
        failureRetryIntervals: [TimeInterval] = [30, 60, 120, 300],
        maximumRetryAttemptsAtFinalInterval: Int = 3,
        hasPendingLocalWork: @escaping @MainActor () -> Bool,
        hasPendingItemRetryWork: @escaping @MainActor () -> Bool = { false },
        minimumRetryDelay: @escaping @MainActor () -> TimeInterval? = { nil },
        syncOutcome: @escaping @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncOutcome,
        retryStateDidChange: @escaping @MainActor (LibraryCloudSyncRetryState) -> Void = { _ in },
        degradedStateDidChange: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.localDebounceInterval = localDebounceInterval
        self.failureRetryIntervals = failureRetryIntervals
        self.maximumRetryAttemptsAtFinalInterval = maximumRetryAttemptsAtFinalInterval
        self.hasPendingLocalWork = hasPendingLocalWork
        self.hasPendingItemRetryWork = hasPendingItemRetryWork
        self.minimumRetryDelay = minimumRetryDelay
        self.sync = syncOutcome
        self.retryStateDidChange = retryStateDidChange
        self.degradedStateDidChange = degradedStateDidChange
    }

    deinit {
        scheduledTask?.cancel()
    }

    /// Schedules a local-change sync after the debounce window settles.
    func schedulePendingLocalSync() {
        schedule(after: delayRespectingFailureBackoff(localDebounceInterval))
    }

    /// Runs one local sync attempt immediately and waits for it to finish.
    ///
    /// A retry that is already subject to backoff stays scheduled for later rather
    /// than keeping a caller alive while waiting for the retry window.
    func flushPendingLocalSyncAndWait() async -> FlushOutcome {
        guard hasPendingLocalWork() else { return .noPendingWork }
        guard delayRespectingFailureBackoff(0) <= 0 else {
            return .deferredByRetryBackoff
        }

        let task = schedule(after: 0)
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, let result else { return .cancelled }
        return .completed(result)
    }

    func resetRetryBackoff() {
        cancelScheduledSync()
        resetFailureBackoff()
        itemRetryAttempt = 0
    }

    /// A foreground or notification pass can fail before any local edits are queued.
    ///
    /// Keep retrying its remote work through the same bounded policy.
    func recordExternalSyncResult(_ result: LibrarySyncCoordinator.SyncResult) {
        switch result {
        case .retryableFailure:
            needsRemoteRetry = true
            scheduleFailureRetryIfNeeded()
        case .success:
            cancelScheduledSync()
            resetFailureBackoff()
            scheduleItemRetryIfNeeded()
        case .skipped, .conflictChoiceRequired, .permanentFailure:
            break
        }
    }

    private func runScheduledSync(taskID: UUID) async -> LibrarySyncCoordinator.SyncResult? {
        guard scheduledTaskID == taskID, !Task.isCancelled else { return nil }
        defer {
            if scheduledTaskID == taskID {
                scheduledTask = nil
                scheduledTaskID = nil
            }
        }
        guard hasPendingLocalWork() || needsRemoteRetry || hasPendingItemRetryWork() else {
            resetFailureBackoff()
            return nil
        }

        let outcome = await sync(.localChange)
        if let scheduledTaskID, scheduledTaskID != taskID {
            // A newer schedule replaced this pass while it ran. If that task
            // waited on this pass, it does not own the result, so keep the
            // failure retrying here. Success must not cancel the replacement,
            // which may carry edits made after this pass exported.
            if outcome.shouldHandleResult, outcome.result == .retryableFailure {
                recordExternalSyncResult(outcome.result)
            }
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let result = outcome.result
        guard outcome.shouldHandleResult else { return result }
        switch result {
        case .success:
            resetFailureBackoff()
            scheduleItemRetryIfNeeded()
        case .skipped(_):
            resetFailureBackoff()
        case .conflictChoiceRequired:
            resetFailureBackoff()
        case .retryableFailure:
            needsRemoteRetry = true
            scheduleFailureRetryIfNeeded()
        case .permanentFailure:
            resetFailureBackoff()
            degradedStateDidChange(
                "Automatic iCloud library sync stopped because a permanent failure blocked local work."
            )
            librarySyncSchedulerLogger.warning(
                "Skipped automatic iCloud library sync retry after a non-retryable local-change sync failure."
            )
        }
        return result
    }

    private var maximumRetryAttempts: Int {
        max(0, failureRetryIntervals.count - 1 + maximumRetryAttemptsAtFinalInterval)
    }

    private func scheduleFailureRetryIfNeeded() {
        guard hasPendingLocalWork() || needsRemoteRetry, !failureRetryIntervals.isEmpty else { return }
        guard failureRetryAttempt < maximumRetryAttempts else {
            nextRetryAllowedAt = nil
            automaticRetriesExhausted = true
            retryStateDidChange(retryState)
            degradedStateDidChange(
                "Automatic iCloud library sync retries stopped after the local-change retry policy was exhausted."
            )
            librarySyncSchedulerLogger.warning(
                "Stopped automatic iCloud library sync retries after exhausting the local-change failure retry policy."
            )
            return
        }
        let policyDelay = failureRetryIntervals[min(failureRetryAttempt, failureRetryIntervals.count - 1)]
        let cloudKitDelay = minimumRetryDelay().flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
        let retryDelay = max(policyDelay, cloudKitDelay)
        failureRetryAttempt += 1
        nextRetryAllowedAt = Date().addingTimeInterval(retryDelay)
        automaticRetriesExhausted = false
        retryStateDidChange(retryState)
        librarySyncSchedulerLogger.warning(
            "Scheduled iCloud library sync retry in \(retryDelay, privacy: .public) seconds after a local-change sync failure."
        )
        schedule(after: retryDelay)
    }

    /// Retries entries a successful pass left behind, such as a rejected upload
    /// or a failed reconstruction.
    ///
    /// These retries follow the failure intervals but stay out of the failure
    /// state: they neither delay local edits nor report sync as degraded, and
    /// they stop silently at the limit because the entries are already shown.
    /// Later passes still retry the entries.
    private func scheduleItemRetryIfNeeded() {
        guard hasPendingItemRetryWork() else {
            itemRetryAttempt = 0
            return
        }
        guard !failureRetryIntervals.isEmpty, itemRetryAttempt < maximumRetryAttempts else {
            librarySyncSchedulerLogger.info(
                "Left pending iCloud library sync entries for later passes after exhausting automatic entry retries."
            )
            return
        }
        let retryDelay = failureRetryIntervals[min(itemRetryAttempt, failureRetryIntervals.count - 1)]
        itemRetryAttempt += 1
        librarySyncSchedulerLogger.info(
            "Scheduled iCloud library sync retry in \(retryDelay, privacy: .public) seconds for entries a successful pass left pending."
        )
        schedule(after: retryDelay)
    }

    private func cancelScheduledSync() {
        scheduledTask?.cancel()
        scheduledTask = nil
        scheduledTaskID = nil
    }

    private func resetFailureBackoff() {
        failureRetryAttempt = 0
        nextRetryAllowedAt = nil
        automaticRetriesExhausted = false
        needsRemoteRetry = false
        retryStateDidChange(retryState)
    }

    private func delayRespectingFailureBackoff(_ preferredDelay: TimeInterval) -> TimeInterval {
        guard let nextRetryAllowedAt else {
            return preferredDelay
        }
        return max(preferredDelay, nextRetryAllowedAt.timeIntervalSinceNow)
    }

    @discardableResult
    private func schedule(after interval: TimeInterval) -> Task<LibrarySyncCoordinator.SyncResult?, Never> {
        scheduledTask?.cancel()
        let clampedInterval = max(0, interval)
        let taskID = UUID()
        scheduledTaskID = taskID
        let task = Task<LibrarySyncCoordinator.SyncResult?, Never> { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: clampedInterval))
            guard !Task.isCancelled else { return nil }
            return await self?.runScheduledSync(taskID: taskID)
        }
        scheduledTask = task
        return task
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        guard interval.isFinite, interval > 0 else { return 0 }
        return UInt64((interval * 1_000_000_000).rounded())
    }
}
