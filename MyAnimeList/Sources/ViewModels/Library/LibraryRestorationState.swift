//
//  LibraryRestorationState.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/9/12.
//

import CloudKit
import DataProvider
import Foundation
import LibrarySync

struct LibraryRestorationFailure: Codable, Equatable, Identifiable {
    static let retryWindow: TimeInterval = 24 * 60 * 60

    var snapshot: LibraryEntrySyncSnapshot
    var metadataIdentity: LibraryEntryIdentity
    var reason: String
    var retryDates: [Date]
    var lastAttempt: Date
    // Persist explicit deletion intent separately from the ordinary dirty queue,
    // so it can only be sent to the account that supplied this failed entry.
    var discardDate: Date?

    var id: String { snapshot.identity.rawID }

    func canDiscard(at date: Date) -> Bool {
        discardDate == nil
            && retryDates.filter {
                $0 <= date && date.timeIntervalSince($0) <= Self.retryWindow
            }.count >= 3
    }

    var tombstone: LibraryEntrySyncTombstone? {
        discardDate.map(snapshot.discardTombstone(deletedAt:))
    }
}

struct LibraryRestorationState: Codable, Equatable {
    var scope: LibraryCloudSyncScope
    var totalEntries = 0
    var restoredEntries = 0
    var failures: [LibraryRestorationFailure] = []

    mutating func recordFailure(
        snapshot: LibraryEntrySyncSnapshot,
        error: LibrarySyncHydrationError,
        isUserRetry: Bool,
        at date: Date
    ) {
        let previous = failures.first { $0.snapshot == snapshot }
        var dates =
            previous?.retryDates.filter {
                $0 <= date && date.timeIntervalSince($0) <= LibraryRestorationFailure.retryWindow
            } ?? []
        if isUserRetry { dates.append(date) }
        failures.removeAll { $0.id == snapshot.identity.rawID }
        failures.append(
            .init(
                snapshot: snapshot, metadataIdentity: error.identity,
                reason: error.localizedDescription, retryDates: Array(dates.suffix(3)),
                lastAttempt: date, discardDate: previous?.discardDate
            ))
    }
}

/// Snapshots whose CloudKit token was committed before TMDb hydration succeeded.
///
/// Retryable failures are retried on every later pass, even when CloudKit has
/// no new changes. Permanent failures are retried only on manual retry, and
/// the user can discard them from iCloud without further retries.
struct LibraryPendingReconstructionState: Codable, Equatable {
    struct Failure: Codable, Equatable, Identifiable {
        var snapshot: LibraryEntrySyncSnapshot
        var metadataIdentity: LibraryEntryIdentity
        var reason: String
        var lastAttempt: Date
        var isPermanent: Bool? = nil
        // Deletion intent stays with the scope that supplied the failure, so it
        // can only be sent to that account.
        var discardDate: Date? = nil

        var id: String { snapshot.identity.rawID }

        var canDiscard: Bool {
            isPermanent == true && discardDate == nil
        }

        var tombstone: LibraryEntrySyncTombstone? {
            discardDate.map(snapshot.discardTombstone(deletedAt:))
        }
    }

    var scope: LibraryCloudSyncScope
    var failures: [Failure] = []

    mutating func recordFailure(
        snapshot: LibraryEntrySyncSnapshot,
        error: LibrarySyncHydrationError,
        at date: Date
    ) {
        let previous = failures.first { $0.snapshot == snapshot }
        failures.removeAll { $0.snapshot.identity == snapshot.identity }
        failures.append(
            .init(
                snapshot: snapshot,
                metadataIdentity: error.identity,
                reason: error.localizedDescription,
                lastAttempt: date,
                isPermanent: error.isPermanentReconstructionFailure,
                discardDate: previous?.discardDate
            )
        )
    }
}

extension LibraryCloudSyncStatus {
    /// Pending reconstruction failures for the scope of the last completed sync.
    var currentPendingReconstructionFailures: [LibraryPendingReconstructionState.Failure] {
        guard let lastCompletedScope else { return [] }
        return pendingReconstructions.first { $0.scope == lastCompletedScope }?.failures ?? []
    }
}

extension LibraryEntrySyncSnapshot {
    /// A discard date that orders after every saved change in this snapshot.
    fileprivate func discardDate(at date: Date) -> Date {
        LibrarySyncTimestamp.normalized(
            max(date, (latestUserStateClock ?? .distantPast).addingTimeInterval(0.001)))
    }

    fileprivate func discardTombstone(deletedAt: Date) -> LibraryEntrySyncTombstone {
        LibraryEntrySyncTombstone(
            identity: identity, tmdbID: tmdbID,
            parentSeriesID: parentSeriesID, seasonNumber: seasonNumber,
            entryType: entryType, deletedAt: deletedAt
        )
    }
}

extension LibraryStore {
    func discardFailedRestorationEntry(_ failure: LibraryRestorationFailure) async -> Bool {
        guard !requiresDuplicateRepair,
            libraryCloudSyncStatus.isEnabled,
            !libraryCloudSyncStatus.isSyncInProgress,
            syncCoordinator?.hasActiveSyncRequest == false,
            failure.canDiscard(at: .now),
            libraryCloudSyncStatus.restoration?.failures.contains(failure) == true,
            repository.existingEntry(identity: failure.snapshot.identity) == nil
        else { return false }

        updateLibraryCloudSyncStatus { status in
            guard let index = status.restoration?.failures.firstIndex(of: failure) else { return }
            status.restoration?.failures[index].discardDate = failure.snapshot.discardDate(at: .now)
        }
        // The bootstrap gate and account check also protect this narrowly scoped
        // export. A failed request retains the exact same deletion intent for retry.
        return await bootstrapLibraryCloudSyncEnablement().succeeded
    }

