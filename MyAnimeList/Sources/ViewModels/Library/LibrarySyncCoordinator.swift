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
        if isSyncing {
            syncRequestedWhileRunning = true
            return await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
        }

        isSyncing = true
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
        guard let store else { return false }

        do {
            try await importer.prepareRemoteSync()
            guard let namespace = try await namespaceProvider() else {
                libraryStoreLogger.warning(
                    "Skipping library sync \(trigger.rawValue, privacy: .public): missing CloudKit namespace"
                )
                return false
            }

            let localSnapshots = try localSnapshotsByIdentity(for: store)
            let importBatch = try await importer.fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshots
            )
            try await apply(importBatch, to: store)
            importer.commit(importBatch)

            try reconcileDirtyQueue(with: importBatch, in: store)
            let postImportSnapshots = try localSnapshotsByIdentity(for: store)
            let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
            let exportResult = try await exporter.export(
                entries: dirtyEntries,
                localSnapshotsByIdentity: postImportSnapshots
            )
            for identity in exportResult.exportedIdentities {
                try store.syncChangeRecorder.dirtyQueueStore.removeEntry(for: identity)
            }
            return true
        } catch {
            libraryStoreLogger.error(
                "Library sync \(trigger.rawValue, privacy: .public) degraded: \(error.localizedDescription)"
            )
            return false
        }
    }

    private func apply(
        _ batch: CloudLibrarySyncImportBatch,
        to store: LibraryStore
    ) async throws {
        try await store.syncChangeRecorder.withSuppressedRecording {
            for snapshot in batch.snapshots {
                let applicationTarget = try await entryForApplying(snapshot, store: store)
                guard let applicationTarget else { continue }
                if applicationTarget.isInitialMaterialization {
                    try applicationTarget.entry.applyInitialSyncSnapshot(snapshot)
                } else {
                    try applicationTarget.entry.applySyncSnapshot(snapshot)
                }
            }
            try store.repository.save()
        }
        store.rebuildSyncChangeTracking()
        try store.refreshLibrary()
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
    ) throws {
        let remoteSnapshotsByIdentity = Dictionary(
            uniqueKeysWithValues: batch.remoteSnapshots.map { ($0.identity, $0) }
        )
        let entries = store.syncChangeRecorder.dirtyQueueStore.load().entries.filter { dirtyEntry in
            guard let remoteSnapshot = remoteSnapshotsByIdentity[dirtyEntry.identity] else {
                return true
            }
            return !remoteSnapshot.isNewer(than: dirtyEntry)
        }
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(entries)
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
