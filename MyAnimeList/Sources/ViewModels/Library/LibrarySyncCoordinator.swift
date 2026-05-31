//
//  LibrarySyncCoordinator.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import DataProvider
import Foundation
import LibrarySync
import os

private let librarySyncCoordinatorLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibrarySync.Coordinator"
)

@MainActor
final class LibrarySyncCoordinator {
    enum Trigger: String {
        case appLaunch
        case foreground
        case cloudNotification
        case manualRetry
    }

    private weak var store: LibraryStore?
    private let client: CloudLibrarySyncClient
    private let importer: CloudLibrarySyncImporter
    private let exporter: CloudLibrarySyncExporter
    private let namespaceProvider: @MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?
    private let hydrateMissingEntry: @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry

    private var isSyncing = false
    private var syncRequestedWhileRunning = false
    private var syncWaiters: [CheckedContinuation<Bool, Never>] = []

    private enum SyncPhase: String {
        case prepareZoneSubscription
        case namespaceResolution
        case remoteFetch
        case hydrationApply
        case tokenCommit
        case dirtyQueueReconciliation
        case export
    }

    init(
        store: LibraryStore,
        client: CloudLibrarySyncClient? = nil,
        database: CloudLibrarySyncDatabase? = nil,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init(),
        namespaceProvider: (@MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?)? = nil,
        hydrateMissingEntry: @escaping @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry =
            LibrarySyncCoordinator.hydrateMissingEntry
    ) {
        let resolvedClient = client ?? CloudLibrarySyncClient(
            container: CKContainer(identifier: CloudLibrarySyncClient.defaultContainerIdentifier)
        )
        let resolvedDatabase =
            database
            ?? resolvedClient.privateDatabase.map(CloudLibrarySyncLiveDatabase.init(database:))

        self.store = store
        self.client = resolvedClient
        self.namespaceProvider = namespaceProvider ?? {
            try await resolvedClient.changeTokenNamespace()
        }
        self.hydrateMissingEntry = hydrateMissingEntry

        if let resolvedDatabase {
            self.importer = CloudLibrarySyncImporter(
                client: resolvedClient,
                database: resolvedDatabase,
                changeTokenStore: changeTokenStore
            )
            self.exporter = CloudLibrarySyncExporter(
                client: resolvedClient,
                database: resolvedDatabase
            )
        } else {
            let disabledDatabase = DisabledCloudLibrarySyncDatabase()
            self.importer = CloudLibrarySyncImporter(
                client: resolvedClient,
                database: disabledDatabase,
                changeTokenStore: changeTokenStore
            )
            self.exporter = CloudLibrarySyncExporter(
                client: resolvedClient,
                database: disabledDatabase
            )
        }
    }

