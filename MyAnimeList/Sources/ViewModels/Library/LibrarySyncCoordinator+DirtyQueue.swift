//
//  LibrarySyncCoordinator+DirtyQueue.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import DataProvider
import Foundation
import LibrarySync
import os

extension LibrarySyncCoordinator {
    func seedDirtyQueue(
        with snapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        at date: Date,
        in store: LibraryStore
    ) throws {
        var entriesByID = store.syncChangeRecorder.dirtyQueueStore.load().entries.reduce(
            into: [String: LibraryEntrySyncDirtyQueueEntry]()
        ) { entriesByID, entry in
            entriesByID[entry.identity.rawID] = entry
        }

        for snapshot in snapshotsByIdentity.values {
            let pendingUpsert = LibraryEntrySyncPendingUpsert(
                identity: snapshot.identity,
                dirtyAt: bootstrapDirtyClock(for: snapshot) ?? date
            )
            entriesByID[snapshot.identity.rawID] = .upsert(pendingUpsert)
        }

        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(Array(entriesByID.values))
    }

    func removeExportedDirtyEntries(
        _ exportedIdentities: Set<LibraryEntrySyncIdentity>,
        from dirtyEntries: [LibraryEntrySyncDirtyQueueEntry],
        in store: LibraryStore
    ) throws {
        let dirtyEntriesByIdentity = Self.coalescedDirtyEntriesByIdentity(dirtyEntries)
        for identity in exportedIdentities {
            guard let exportedEntry = dirtyEntriesByIdentity[identity] else { continue }
            let removed: Bool
            if dirtyEntries.filter({ $0.identity == identity }).count > 1 {
                removed = try removeExportedDuplicateDirtyEntries(
                    for: identity,
                    matching: dirtyEntries.filter { $0.identity == identity },
                    selectedEntry: exportedEntry,
                    in: store
                )
            } else {
                removed = try store.syncChangeRecorder.dirtyQueueStore.removeEntry(
                    for: identity,
                    ifCurrentEntryMatches: exportedEntry
                )
            }
            if removed {
                librarySyncCoordinatorLogger.info(
                    "Removed \(identity.rawID, privacy: .private) from the iCloud sync dirty queue after export."
                )
            } else {
                librarySyncCoordinatorLogger.info(
                    "Kept \(identity.rawID, privacy: .private) in the iCloud sync dirty queue because newer local work was queued during export."
                )
            }
        }
    }

    private func removeExportedDuplicateDirtyEntries(
        for identity: LibraryEntrySyncIdentity,
        matching observedEntries: [LibraryEntrySyncDirtyQueueEntry],
        selectedEntry: LibraryEntrySyncDirtyQueueEntry,
        in store: LibraryStore
    ) throws -> Bool {
        let currentEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        let currentEntriesForIdentity = currentEntries.filter { $0.identity == identity }
        guard currentEntriesForIdentity == observedEntries || currentEntriesForIdentity == [selectedEntry] else {
            librarySyncCoordinatorLogger.info(
                "Kept duplicate dirty-queue entries for \(identity.rawID, privacy: .private) because local work changed during export confirmation."
            )
            return false
        }

        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(
            currentEntries.filter { $0.identity != identity }
        )
        librarySyncCoordinatorLogger.info(
            "Removed \(currentEntriesForIdentity.count, privacy: .public) duplicate dirty-queue entries for \(identity.rawID, privacy: .private) after export."
        )
        return true
    }

    func export(
        entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        settingsSnapshot: LibrarySettingsSyncSnapshot?,
        observedDirtyEntries: [LibraryEntrySyncDirtyQueueEntry],
        store: LibraryStore
    ) async throws -> CloudLibrarySyncExportResult {
        do {
            return try await exporter.export(
                entries: entries,
                localSnapshotsByIdentity: localSnapshotsByIdentity,
                settingsSnapshot: settingsSnapshot
            )
        } catch let failure as CloudLibrarySyncExportFailure {
            try reconcilePartialExportFailure(
                failure,
                observedDirtyEntries: observedDirtyEntries,
                settingsSnapshot: settingsSnapshot,
                in: store
            )
            throw failure.underlyingError
        }
    }

