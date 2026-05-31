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

fileprivate let librarySyncCoordinatorLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibrarySync.Coordinator"
)

/// Orchestrates the full local<->CloudKit library sync cycle.
///
/// The coordinator owns the end-to-end sequence: prepare the remote zone,
/// resolve the CloudKit namespace, fetch and apply remote changes, commit the
/// server token, reconcile the local dirty queue, and finally export remaining
/// local edits.
@MainActor
final class LibrarySyncCoordinator {
    enum Trigger: String {
        case appLaunch
        case foreground
        case cloudNotification
        case localDirtyQueueChange
        case manualRetry
    }

    private weak var store: LibraryStore?
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

    /// Creates the coordinator and wires the sync pipeline dependencies.
    ///
    /// - Parameters:
    ///   - store: Owning library store.
    ///   - client: Optional preconfigured CloudKit client for tests or custom
    ///     containers.
    ///   - database: Optional CloudKit database adapter. When omitted, the
    ///     coordinator uses the client's private database if available.
    ///   - changeTokenStore: Storage for zone change tokens.
    ///   - namespaceProvider: Async namespace resolver. This is injected for
    ///     tests and otherwise resolves the current iCloud account through the
    ///     client.
    ///   - hydrateMissingEntry: Entry hydration hook used when remote state
    ///     refers to an entry the local store does not currently have.
    init(
        store: LibraryStore,
        client: CloudLibrarySyncClient? = nil,
        database: CloudLibrarySyncDatabase? = nil,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init(),
        namespaceProvider: (@MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?)? = nil,
        hydrateMissingEntry: @escaping @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry =
            LibrarySyncCoordinator.hydrateMissingEntry
    ) {
        let resolvedClient =
            client
            ?? CloudLibrarySyncClient(
                container: CKContainer(identifier: CloudLibrarySyncClient.defaultContainerIdentifier)
            )
        let resolvedDatabase =
            database
            ?? resolvedClient.privateDatabase.map(CloudLibrarySyncLiveDatabase.init(database:))

        self.store = store
        self.namespaceProvider =
            namespaceProvider ?? {
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
    /// Runs one coalesced sync pass for the requested trigger.
    ///
    /// Concurrent requests are serialized and merged so callers do not start
    /// overlapping CloudKit work.
    func sync(trigger: Trigger) async -> Bool {
        if isSyncing {
            syncRequestedWhileRunning = true
            librarySyncCoordinatorLogger.info(
                "Queued iCloud library sync for \(trigger.rawValue, privacy: .public) while another sync was already running."
            )
            return await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
        }

        isSyncing = true
        librarySyncCoordinatorLogger.info(
            "Starting iCloud library sync triggered by \(trigger.rawValue, privacy: .public)."
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

    /// Executes the ordered sync phases once.
    private func runSync(trigger: Trigger) async -> Bool {
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because the library store was unavailable."
            )
            return false
        }
        var currentPhase: SyncPhase?

        do {
            currentPhase = .prepareZoneSubscription
            try await importer.prepareRemoteSync()

            currentPhase = .namespaceResolution
            guard let namespace = try await namespaceProvider() else {
                librarySyncCoordinatorLogger.warning(
                    "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because no iCloud account namespace was available."
                )
                return false
            }

            let localSnapshots = try localSnapshotsByIdentity(for: store)
            currentPhase = .remoteFetch
            let importBatch = try await importer.fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshots
            )

            currentPhase = .hydrationApply
            _ = try await apply(importBatch, to: store)

            currentPhase = .tokenCommit
            importer.commit(importBatch)

            currentPhase = .dirtyQueueReconciliation
            _ = try reconcileDirtyQueue(with: importBatch, in: store)

            let postImportSnapshots = try localSnapshotsByIdentity(for: store)
            let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
            currentPhase = .export
            let exportResult = try await exporter.export(
                entries: dirtyEntries,
                localSnapshotsByIdentity: postImportSnapshots
            )
            for identity in exportResult.exportedIdentities {
                try store.syncChangeRecorder.dirtyQueueStore.removeEntry(for: identity)
                librarySyncCoordinatorLogger.info(
                    "Removed \(identity.rawID, privacy: .private) from the iCloud sync dirty queue after export."
                )
            }
            librarySyncCoordinatorLogger.info(
                "Finished iCloud library sync triggered by \(trigger.rawValue, privacy: .public)."
            )
            return true
        } catch {
            let phase = currentPhase?.rawValue ?? "unknown"
            librarySyncCoordinatorLogger.error(
                "iCloud library sync triggered by \(trigger.rawValue, privacy: .public) failed during \(phase, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    /// Applies remote changes to local entries, hydrating missing snapshots first.
    ///
    /// The method suppresses change recording while the imported changes are
    /// written so the local save pass does not enqueue its own changes.
    private func apply(
        _ batch: CloudLibrarySyncImportBatch,
        to store: LibraryStore
    ) async throws -> (appliedChangesCount: Int, hydratedEntriesCount: Int) {
        var appliedChangesCount = 0
        var hydratedEntriesCount = 0
        try await store.syncChangeRecorder.withSuppressedRecordingAsync {
            for change in batch.changes {
                switch change {
                case .snapshot(let snapshot):
                    let applicationTarget = try await entryForApplying(snapshot, store: store)
                    guard let applicationTarget else { continue }
                    appliedChangesCount += 1
                    if applicationTarget.isInitialMaterialization {
                        hydratedEntriesCount += 1
                        try applicationTarget.entry.applyInitialSyncSnapshot(snapshot)
                    } else {
                        try applicationTarget.entry.applySyncSnapshot(snapshot)
                    }
                case .tombstone(let tombstone):
                    guard let entry = store.repository.existingEntry(identity: tombstone.identity) else {
                        continue
                    }
                    appliedChangesCount += 1
                    try entry.applySyncTombstone(tombstone)
                }
            }
            try store.repository.save()
        }
        store.rebuildSyncChangeTracking()
        try store.refreshLibrary()
        return (appliedChangesCount, hydratedEntriesCount)
    }

    /// Returns the local entry to update, hydrating a new one when needed.
    private func entryForApplying(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore
    ) async throws -> ApplicationTarget? {
        if let entry = store.repository.existingEntry(identity: snapshot.identity) {
            return .init(entry: entry, isInitialMaterialization: false)
        }

        return .init(
            entry: try await hydrateMissingEntry(snapshot, store),
            isInitialMaterialization: true
        )
    }

    /// Rebuilds a missing local entry from TMDb before remote data is applied.
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

    /// Drops queued local edits that were superseded by newer remote changes.
    ///
    /// - Returns: Pre/post dirty counts plus diagnostic counts for queue
    ///   reconciliation decisions.
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
        let remoteChangesByIdentity = Dictionary(
            uniqueKeysWithValues: batch.remoteChanges.map { ($0.identity, $0) }
        )
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

fileprivate struct ApplicationTarget {
    let entry: AnimeEntry
    let isInitialMaterialization: Bool
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

fileprivate struct DisabledCloudLibrarySyncDatabase: CloudLibrarySyncDatabase {
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