    @discardableResult
    func sync(trigger: Trigger) async -> Bool {
        librarySyncCoordinatorLogger.debug(
            "trigger=\(trigger.rawValue, privacy: .public) action=request isSyncing=\(self.isSyncing, privacy: .public)"
        )
        if isSyncing {
            syncRequestedWhileRunning = true
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) action=coalesced reason=alreadyRunning"
            )
            return await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
        }

        isSyncing = true
        librarySyncCoordinatorLogger.info(
            "trigger=\(trigger.rawValue, privacy: .public) action=start"
        )
        var succeeded = true

        repeat {
            syncRequestedWhileRunning = false
            succeeded = await runSync(trigger: trigger) && succeeded
        } while syncRequestedWhileRunning

        isSyncing = false
        let waiters = syncWaiters
        syncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: succeeded)
        }
        return succeeded
    }

    private func runSync(trigger: Trigger) async -> Bool {
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "trigger=\(trigger.rawValue, privacy: .public) result=skipped reason=missingStore"
            )
            return false
        }
        var currentPhase: SyncPhase?
        var localSnapshotsCount = 0
        var importedSnapshotsCount = 0
        var hydratedEntriesCount = 0
        var appliedSnapshotsCount = 0
        var dirtyEntriesBeforeReconciliation = 0
        var dirtyEntriesAfterReconciliation = 0
        var removedRemoteWonCount = 0
        var keptLocalWonCount = 0
        var importUnaffectedCount = 0
        var exportedEntriesCount = 0
        var remainingDirtyEntriesCount = 0

        do {
            currentPhase = .prepareZoneSubscription
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start"
            )
            try await importer.prepareRemoteSync()
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success"
            )

            currentPhase = .namespaceResolution
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start"
            )
            guard let namespace = try await namespaceProvider() else {
                librarySyncCoordinatorLogger.debug(
                    "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=skipped reason=missingCloudKitNamespace"
                )
                librarySyncCoordinatorLogger.warning(
                    "trigger=\(trigger.rawValue, privacy: .public) result=skipped reason=missingCloudKitNamespace"
                )
                return false
            }
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success"
            )

            let localSnapshots = try localSnapshotsByIdentity(for: store)
            localSnapshotsCount = localSnapshots.count
            currentPhase = .remoteFetch
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start localSnapshotCount=\(localSnapshotsCount, privacy: .public)"
            )
            let importBatch = try await importer.fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshots
            )
            importedSnapshotsCount = importBatch.remoteSnapshots.count
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success modifiedRemoteSnapshotCount=\(importBatch.remoteSnapshots.count, privacy: .public) importedSnapshotCount=\(importBatch.snapshots.count, privacy: .public) ignoredRawDeleteCount=\(importBatch.ignoredDeletedRecordIDs.count, privacy: .public)"
            )

            currentPhase = .hydrationApply
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start importedSnapshotCount=\(importBatch.snapshots.count, privacy: .public)"
            )
            let applyResult = try await apply(importBatch, to: store)
            appliedSnapshotsCount = applyResult.appliedSnapshotsCount
            hydratedEntriesCount = applyResult.hydratedEntriesCount
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success appliedSnapshotCount=\(appliedSnapshotsCount, privacy: .public) hydratedEntryCount=\(hydratedEntriesCount, privacy: .public)"
            )

            currentPhase = .tokenCommit
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start"
            )
            importer.commit(importBatch)
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success"
            )

            currentPhase = .dirtyQueueReconciliation
            let dirtyQueueBefore = store.syncChangeRecorder.dirtyQueueStore.load().entries.count
            dirtyEntriesBeforeReconciliation = dirtyQueueBefore
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start dirtyBefore=\(dirtyQueueBefore, privacy: .public)"
            )
            let reconcileResult = try reconcileDirtyQueue(with: importBatch, in: store)
            dirtyEntriesAfterReconciliation = reconcileResult.dirtyEntriesAfter
            removedRemoteWonCount = reconcileResult.removedRemoteWonCount
            keptLocalWonCount = reconcileResult.keptLocalWonCount
            importUnaffectedCount = reconcileResult.importUnaffectedCount
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success dirtyBefore=\(reconcileResult.dirtyEntriesBefore, privacy: .public) dirtyAfter=\(reconcileResult.dirtyEntriesAfter, privacy: .public) removedRemoteWon=\(removedRemoteWonCount, privacy: .public) keptLocalWon=\(keptLocalWonCount, privacy: .public) importUnaffected=\(importUnaffectedCount, privacy: .public)"
            )

            let postImportSnapshots = try localSnapshotsByIdentity(for: store)
            let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
            currentPhase = .export
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=start dirtyCount=\(dirtyEntries.count, privacy: .public)"
            )
            let exportResult = try await exporter.export(
                entries: dirtyEntries,
                localSnapshotsByIdentity: postImportSnapshots
            )
            exportedEntriesCount = exportResult.exportedIdentities.count
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) action=removeConfirmedDirtyEntries confirmedExportCount=\(exportedEntriesCount, privacy: .public)"
            )
            for identity in exportResult.exportedIdentities {
                try store.syncChangeRecorder.dirtyQueueStore.removeEntry(for: identity)
            }
            remainingDirtyEntriesCount = store.syncChangeRecorder.dirtyQueueStore.load().entries.count
            librarySyncCoordinatorLogger.debug(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(currentPhase!.rawValue, privacy: .public) state=end result=success exportedEntryCount=\(exportedEntriesCount, privacy: .public) remainingDirtyCount=\(remainingDirtyEntriesCount, privacy: .public)"
            )
            librarySyncCoordinatorLogger.info(
                "trigger=\(trigger.rawValue, privacy: .public) result=success localSnapshotCount=\(localSnapshotsCount, privacy: .public) importedSnapshotCount=\(importedSnapshotsCount, privacy: .public) appliedSnapshotCount=\(appliedSnapshotsCount, privacy: .public) hydratedEntryCount=\(hydratedEntriesCount, privacy: .public) dirtyBefore=\(dirtyEntriesBeforeReconciliation, privacy: .public) dirtyAfter=\(dirtyEntriesAfterReconciliation, privacy: .public) removedRemoteWon=\(removedRemoteWonCount, privacy: .public) keptLocalWon=\(keptLocalWonCount, privacy: .public) importUnaffected=\(importUnaffectedCount, privacy: .public) exportedEntryCount=\(exportedEntriesCount, privacy: .public) remainingDirtyCount=\(remainingDirtyEntriesCount, privacy: .public)"
            )
            return true
        } catch {
            let phase = currentPhase?.rawValue ?? "unknown"
            librarySyncCoordinatorLogger.error(
                "trigger=\(trigger.rawValue, privacy: .public) phase=\(phase, privacy: .public) result=degraded errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private func apply(
        _ batch: CloudLibrarySyncImportBatch,
        to store: LibraryStore
    ) async throws -> (appliedSnapshotsCount: Int, hydratedEntriesCount: Int) {
        var appliedSnapshotsCount = 0
        var hydratedEntriesCount = 0
        try await store.syncChangeRecorder.withSuppressedRecording {
            for snapshot in batch.snapshots {
                let applicationTarget = try await entryForApplying(snapshot, store: store)
                guard let applicationTarget else { continue }
                appliedSnapshotsCount += 1
                if applicationTarget.isInitialMaterialization {
                    hydratedEntriesCount += 1
                    try applicationTarget.entry.applyInitialSyncSnapshot(snapshot)
                } else {
                    try applicationTarget.entry.applySyncSnapshot(snapshot)
                }
            }
            try store.repository.save()
        }
        store.rebuildSyncChangeTracking()
        try store.refreshLibrary()
        return (appliedSnapshotsCount, hydratedEntriesCount)
    }

    private func entryForApplying(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore
    ) async throws -> ApplicationTarget? {
        if let entry = store.repository.existingEntry(identity: snapshot.identity) {
            return .init(entry: entry, isInitialMaterialization: false)
        }

        guard snapshot.deletedAt == nil else {
            return nil
        }

        return .init(
            entry: try await hydrateMissingEntry(snapshot, store),
            isInitialMaterialization: true
        )
    }

    private static func hydrateMissingEntry(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore
    ) async throws -> AnimeEntry {
        let latestInfo = try await store.infoFetcher.latestInfo(
            entryType: snapshot.entryType,
            tmdbID: snapshot.tmdbID,
            language: store.language
        )
        let entry = AnimeEntry(fromInfo: latestInfo.0)
        entry.dateSaved = snapshot.dateSaved
        entry.replaceDetail(from: latestInfo.1)

        if let parentSeriesID = snapshot.parentSeriesID {
            if let parentSeriesEntry = store.repository.existingEntry(
                identity: .init(entryType: .series, tmdbID: parentSeriesID)
            ) ?? store.repository.existingEntry(tmdbID: parentSeriesID) {
                entry.parentSeriesEntry = parentSeriesEntry
            } else {
                let parentSeriesEntry = try await AnimeEntry.generateParentSeriesEntryForSeason(
                    parentSeriesID: parentSeriesID,
                    fetcher: store.infoFetcher,
                    infoLanguage: store.language
                )
                store.repository.insert(parentSeriesEntry)
                entry.parentSeriesEntry = parentSeriesEntry
            }
        }

        store.repository.insert(entry)
        return entry
    }

    private func reconcileDirtyQueue(
        with batch: CloudLibrarySyncImportBatch,
        in store: LibraryStore
    ) throws -> (
        dirtyEntriesBefore: Int,
        dirtyEntriesAfter: Int,
        removedRemoteWonCount: Int,
        keptLocalWonCount: Int,
        importUnaffectedCount: Int
    ) {
        let remoteSnapshotsByIdentity = Dictionary(
            uniqueKeysWithValues: batch.remoteSnapshots.map { ($0.identity, $0) }
        )
        let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        var removedRemoteWonCount = 0
        var keptLocalWonCount = 0
        var importUnaffectedCount = 0
        let entries = dirtyEntries.filter { dirtyEntry in
            guard let remoteSnapshot = remoteSnapshotsByIdentity[dirtyEntry.identity] else {
                importUnaffectedCount += 1
                return true
            }
            if remoteSnapshot.isNewer(than: dirtyEntry) {
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

    private func localSnapshotsByIdentity(
        for store: LibraryStore
    ) throws -> [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot] {
        let entries = try store.dataProvider.getAllModels(ofType: AnimeEntry.self)
        return Dictionary(
            uniqueKeysWithValues: entries.map { entry in
                (entry.syncIdentity, LibraryEntrySyncSnapshot(entry: entry))
            }
        )
    }
}

private struct ApplicationTarget {
    let entry: AnimeEntry
    let isInitialMaterialization: Bool
}

private extension LibraryEntrySyncSnapshot {
    func isNewer(than dirtyEntry: LibraryEntrySyncDirtyQueueEntry) -> Bool {
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

private struct DisabledCloudLibrarySyncDatabase: CloudLibrarySyncDatabase {
    enum DisabledError: Error {
        case unavailable
    }

    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        throw DisabledError.unavailable
    }

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        throw DisabledError.unavailable
    }

    func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        throw DisabledError.unavailable
    }
}