    private func reconcilePartialExportFailure(
        _ failure: CloudLibrarySyncExportFailure,
        observedDirtyEntries: [LibraryEntrySyncDirtyQueueEntry],
        settingsSnapshot: LibrarySettingsSyncSnapshot?,
        in store: LibraryStore
    ) throws {
        logSettingsExportResult(
            settingsSnapshot,
            exportResult: failure.partialResult
        )
        try removeExportedDirtyEntries(
            failure.partialResult.exportedIdentities,
            from: observedDirtyEntries,
            in: store
        )

        guard settingsSnapshot != nil else { return }
        let reconciledSettingsUpdatedAt =
            reconciledCloudSyncedSettingsUpdatedAt(
                store: store,
                exportedSnapshot: settingsSnapshot,
                settingsExported: failure.partialResult.settingsExported
            )
        store.updateLibraryCloudSyncStatus { status in
            status.lastReconciledCloudSyncedSettingsUpdatedAt =
                reconciledSettingsUpdatedAt
        }
    }


    /// Drops queued local edits that were superseded by newer remote changes.
    ///
    /// - Returns: Pre/post dirty counts plus diagnostic counts for queue
    ///   reconciliation decisions.
    func reconcileDirtyQueue(
        with batch: CloudLibrarySyncImportBatch,
        in store: LibraryStore
    ) throws -> (
        dirtyEntriesBefore: Int,
        dirtyEntriesAfter: Int,
        removedRemoteWonCount: Int,
        keptLocalWonCount: Int,
        importUnaffectedCount: Int
    ) {
        let remoteChangesByIdentity = try Self.coalescedRemoteChangesByIdentity(batch.changes)
        let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        var removedRemoteWonCount = 0
        var keptLocalWonCount = 0
        var importUnaffectedCount = 0
        let entries = dirtyEntries.filter { dirtyEntry in
            guard let remoteChange = remoteChangesByIdentity[dirtyEntry.identity] else {
                importUnaffectedCount += 1
                return true
            }
            if remoteChange.isNewer(than: dirtyEntry) {
                removedRemoteWonCount += 1
                return false
            }
            keptLocalWonCount += 1
            return true
        }
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(entries)
        return (
            dirtyEntriesBefore: dirtyEntries.count,
            dirtyEntriesAfter: entries.count,
            removedRemoteWonCount: removedRemoteWonCount,
            keptLocalWonCount: keptLocalWonCount,
            importUnaffectedCount: importUnaffectedCount
        )
    }


