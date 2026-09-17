//
//  LibraryRestorationState.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/9/12.
//

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
        guard let discardDate else { return nil }
        return LibraryEntrySyncTombstone(
            identity: snapshot.identity, tmdbID: snapshot.tmdbID,
            parentSeriesID: snapshot.parentSeriesID, seasonNumber: snapshot.seasonNumber,
            entryType: snapshot.entryType, deletedAt: discardDate
        )
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
            status.restoration?.failures[index].discardDate = max(
                .now, (failure.snapshot.latestUserStateClock ?? .distantPast).addingTimeInterval(0.001)
            )
        }
        // The bootstrap gate and account check also protect this narrowly scoped
        // export. A failed request retains the exact same deletion intent for retry.
        return await bootstrapLibraryCloudSyncEnablement().succeeded
    }
}

extension LibrarySyncCoordinator {
    func exportRestorationDiscards(in store: LibraryStore, checkCancellation: () throws -> Void) async throws {
        let pending = store.libraryCloudSyncStatus.restoration?.failures.compactMap(\.tombstone) ?? []
        for tombstone in pending {
            try checkCancellation()
            try Task.checkCancellation()
            let result = try await exporter.export(
                entries: [.delete(.init(tombstone: tombstone))],
                localSnapshotsByIdentity: [:]
            )
            guard result.exportedIdentities.contains(tombstone.identity) else {
                throw LibraryRestorationDiscardError.notConfirmed
            }
            store.updateLibraryCloudSyncStatus { status in
                status.restoration?.failures.removeAll {
                    $0.snapshot.identity == tombstone.identity && $0.discardDate == tombstone.deletedAt
                }
            }
            try checkCancellation()
        }
    }
}

fileprivate enum LibraryRestorationDiscardError: LocalizedError {
    case notConfirmed

    var errorDescription: String? {
        String(localized: "iCloud has not confirmed the deletion. Retry to finish discarding this entry.")
    }
}
