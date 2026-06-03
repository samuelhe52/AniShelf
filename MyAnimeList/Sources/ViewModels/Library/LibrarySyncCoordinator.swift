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
import SwiftUI
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
        case firstEnableBootstrap
    }

    enum SyncResult: Equatable {
        case success
        case skipped(LibraryCloudSyncPolicyBlockReason)
        case conflictChoiceRequired
        case retryableFailure
        case permanentFailure

        var succeeded: Bool {
            self == .success
        }

        var resultClass: LibraryCloudSyncResultClass {
            switch self {
            case .success:
                .success
            case .skipped(_):
                .skipped
            case .conflictChoiceRequired:
                .conflictChoiceRequired
            case .retryableFailure:
                .retryableFailure
            case .permanentFailure:
                .permanentFailure
            }
        }
    }

    private weak var store: LibraryStore?
    private let importer: CloudLibrarySyncImporter
    private let exporter: CloudLibrarySyncExporter
    private let namespaceProvider: @MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?
    private let hydrateMissingEntry: @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry
    private let dateProvider: @MainActor @Sendable () -> Date

    private var isSyncing = false
    private var syncRequestedWhileRunning = false
    private var syncWaiters: [CheckedContinuation<SyncResult, Never>] = []
    private var activeFirstEnableBootstrapIDs = Set<UUID>()
    private var canceledFirstEnableBootstrapIDs = Set<UUID>()

    private typealias SyncPhase = LibraryCloudSyncPhase

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
    ///   - dateProvider: Clock injection for status timestamps and tests.
    init(
        store: LibraryStore,
        client: CloudLibrarySyncClient? = nil,
        database: CloudLibrarySyncDatabase? = nil,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init(),
        namespaceProvider: (@MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?)? = nil,
        hydrateMissingEntry: @escaping @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry =
            LibrarySyncCoordinator.hydrateMissingEntry,
        dateProvider: @escaping @MainActor @Sendable () -> Date = { .now }
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
        self.dateProvider = dateProvider

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
        await syncResult(trigger: trigger).succeeded
    }

    /// Runs one coalesced sync pass and preserves failure classification for
    /// local dirty-queue retry scheduling.
    func syncResult(trigger: Trigger) async -> SyncResult {
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because the library store was unavailable."
            )
            return .permanentFailure
        }
        if isSyncing {
            syncRequestedWhileRunning = true
            librarySyncCoordinatorLogger.info(
                "Queued iCloud library sync for \(trigger.rawValue, privacy: .public) while another sync was already running."
            )
            return await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
        }
        if let blockedReason = store.libraryCloudSyncPolicyBlockReason() {
            store.recordLibraryCloudSyncSkipped(
                trigger: trigger,
                reason: blockedReason,
                at: dateProvider()
            )
            librarySyncCoordinatorLogger.info(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because policy blocked ordinary sync: \(blockedReason.rawValue, privacy: .public)."
            )
            return .skipped(blockedReason)
        }

        isSyncing = true
        librarySyncCoordinatorLogger.info(
            "Starting iCloud library sync triggered by \(trigger.rawValue, privacy: .public)."
        )
        var result = SyncResult.success

        repeat {
            syncRequestedWhileRunning = false
            result = result.merged(with: await runSync(trigger: trigger))
        } while syncRequestedWhileRunning

        isSyncing = false
        let waiters = syncWaiters
        syncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
        return result
    }

    /// Executes the ordered sync phases once.
    private func runSync(trigger: Trigger) async -> SyncResult {
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because the library store was unavailable."
            )
            return .permanentFailure
        }
        var currentPhase: SyncPhase?

        do {
            currentPhase = .prepareZoneSubscription
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .prepareZoneSubscription,
                at: dateProvider()
            )
            try await importer.prepareRemoteSync()

            currentPhase = .namespaceResolution
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .namespaceResolution,
                at: dateProvider()
            )
            guard let namespace = try await resolveNamespace(reportingTo: store) else {
                librarySyncCoordinatorLogger.warning(
                    "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because no iCloud account namespace was available."
                )
                store.recordLibraryCloudSyncFailure(
                    trigger: trigger,
                    phase: currentPhase,
                    result: .permanentFailure,
                    reason: "No iCloud account namespace was available.",
                    degradedReason: "iCloud library sync is blocked until iCloud account access is available.",
                    at: dateProvider()
                )
                return .permanentFailure
            }

            let localSnapshots = try localSnapshotsByIdentity(for: store)
            currentPhase = .remoteFetch
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .remoteFetch,
                at: dateProvider()
            )
            let importBatch = try await importer.fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshots
            )

            currentPhase = .hydrationApply
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .hydrationApply,
                at: dateProvider()
            )
            _ = try await applyImportedChanges(importBatch, to: store)

            currentPhase = .tokenCommit
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .tokenCommit,
                at: dateProvider()
            )
            importer.commit(importBatch)

            currentPhase = .libraryRefresh
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .libraryRefresh,
                at: dateProvider()
            )
            try refreshLibraryAfterImport(in: store)

            currentPhase = .dirtyQueueReconciliation
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .dirtyQueueReconciliation,
                at: dateProvider()
            )
            _ = try reconcileDirtyQueue(with: importBatch, in: store)

            let postImportSnapshots = try localSnapshotsByIdentity(for: store)
            let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
            currentPhase = .export
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .export,
                at: dateProvider()
            )
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
            store.recordLibraryCloudSyncSuccess(
                trigger: trigger,
                completedBootstrap: false,
                at: dateProvider()
            )
            return .success
        } catch {
            let phase = currentPhase?.rawValue ?? "unknown"
            librarySyncCoordinatorLogger.error(
                "iCloud library sync triggered by \(trigger.rawValue, privacy: .public) failed during \(phase, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            let result: SyncResult = error.isPermanentLibrarySyncFailure ? .permanentFailure : .retryableFailure
            store.recordLibraryCloudSyncFailure(
                trigger: trigger,
                phase: currentPhase,
                result: result.resultClass,
                reason: error.localizedDescription,
                degradedReason: result == .permanentFailure
                    ? "iCloud library sync is blocked by a permanent failure."
                    : nil,
                at: dateProvider()
            )
            return result
        }
    }

    /// Runs the first-enable bootstrap flow.
    ///
    /// The bootstrap prepares CloudKit, fetches remote changes before any
    /// export, pauses on ambiguous clockless conflicts, and otherwise seeds the
    /// existing local library into the dirty queue before continuing through the
    /// normal import-before-export pass.
    func bootstrapFirstEnablement(
        preference: LibraryCloudSyncConflictPreference?
    ) async -> SyncResult {
        let bootstrapID = UUID()
        if isSyncing {
            syncRequestedWhileRunning = true
            librarySyncCoordinatorLogger.info(
                "Queued iCloud library first-enable bootstrap while another sync was already running."
            )
            return await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
        }

        isSyncing = true
        activeFirstEnableBootstrapIDs.insert(bootstrapID)
        var result = await runFirstEnableBootstrap(
            preference: preference,
            bootstrapID: bootstrapID
        )
        activeFirstEnableBootstrapIDs.remove(bootstrapID)
        canceledFirstEnableBootstrapIDs.remove(bootstrapID)
        if result == .success {
            while syncRequestedWhileRunning {
                syncRequestedWhileRunning = false
                result = result.merged(with: await runSync(trigger: .firstEnableBootstrap))
            }
        }
        isSyncing = false
        if result == .conflictChoiceRequired, !syncWaiters.isEmpty {
            return result
        }
        let waiters = syncWaiters
        syncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: result)
        }
        return result
    }

    func cancelFirstEnableBootstrap() {
        canceledFirstEnableBootstrapIDs.formUnion(activeFirstEnableBootstrapIDs)
        syncRequestedWhileRunning = false
        let waiters = syncWaiters
        syncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: .skipped(.disabled))
        }
    }

    private func runFirstEnableBootstrap(
        preference: LibraryCloudSyncConflictPreference?,
        bootstrapID: UUID
    ) async -> SyncResult {
        let trigger = Trigger.firstEnableBootstrap
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library first-enable bootstrap because the library store was unavailable."
            )
            return .permanentFailure
        }

        store.updateLibraryCloudSyncStatus { status in
            status.isEnabled = true
            status.bootstrapState = .running
            if preference != nil {
                status.pendingConflictSummary = nil
            }
            status.lastFailureReason = nil
        }

        var currentPhase: SyncPhase?
        do {
            try checkFirstEnableBootstrapCancellation(bootstrapID)
            currentPhase = .prepareZoneSubscription
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .prepareZoneSubscription,
                at: dateProvider()
            )
            try await importer.prepareRemoteSync()
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .namespaceResolution
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .namespaceResolution,
                at: dateProvider()
            )
            guard let namespace = try await resolveNamespace(reportingTo: store) else {
                store.recordLibraryCloudSyncFailure(
                    trigger: trigger,
                    phase: currentPhase,
                    result: .permanentFailure,
                    reason: "No iCloud account namespace was available.",
                    degradedReason:
                        "iCloud library sync enablement is blocked until iCloud account access is available.",
                    at: dateProvider()
                )
                store.updateLibraryCloudSyncStatus { status in
                    status.bootstrapState = .failed
                }
                return .permanentFailure
            }
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .remoteFetch
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .remoteFetch,
                at: dateProvider()
            )
            let preImportSnapshots = try localSnapshotsByIdentity(for: store)
            let fetchedBatch = try await importer.fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: preImportSnapshots
            )
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .conflictDetection
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .conflictDetection,
                at: dateProvider()
            )
            let ambiguousConflicts = ambiguousConflicts(
                localSnapshotsByIdentity: preImportSnapshots,
                remoteChanges: fetchedBatch.remoteChanges
            )
            if preference == nil, !ambiguousConflicts.isEmpty {
                store.recordLibraryCloudSyncConflictNeeded(
                    summary: ambiguousConflicts.summary,
                    at: dateProvider()
                )
                librarySyncCoordinatorLogger.info(
                    "Paused iCloud library first-enable bootstrap because \(ambiguousConflicts.summary.entryCount, privacy: .public) overlapping entries need a conflict preference."
                )
                return .conflictChoiceRequired
            }

            try checkFirstEnableBootstrapCancellation(bootstrapID)
            if preference == .preferLocal, !ambiguousConflicts.isEmpty {
                try stampLocalClocks(
                    for: ambiguousConflicts,
                    at: dateProvider(),
                    in: store
                )
            }
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            let decisionSnapshots = try localSnapshotsByIdentity(for: store)
            currentPhase = .dirtyQueueSeeding
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .dirtyQueueSeeding,
                at: dateProvider()
            )
            try seedDirtyQueue(
                with: decisionSnapshots,
                at: dateProvider(),
                in: store
            )
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            var importBatch = fetchedBatch
            if let preference {
                importBatch = try resolvedBatch(
                    from: fetchedBatch,
                    localSnapshotsByIdentity: decisionSnapshots,
                    conflicts: ambiguousConflicts,
                    preference: preference
                )
                if preference == .preferCloud {
                    try dropCloudSupersededDirtyWork(
                        conflicts: ambiguousConflicts,
                        localSnapshotsByIdentity: preImportSnapshots,
                        remoteChanges: fetchedBatch.remoteChanges,
                        in: store
                    )
                }
            }
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .hydrationApply
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .hydrationApply,
                at: dateProvider()
            )
            _ = try await applyImportedChanges(
                importBatch,
                to: store,
                forcedDomainsByIdentity: preference == .preferCloud
                    ? ambiguousConflicts.domainsByIdentity
                    : [:]
            )
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .tokenCommit
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .tokenCommit,
                at: dateProvider()
            )
            importer.commit(importBatch)
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .libraryRefresh
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .libraryRefresh,
                at: dateProvider()
            )
            try refreshLibraryAfterImport(in: store)
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            currentPhase = .dirtyQueueReconciliation
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .dirtyQueueReconciliation,
                at: dateProvider()
            )
            _ = try reconcileDirtyQueue(with: importBatch, in: store)
            try checkFirstEnableBootstrapCancellation(bootstrapID)

            let postImportSnapshots = try localSnapshotsByIdentity(for: store)
            let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
            currentPhase = .export
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: .export,
                at: dateProvider()
            )
            try checkFirstEnableBootstrapCancellation(bootstrapID)
            let exportResult = try await exporter.export(
                entries: dirtyEntries,
                localSnapshotsByIdentity: postImportSnapshots
            )
            for identity in exportResult.exportedIdentities {
                try store.syncChangeRecorder.dirtyQueueStore.removeEntry(for: identity)
            }

            store.recordLibraryCloudSyncSuccess(
                trigger: trigger,
                completedBootstrap: true,
                at: dateProvider()
            )
            librarySyncCoordinatorLogger.info(
                "Finished iCloud library first-enable bootstrap."
            )
            return .success
        } catch FirstEnableBootstrapCancellation.cancelled {
            librarySyncCoordinatorLogger.info(
                "Cancelled iCloud library first-enable bootstrap."
            )
            return .skipped(.disabled)
        } catch {
            let result: SyncResult = error.isPermanentLibrarySyncFailure ? .permanentFailure : .retryableFailure
            store.recordLibraryCloudSyncFailure(
                trigger: trigger,
                phase: currentPhase,
                result: result.resultClass,
                reason: error.localizedDescription,
                degradedReason: result == .permanentFailure
                    ? "iCloud library sync enablement is blocked by a permanent failure."
                    : nil,
                at: dateProvider()
            )
            store.updateLibraryCloudSyncStatus { status in
                status.bootstrapState = .failed
            }
            librarySyncCoordinatorLogger.error(
                "iCloud library first-enable bootstrap failed during \(currentPhase?.rawValue ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
            return result
        }
    }

    private func resolveNamespace(
        reportingTo store: LibraryStore
    ) async throws -> CloudLibrarySyncChangeTokenStore.Namespace? {
        do {
            let namespace = try await namespaceProvider()
            store.updateLibraryCloudKitAvailability(namespace == nil ? .noAccount : .available)
            return namespace
        } catch {
            store.updateLibraryCloudKitAvailability(error.libraryCloudKitAvailability)
            throw error
        }
    }

    private func checkFirstEnableBootstrapCancellation(_ bootstrapID: UUID) throws {
        if canceledFirstEnableBootstrapIDs.contains(bootstrapID) {
            throw FirstEnableBootstrapCancellation.cancelled
        }
    }

    private func seedDirtyQueue(
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

    private func resolvedBatch(
        from batch: CloudLibrarySyncImportBatch,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        conflicts: AmbiguousConflictSet,
        preference: LibraryCloudSyncConflictPreference
    ) throws -> CloudLibrarySyncImportBatch {
        let changes = try batch.remoteChanges.map { remoteChange -> LibraryEntrySyncRemoteChange in
            var resolvedChange = try resolvedChange(
                remoteChange,
                localSnapshotsByIdentity: localSnapshotsByIdentity
            )
            guard case .snapshot(var resolvedSnapshot) = resolvedChange,
                case .snapshot(let remoteSnapshot) = remoteChange,
                let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity],
                let conflict = conflicts.conflictsByIdentity[remoteSnapshot.identity]
            else {
                return resolvedChange
            }

            switch preference {
            case .preferCloud:
                apply(conflict.domains, from: remoteSnapshot, to: &resolvedSnapshot)
            case .preferLocal:
                apply(conflict.domains, from: localSnapshot, to: &resolvedSnapshot)
            }
            resolvedChange = .snapshot(resolvedSnapshot)
            return resolvedChange
        }

        return .init(
            changes: changes,
            remoteChanges: batch.remoteChanges,
            ignoredDeletedRecordIDs: batch.ignoredDeletedRecordIDs,
            changeToken: batch.changeToken,
            namespace: batch.namespace,
            zoneID: batch.zoneID
        )
    }

    private func resolvedChange(
        _ remoteChange: LibraryEntrySyncRemoteChange,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) throws -> LibraryEntrySyncRemoteChange {
        guard case .snapshot(let remoteSnapshot) = remoteChange,
            let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity]
        else {
            return remoteChange
        }
        return .snapshot(try localSnapshot.merged(with: remoteSnapshot))
    }

    private func stampLocalClocks(
        for conflicts: AmbiguousConflictSet,
        at date: Date,
        in store: LibraryStore
    ) throws {
        guard !conflicts.isEmpty else { return }
        let entries = try store.dataProvider.getAllModels(ofType: AnimeEntry.self)
        var changed = false
        try store.syncChangeRecorder.withSuppressedRecording {
            for entry in entries {
                guard let conflict = conflicts.conflictsByIdentity[entry.syncIdentity] else {
                    continue
                }
                if conflict.domains.contains(.library), entry.libraryUpdatedAt == nil {
                    entry.libraryUpdatedAt = date
                    changed = true
                }
                if conflict.domains.contains(.tracking), entry.trackingUpdatedAt == nil {
                    entry.trackingUpdatedAt = date
                    changed = true
                }
            }
            if changed {
                try store.repository.save()
            }
        }
        if changed {
            store.rebuildSyncChangeTracking()
        }
    }

    private func dropCloudSupersededDirtyWork(
        conflicts: AmbiguousConflictSet,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        remoteChanges: [LibraryEntrySyncRemoteChange],
        in store: LibraryStore
    ) throws {
        guard !conflicts.isEmpty else { return }
        let remoteSnapshotsByIdentity = remoteChanges.reduce(
            into: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]()
        ) { snapshotsByIdentity, remoteChange in
            guard case .snapshot(let snapshot) = remoteChange else { return }
            snapshotsByIdentity[snapshot.identity] = snapshot
        }

        let retainedEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries.filter { entry in
            guard let conflict = conflicts.conflictsByIdentity[entry.identity],
                let localSnapshot = localSnapshotsByIdentity[entry.identity],
                let remoteSnapshot = remoteSnapshotsByIdentity[entry.identity]
            else {
                return true
            }
            return hasAuthoritativeLocalWork(
                localSnapshot,
                remoteSnapshot: remoteSnapshot,
                cloudPreferredDomains: conflict.domains
            )
        }
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(retainedEntries)
    }

    private func ambiguousConflicts(
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        remoteChanges: [LibraryEntrySyncRemoteChange]
    ) -> AmbiguousConflictSet {
        var conflictsByIdentity: [LibraryEntrySyncIdentity: AmbiguousConflict] = [:]
        for remoteChange in remoteChanges {
            guard case .snapshot(let remoteSnapshot) = remoteChange,
                let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity]
            else {
                continue
            }

            var domains: Set<LibraryCloudSyncConflictDomain> = []
            if localSnapshot.libraryUpdatedAt == nil,
                remoteSnapshot.libraryUpdatedAt == nil,
                libraryValuesDiffer(localSnapshot, remoteSnapshot)
            {
                domains.insert(.library)
            }
            if localSnapshot.trackingUpdatedAt == nil,
                remoteSnapshot.trackingUpdatedAt == nil,
                trackingValuesDiffer(localSnapshot, remoteSnapshot)
            {
                domains.insert(.tracking)
            }

            if !domains.isEmpty {
                conflictsByIdentity[remoteSnapshot.identity] = .init(
                    identity: remoteSnapshot.identity,
                    domains: domains
                )
            }
        }
        return .init(conflictsByIdentity: conflictsByIdentity)
    }

    private func apply(
        _ domains: Set<LibraryCloudSyncConflictDomain>,
        from source: LibraryEntrySyncSnapshot,
        to target: inout LibraryEntrySyncSnapshot
    ) {
        if domains.contains(.library) {
            target.onDisplay = source.onDisplay
            target.dateSaved = source.dateSaved
            target.libraryUpdatedAt = source.libraryUpdatedAt
        }
        if domains.contains(.tracking) {
            target.watchStatus = source.watchStatus
            target.dateStarted = source.dateStarted
            target.dateFinished = source.dateFinished
            target.isDateTrackingEnabled = source.isDateTrackingEnabled
            target.score = source.score
            target.favorite = source.favorite
            target.notes = source.notes
            target.usingCustomPoster = source.usingCustomPoster
            target.customPosterURL = source.usingCustomPoster ? source.customPosterURL : nil
            target.trackingUpdatedAt = source.trackingUpdatedAt
        }
        if domains.contains(.episodeProgress) {
            target.episodeProgresses = source.episodeProgresses
        }
    }

    /// Applies remote changes to local entries, hydrating missing snapshots first.
    ///
    /// The method suppresses change recording while the imported changes are
    /// written so the local save pass does not enqueue its own changes.
    private func applyImportedChanges(
        _ batch: CloudLibrarySyncImportBatch,
        to store: LibraryStore,
        forcedDomainsByIdentity: [LibraryEntrySyncIdentity: Set<LibraryCloudSyncConflictDomain>] = [:]
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
                    try withAnimation {
                        if applicationTarget.isInitialMaterialization {
                            hydratedEntriesCount += 1
                            try applicationTarget.entry.applyInitialSyncSnapshot(snapshot)
                        } else {
                            try applicationTarget.entry.applySyncSnapshot(snapshot)
                            if let forcedDomains = forcedDomainsByIdentity[snapshot.identity] {
                                applicationTarget.entry.applyForcedSyncDomains(
                                    forcedDomains,
                                    from: snapshot
                                )
                            }
                        }
                    }
                case .tombstone(let tombstone):
                    guard let entry = store.repository.existingEntry(identity: tombstone.identity) else {
                        continue
                    }
                    appliedChangesCount += 1
                    try withAnimation {
                        try entry.applySyncTombstone(tombstone)
                    }
                }
            }
            try store.repository.save()
        }
        store.rebuildSyncChangeTracking()
        return (appliedChangesCount, hydratedEntriesCount)
    }

    /// Refreshes derived library view state after imported changes are persisted.
    private func refreshLibraryAfterImport(in store: LibraryStore) throws {
        try store.refreshLibrary()
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
    static func hydrateMissingEntry(
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
            uniqueKeysWithValues: batch.changes.map { ($0.identity, $0) }
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

extension LibrarySyncCoordinator.SyncResult {
    fileprivate func merged(with nextResult: Self) -> Self {
        switch (self, nextResult) {
        case (.retryableFailure, _), (_, .retryableFailure):
            return .retryableFailure
        case (.permanentFailure, _), (_, .permanentFailure):
            return .permanentFailure
        case (.conflictChoiceRequired, _), (_, .conflictChoiceRequired):
            return .conflictChoiceRequired
        case (.skipped(_), _):
            return nextResult
        case (_, .skipped(_)):
            return self
        case (.success, .success):
            return .success
        }
    }
}

fileprivate struct ApplicationTarget {
    let entry: AnimeEntry
    let isInitialMaterialization: Bool
}

fileprivate struct AmbiguousConflict {
    var identity: LibraryEntrySyncIdentity
    var domains: Set<LibraryCloudSyncConflictDomain>
}

fileprivate struct AmbiguousConflictSet {
    var conflictsByIdentity: [LibraryEntrySyncIdentity: AmbiguousConflict]

    var isEmpty: Bool {
        conflictsByIdentity.isEmpty
    }

    var summary: LibraryCloudSyncConflictSummary {
        LibraryCloudSyncConflictSummary(
            entryCount: conflictsByIdentity.count,
            libraryDomainCount: domainCount(.library),
            trackingDomainCount: domainCount(.tracking),
            episodeProgressDomainCount: domainCount(.episodeProgress)
        )
    }

    var domainsByIdentity: [LibraryEntrySyncIdentity: Set<LibraryCloudSyncConflictDomain>] {
        conflictsByIdentity.mapValues(\.domains)
    }

    private func domainCount(_ domain: LibraryCloudSyncConflictDomain) -> Int {
        conflictsByIdentity.values.filter { $0.domains.contains(domain) }.count
    }
}

extension Error {
    fileprivate var isPermanentLibrarySyncFailure: Bool {
        if self is DisabledCloudLibrarySyncDatabase.DisabledError {
            return true
        }
        guard let ckError = self as? CKError else { return false }
        switch ckError.code {
        case .notAuthenticated, .permissionFailure:
            return true
        default:
            return false
        }
    }

    fileprivate var libraryCloudKitAvailability: LibraryCloudKitAvailability {
        guard let ckError = self as? CKError else {
            return .couldNotDetermine
        }
        switch ckError.code {
        case .notAuthenticated:
            return .noAccount
        case .permissionFailure:
            return .restricted
        default:
            return .couldNotDetermine
        }
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

fileprivate func libraryValuesDiffer(
    _ lhs: LibraryEntrySyncSnapshot,
    _ rhs: LibraryEntrySyncSnapshot
) -> Bool {
    lhs.onDisplay != rhs.onDisplay
        || lhs.dateSaved != rhs.dateSaved
}

fileprivate func trackingValuesDiffer(
    _ lhs: LibraryEntrySyncSnapshot,
    _ rhs: LibraryEntrySyncSnapshot
) -> Bool {
    lhs.watchStatus != rhs.watchStatus
        || lhs.dateStarted != rhs.dateStarted
        || lhs.dateFinished != rhs.dateFinished
        || lhs.isDateTrackingEnabled != rhs.isDateTrackingEnabled
        || lhs.score != rhs.score
        || lhs.favorite != rhs.favorite
        || lhs.notes != rhs.notes
        || lhs.usingCustomPoster != rhs.usingCustomPoster
        || lhs.customPosterURL != rhs.customPosterURL
}

fileprivate func hasAuthoritativeLocalWork(
    _ localSnapshot: LibraryEntrySyncSnapshot,
    remoteSnapshot: LibraryEntrySyncSnapshot,
    cloudPreferredDomains: Set<LibraryCloudSyncConflictDomain>
) -> Bool {
    if !cloudPreferredDomains.contains(.library),
        isNewer(localSnapshot.libraryUpdatedAt, than: remoteSnapshot.libraryUpdatedAt)
    {
        return true
    }
    if !cloudPreferredDomains.contains(.tracking),
        isNewer(localSnapshot.trackingUpdatedAt, than: remoteSnapshot.trackingUpdatedAt)
    {
        return true
    }
    return hasNewerLocalEpisodeProgress(localSnapshot, remoteSnapshot: remoteSnapshot)
}

fileprivate func hasNewerLocalEpisodeProgress(
    _ localSnapshot: LibraryEntrySyncSnapshot,
    remoteSnapshot: LibraryEntrySyncSnapshot
) -> Bool {
    let remoteProgresses = Dictionary(
        uniqueKeysWithValues: remoteSnapshot.episodeProgresses.map { ($0.seasonNumber, $0) }
    )
    for localProgress in localSnapshot.episodeProgresses {
        guard let remoteProgress = remoteProgresses[localProgress.seasonNumber] else {
            return true
        }
        if localProgress.updatedAt > remoteProgress.updatedAt {
            return true
        }
        if localProgress.updatedAt == remoteProgress.updatedAt,
            localProgress.watchedThroughEpisode > remoteProgress.watchedThroughEpisode
        {
            return true
        }
    }
    return false
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

extension AnimeEntry {
    fileprivate func applyForcedSyncDomains(
        _ domains: Set<LibraryCloudSyncConflictDomain>,
        from snapshot: LibraryEntrySyncSnapshot
    ) {
        if domains.contains(.library) {
            onDisplay = snapshot.onDisplay
            dateSaved = snapshot.dateSaved
            libraryUpdatedAt = snapshot.libraryUpdatedAt
        }
        if domains.contains(.tracking) {
            watchStatus = snapshot.watchStatus
            dateStarted = snapshot.dateStarted
            dateFinished = snapshot.dateFinished
            isDateTrackingEnabled = snapshot.isDateTrackingEnabled
            score = snapshot.score
            favorite = snapshot.favorite
            notes = snapshot.notes
            let wasUsingCustomPoster = usingCustomPoster
            usingCustomPoster = snapshot.usingCustomPoster
            if snapshot.usingCustomPoster {
                posterURL = snapshot.customPosterURL
            } else if wasUsingCustomPoster {
                posterURL = nil
            }
            trackingUpdatedAt = snapshot.trackingUpdatedAt
        }
        if domains.contains(.episodeProgress) {
            for progress in episodeProgresses {
                modelContext?.delete(progress)
            }
            episodeProgresses.removeAll()
            for progress in snapshot.episodeProgresses {
                applyEpisodeProgressSnapshot(
                    seasonNumber: progress.seasonNumber,
                    watchedThroughEpisode: progress.watchedThroughEpisode,
                    updatedAt: progress.updatedAt
                )
            }
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

fileprivate enum FirstEnableBootstrapCancellation: Error {
    case cancelled
}