    /// Builds the current local snapshot map used by importer and exporter.
    func localSnapshotsByIdentity(
        for store: LibraryStore
    ) throws -> [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot] {
        let entries = try store.dataProvider.getAllModels(ofType: AnimeEntry.self)
        var entriesByIdentity: [LibraryEntrySyncIdentity: AnimeEntry] = [:]
        var duplicateCountsByIdentity: [LibraryEntrySyncIdentity: Int] = [:]

        for entry in entries {
            let identity = entry.syncIdentity
            guard let existingEntry = entriesByIdentity[identity] else {
                entriesByIdentity[identity] = entry
                duplicateCountsByIdentity[identity] = 1
                continue
            }

            duplicateCountsByIdentity[identity, default: 1] += 1
            if AnimeEntryDuplicateResolver.prefers(entry, existingEntry) {
                entriesByIdentity[identity] = entry
            }
        }

        for (identity, count) in duplicateCountsByIdentity where count > 1 {
            librarySyncCoordinatorLogger.warning(
                "Found \(count, privacy: .public) local library rows for iCloud sync identity \(identity.rawID, privacy: .private); using the preferred local row for sync snapshot generation."
            )
        }

        return entriesByIdentity.reduce(into: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]()) {
            snapshotsByIdentity, pair in
            snapshotsByIdentity[pair.key] = LibraryEntrySyncSnapshot(entry: pair.value)
        }
    }

    static func coalescedDirtyEntriesByIdentity(
        _ dirtyEntries: [LibraryEntrySyncDirtyQueueEntry]
    ) -> [LibraryEntrySyncIdentity: LibraryEntrySyncDirtyQueueEntry] {
        var entriesByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncDirtyQueueEntry] = [:]
        var duplicateCountsByIdentity: [LibraryEntrySyncIdentity: Int] = [:]

        for entry in dirtyEntries {
            let identity = entry.identity
            if entriesByIdentity[identity] != nil {
                duplicateCountsByIdentity[identity, default: 1] += 1
            } else {
                duplicateCountsByIdentity[identity] = 1
            }
            entriesByIdentity[identity] = entry
        }

        for (identity, count) in duplicateCountsByIdentity where count > 1 {
            librarySyncCoordinatorLogger.warning(
                "Found \(count, privacy: .public) dirty-queue entries for iCloud sync identity \(identity.rawID, privacy: .private); using the last queued entry for export confirmation."
            )
        }

        return entriesByIdentity
    }
    static func coalescedRemoteChangesByIdentity(
        _ remoteChanges: [LibraryEntrySyncRemoteChange]
    ) throws -> [LibraryEntrySyncIdentity: LibraryEntrySyncRemoteChange] {
        var changesByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncRemoteChange] = [:]
        var duplicateCountsByIdentity: [LibraryEntrySyncIdentity: Int] = [:]

        for remoteChange in remoteChanges {
            let identity = remoteChange.identity
            if let existingChange = changesByIdentity[identity] {
                changesByIdentity[identity] = try existingChange.merged(with: remoteChange)
                duplicateCountsByIdentity[identity, default: 1] += 1
            } else {
                changesByIdentity[identity] = remoteChange
                duplicateCountsByIdentity[identity] = 1
            }
        }

        for (identity, count) in duplicateCountsByIdentity where count > 1 {
            librarySyncCoordinatorLogger.warning(
                "Found \(count, privacy: .public) remote changes for iCloud sync identity \(identity.rawID, privacy: .private); merged them before dirty-queue reconciliation."
            )
        }

        return changesByIdentity
    }
}

fileprivate func bootstrapDirtyClock(for snapshot: LibraryEntrySyncSnapshot) -> Date? {
    [
        snapshot.libraryUpdatedAt,
        snapshot.trackingUpdatedAt,
        snapshot.episodeProgresses.map(\.updatedAt).max()
    ]
    .compactMap(\.self)
    .max()
}

fileprivate func isNewer(_ candidate: Date?, than existing: Date?) -> Bool {
    guard let candidate else { return false }
    guard let existing else { return true }
    return candidate > existing
}

extension LibraryEntrySyncRemoteChange {
    /// Returns true when this remote snapshot is newer than the queued local work.
    ///
    /// Upserts compare against the local dirty timestamp, while deletes compare
    /// against the tombstone's delete clock.
    fileprivate func isNewer(than dirtyEntry: LibraryEntrySyncDirtyQueueEntry) -> Bool {
        switch dirtyEntry {
        case .upsert(let pendingUpsert):
            guard let latestSyncClock else { return false }
            return latestSyncClock > pendingUpsert.dirtyAt
        case .delete(let pendingDelete):
            guard let latestSyncClock else { return false }
            return latestSyncClock > pendingDelete.tombstone.deletedAt
        }
    }
}

extension LibraryEntrySyncSnapshot {
    func isNotNewerThanPendingDelete(
        _ dirtyEntry: LibraryEntrySyncDirtyQueueEntry?
    ) -> Bool {
        guard case .delete(let pendingDelete) = dirtyEntry else { return false }
        let snapshotClock = latestUserStateClock ?? .distantPast
        return snapshotClock <= pendingDelete.tombstone.deletedAt
    }
}
