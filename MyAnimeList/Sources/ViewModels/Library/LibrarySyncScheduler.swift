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

/// Coalesces local dirty-queue changes before asking CloudKit to sync.
@MainActor
final class LibrarySyncScheduler {
    private let localDebounceInterval: TimeInterval
    private let failureRetryIntervals: [TimeInterval]
    private let hasPendingDirtyWork: @MainActor () -> Bool
    private let sync: @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncResult

    private var scheduledTask: Task<Void, Never>?
    private var nextRetryAllowedAt: Date?
    private var failureRetryAttempt = 0

    init(
        localDebounceInterval: TimeInterval = 1.5,
        failureRetryIntervals: [TimeInterval] = [30, 60, 120, 300],
        hasPendingDirtyWork: @escaping @MainActor () -> Bool,
        sync: @escaping @MainActor (LibrarySyncCoordinator.Trigger) async -> LibrarySyncCoordinator.SyncResult
    ) {
        self.localDebounceInterval = localDebounceInterval
        self.failureRetryIntervals = failureRetryIntervals
        self.hasPendingDirtyWork = hasPendingDirtyWork
        self.sync = sync
    }

    deinit {
        scheduledTask?.cancel()
    }

    /// Schedules a local-change sync after the debounce window settles.
    func scheduleLocalDirtyQueueSync() {
        schedule(after: delayRespectingFailureBackoff(localDebounceInterval))
    }

    /// Runs local dirty work as soon as possible, if there is any.
    func flushLocalDirtyQueueSync() {
        guard hasPendingDirtyWork() else { return }
        schedule(after: delayRespectingFailureBackoff(0))
    }

    private func runScheduledSync() async {
        scheduledTask = nil
        guard hasPendingDirtyWork() else {
            resetFailureBackoff()
            return
        }

        let result = await sync(.localDirtyQueueChange)
        switch result {
        case .success:
            resetFailureBackoff()
        case .retryableFailure:
            scheduleFailureRetryIfNeeded()
        case .permanentFailure:
            resetFailureBackoff()
            librarySyncSchedulerLogger.warning(
                "Skipped automatic iCloud library sync retry after a non-retryable local-change sync failure."
            )
        }
    }

    private func scheduleFailureRetryIfNeeded() {
        guard hasPendingDirtyWork(), !failureRetryIntervals.isEmpty else { return }
        let retryDelay = failureRetryIntervals[min(failureRetryAttempt, failureRetryIntervals.count - 1)]
        failureRetryAttempt += 1
        nextRetryAllowedAt = Date().addingTimeInterval(retryDelay)
        librarySyncSchedulerLogger.warning(
            "Scheduled iCloud library sync retry in \(retryDelay, privacy: .public) seconds after a local-change sync failure."
        )
        schedule(after: retryDelay)
    }

    private func resetFailureBackoff() {
        failureRetryAttempt = 0
        nextRetryAllowedAt = nil
    }

    private func delayRespectingFailureBackoff(_ preferredDelay: TimeInterval) -> TimeInterval {
        guard let nextRetryAllowedAt else {
            return preferredDelay
        }
        return max(preferredDelay, nextRetryAllowedAt.timeIntervalSinceNow)
    }

    private func schedule(after interval: TimeInterval) {
        scheduledTask?.cancel()
        let clampedInterval = max(0, interval)
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: clampedInterval))
            guard !Task.isCancelled else { return }
            await self?.runScheduledSync()
        }
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        guard interval.isFinite, interval > 0 else { return 0 }
        return UInt64((interval * 1_000_000_000).rounded())
    }
}