    /// Discards a permanently failed reconstruction from iCloud.
    ///
    /// Unlike restoration failures, these need no manual retries first: the
    /// failure is already known to be permanent, such as a title TMDb removed.
    func discardFailedPendingReconstruction(_ failure: LibraryPendingReconstructionState.Failure) async -> Bool {
        guard !requiresDuplicateRepair,
            libraryCloudSyncStatus.isEnabled,
            libraryCloudSyncStatus.bootstrapState == .completed,
            !libraryCloudSyncStatus.isSyncInProgress,
            syncCoordinator?.hasActiveSyncRequest == false,
            failure.canDiscard,
            libraryCloudSyncStatus.currentPendingReconstructionFailures.contains(failure),
            repository.existingEntry(identity: failure.snapshot.identity) == nil,
            let scope = libraryCloudSyncStatus.lastCompletedScope
        else { return false }

        updateLibraryCloudSyncStatus { status in
            guard let pendingIndex = status.pendingReconstructions.firstIndex(where: { $0.scope == scope }),
                let index = status.pendingReconstructions[pendingIndex].failures.firstIndex(of: failure)
            else { return }
            status.pendingReconstructions[pendingIndex].failures[index].discardDate =
                failure.snapshot.discardDate(at: .now)
        }
        // The ordinary pass sends the deletion only after confirming the active
        // account still matches this scope. A failed request keeps the intent.
        return await performLibrarySync(trigger: .manualRetry)
    }
}

extension LibrarySyncCoordinator {
    func exportRestorationDiscards(in store: LibraryStore, checkCancellation: () throws -> Void) async throws {
        guard let scope = store.libraryCloudSyncStatus.restoration?.scope else { return }
        let pending = store.libraryCloudSyncStatus.restoration?.failures.compactMap(\.tombstone) ?? []
        try await exportDiscards(pending, in: scope, checkCancellation: checkCancellation) { tombstone in
            store.updateLibraryCloudSyncStatus { status in
                status.restoration?.failures.removeAll { $0.matches(tombstone) }
            }
        }
    }

    /// Sends discard intents recorded for failed reconstructions in `scope`.
    ///
    /// The caller must have verified that `scope` belongs to the active account.
    func exportPendingReconstructionDiscards(
        in scope: LibraryCloudSyncScope,
        store: LibraryStore,
        checkCancellation: () throws -> Void
    ) async throws {
        let pending =
            store.libraryCloudSyncStatus.pendingReconstructions
            .first { $0.scope == scope }?.failures.compactMap(\.tombstone) ?? []
        try await exportDiscards(pending, in: scope, checkCancellation: checkCancellation) { tombstone in
            store.updateLibraryCloudSyncStatus { status in
                guard let index = status.pendingReconstructions.firstIndex(where: { $0.scope == scope }) else {
                    return
                }
                status.pendingReconstructions[index].failures.removeAll { $0.matches(tombstone) }
                if status.pendingReconstructions[index].failures.isEmpty {
                    status.pendingReconstructions.remove(at: index)
                }
            }
        }
    }

    private func exportDiscards(
        _ tombstones: [LibraryEntrySyncTombstone],
        in scope: LibraryCloudSyncScope,
        checkCancellation: () throws -> Void,
        onConfirmed: (LibraryEntrySyncTombstone) -> Void
    ) async throws {
        guard !tombstones.isEmpty else { return }
        let blockedRecordIDs = try importer.quarantinedRecordIDs(
            namespace: .init(
                containerIdentifier: scope.containerIdentifier,
                accountIdentifier: scope.accountIdentifier
            )
        )
        for tombstone in tombstones {
            try checkCancellation()
            try Task.checkCancellation()
            let result = try await exporter.export(
                entries: [.delete(.init(tombstone: tombstone))],
                localSnapshotsByIdentity: [:],
                blockedRecordIDs: blockedRecordIDs
            )
            guard result.exportedIdentities.contains(tombstone.identity) else {
                // The exporter skips quarantined records; keep their discard
                // intent until a newer build can read and confirm the save.
                if !result.rejectedIdentities.contains(tombstone.identity) {
                    continue
                }
                throw LibraryRestorationDiscardError.notConfirmed
            }
            onConfirmed(tombstone)
            try checkCancellation()
        }
    }
}

fileprivate protocol LibraryDiscardableFailure {
    var snapshot: LibraryEntrySyncSnapshot { get }
    var discardDate: Date? { get }
}

extension LibraryDiscardableFailure {
    fileprivate func matches(_ tombstone: LibraryEntrySyncTombstone) -> Bool {
        snapshot.identity == tombstone.identity
            && discardDate.map(LibrarySyncTimestamp.milliseconds)
                == LibrarySyncTimestamp.milliseconds(tombstone.deletedAt)
    }
}

extension LibraryRestorationFailure: LibraryDiscardableFailure {}
extension LibraryPendingReconstructionState.Failure: LibraryDiscardableFailure {}

fileprivate enum LibraryRestorationDiscardError: LocalizedError {
    case notConfirmed

    var errorDescription: String? {
        String(localized: "iCloud has not confirmed the deletion. Retry to finish discarding this entry.")
    }
}
