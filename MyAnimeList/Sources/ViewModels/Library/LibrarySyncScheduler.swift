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
    private let sync: @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncResult
    private let retryStateDidChange: @MainActor (LibraryCloudSyncRetryState) -> Void
    private let degradedStateDidChange: @MainActor (String) -> Void

    private var scheduledTask: Task<LibrarySyncCoordinator.SyncResult?, Never>?
    private var scheduledTaskID: UUID?
    private var nextRetryAllowedAt: Date?
    private var failureRetryAttempt = 0
    private var automaticRetriesExhausted = false

    var retryState: LibraryCloudSyncRetryState {
        .init(
            failureRetryAttempt: failureRetryAttempt,
            nextRetryAllowedAt: nextRetryAllowedAt,
            automaticRetriesExhausted: automaticRetriesExhausted
        )
    }

    init(
        localDebounceInterval: TimeInterval = 1.5,
        failureRetryIntervals: [TimeInterval] = [30, 60, 120, 300],
        maximumRetryAttemptsAtFinalInterval: Int = 3,
        hasPendingLocalWork: @escaping @MainActor () -> Bool,
        sync: @escaping @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncResult,
        retryStateDidChange: @escaping @MainActor (LibraryCloudSyncRetryState) -> Void = { _ in },
        degradedStateDidChange: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.localDebounceInterval = localDebounceInterval
        self.failureRetryIntervals = failureRetryIntervals
        self.maximumRetryAttemptsAtFinalInterval = maximumRetryAttemptsAtFinalInterval
        self.hasPendingLocalWork = hasPendingLocalWork
        self.sync = sync
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
        scheduledTask?.cancel()
        scheduledTask = nil
        scheduledTaskID = nil
        resetFailureBackoff()
    }

    private func runScheduledSync(taskID: UUID) async -> LibrarySyncCoordinator.SyncResult? {
        guard scheduledTaskID == taskID, !Task.isCancelled else { return nil }
        defer {
            if scheduledTaskID == taskID {
                scheduledTask = nil
                scheduledTaskID = nil
            }
        }
        guard hasPendingLocalWork() else {
            resetFailureBackoff()
            return nil
        }

        let result = await sync(.localChange)
        guard !Task.isCancelled, scheduledTaskID == taskID else { return nil }
        switch result {
        case .success:
            resetFailureBackoff()
        case .skipped(_):
            resetFailureBackoff()
        case .conflictChoiceRequired:
            resetFailureBackoff()
        case .retryableFailure:
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

    private func scheduleFailureRetryIfNeeded() {
        guard hasPendingLocalWork(), !failureRetryIntervals.isEmpty else { return }
        let maximumRetryAttempts = max(
            0,
            failureRetryIntervals.count - 1 + maximumRetryAttemptsAtFinalInterval
        )
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
        let retryDelay = failureRetryIntervals[min(failureRetryAttempt, failureRetryIntervals.count - 1)]
        failureRetryAttempt += 1
        nextRetryAllowedAt = Date().addingTimeInterval(retryDelay)
        automaticRetriesExhausted = false
        retryStateDidChange(retryState)
        librarySyncSchedulerLogger.warning(
            "Scheduled iCloud library sync retry in \(retryDelay, privacy: .public) seconds after a local-change sync failure."
        )
        schedule(after: retryDelay)
    }

    private func resetFailureBackoff() {
        failureRetryAttempt = 0
        nextRetryAllowedAt = nil
        automaticRetriesExhausted = false
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
