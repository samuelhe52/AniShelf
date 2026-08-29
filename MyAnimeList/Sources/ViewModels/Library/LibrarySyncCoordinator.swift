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

let librarySyncCoordinatorLogger = Logger(
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
        case localChange
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

    weak var store: LibraryStore?
    let importer: CloudLibrarySyncImporter
    let exporter: CloudLibrarySyncExporter
    private let changeTokenStore: CloudLibrarySyncChangeTokenStore
    private let namespaceProvider: @MainActor () async throws -> CloudLibrarySyncChangeTokenStore.Namespace?
    let hydrateMissingEntry: @MainActor (LibraryEntrySyncSnapshot, LibraryStore) async throws -> AnimeEntry
    let dateProvider: @MainActor @Sendable () -> Date

    private let syncGate = SyncGate()
    private var activeSyncRequestCount = 0
    private var ordinarySyncCancellationGeneration = 0
    private var activeFirstEnableBootstrapIDs = Set<UUID>()
    private var canceledFirstEnableBootstrapIDs = Set<UUID>()

    var hasActiveSyncRequest: Bool {
        activeSyncRequestCount > 0
    }

    typealias SyncPhase = LibraryCloudSyncPhase

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
    ///     refers to an entry the local store does not currently have. The hook
    ///     must return a detached entry; the coordinator inserts it only after
    ///     hydration planning passes its cancellation boundary.
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
        self.changeTokenStore = changeTokenStore
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

    func removeAllChangeTokens() {
        changeTokenStore.removeAllTokens()
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
        activeSyncRequestCount += 1
        defer { activeSyncRequestCount -= 1 }

        guard !Task.isCancelled else { return .skipped(.disabled) }
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because the library store was unavailable."
            )
            return .permanentFailure
        }
        if let queuedResult = await syncGate.waitForRunningPass() {
            librarySyncCoordinatorLogger.info(
                "Queued iCloud library sync for \(trigger.rawValue, privacy: .public) while another sync was already running."
            )
            return queuedResult
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

        var scopeRequiringBootstrap: LibraryCloudSyncScope?
        do {
            scopeRequiringBootstrap = try await currentScopeRequiringBootstrap(store: store)
        } catch {
            // Continue through the normal pipeline so the existing phase and
            // failure reporting path records the namespace-resolution error.
        }

        guard !Task.isCancelled else { return .skipped(.disabled) }
        if let queuedResult = await syncGate.waitForRunningPass() {
            librarySyncCoordinatorLogger.info(
                "Queued iCloud library sync for \(trigger.rawValue, privacy: .public) because another sync started during scope resolution."
            )
            return queuedResult
        }
        if let blockedReason = store.libraryCloudSyncPolicyBlockReason() {
            store.recordLibraryCloudSyncSkipped(
                trigger: trigger,
                reason: blockedReason,
                at: dateProvider()
            )
            librarySyncCoordinatorLogger.info(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because policy changed during scope resolution: \(blockedReason.rawValue, privacy: .public)."
            )
            return .skipped(blockedReason)
        }
        if let scopeRequiringBootstrap,
            store.libraryCloudSyncStatus.lastCompletedScope != scopeRequiringBootstrap
        {
            librarySyncCoordinatorLogger.info(
                "Starting iCloud library bootstrap because the active sync scope differs from the last completed scope."
            )
            return await store.bootstrapLibraryCloudSyncEnablement()
        }

        syncGate.begin()
        librarySyncCoordinatorLogger.info(
            "Starting iCloud library sync triggered by \(trigger.rawValue, privacy: .public)."
        )
        var result = SyncResult.success
        let cancellationGeneration = ordinarySyncCancellationGeneration

        repeat {
            result = result.merged(
                with: await runSync(
                    trigger: trigger,
                    cancellationGeneration: cancellationGeneration
                ))
        } while syncGate.consumeRerunRequest()

        syncGate.finish(result)
        return result
    }

    /// Executes the ordered sync phases once.
    private func runSync(
        trigger: Trigger,
        cancellationGeneration: Int
    ) async -> SyncResult {
        guard let store else {
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library sync for \(trigger.rawValue, privacy: .public) because the library store was unavailable."
            )
            return .permanentFailure
        }
        let pass = ordinarySyncPass(
            trigger: trigger,
            cancellationGeneration: cancellationGeneration,
            store: store
        )
        let state = SyncPipelineState(dateProvider: dateProvider)
        do {
            guard let head = try await runImportHead(pass: pass, state: state, store: store) else {
                return .permanentFailure
            }
            let result = try await runApplyExportTail(
                pass: pass,
                state: state,
                store: store,
                importBatch: head.importBatch
            )
            librarySyncCoordinatorLogger.info(
                "Finished iCloud library sync triggered by \(trigger.rawValue, privacy: .public)."
            )
            return result
        } catch is CancellationError {
            store.recordLibraryCloudSyncCancellation()
            librarySyncCoordinatorLogger.info(
                "Cancelled iCloud library sync triggered by \(trigger.rawValue, privacy: .public)."
            )
            return .skipped(.disabled)
        } catch {
            return recordPipelineFailure(error, pass: pass, state: state, store: store)
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
        activeSyncRequestCount += 1
        defer { activeSyncRequestCount -= 1 }

        let bootstrapID = UUID()
        if let queuedResult = await syncGate.waitForRunningPass() {
            librarySyncCoordinatorLogger.info(
                "Queued iCloud library first-enable bootstrap while another sync was already running."
            )
            return queuedResult
        }

        syncGate.begin()
        activeFirstEnableBootstrapIDs.insert(bootstrapID)
        var result = await runFirstEnableBootstrap(
            preference: preference,
            bootstrapID: bootstrapID
        )
        activeFirstEnableBootstrapIDs.remove(bootstrapID)
        canceledFirstEnableBootstrapIDs.remove(bootstrapID)
        if result == .success {
            let cancellationGeneration = ordinarySyncCancellationGeneration
            while syncGate.consumeRerunRequest() {
                result = result.merged(
                    with: await runSync(
                        trigger: .firstEnableBootstrap,
                        cancellationGeneration: cancellationGeneration
                    ))
            }
        }
        // A queued ordinary sync must remain parked until the caller resolves
        // the bootstrap conflict and starts the next bootstrap pass.
        syncGate.finish(result, parkingWaiters: result == .conflictChoiceRequired)
        return result
    }

    func cancelAllSync() {
        ordinarySyncCancellationGeneration &+= 1
        canceledFirstEnableBootstrapIDs.formUnion(activeFirstEnableBootstrapIDs)
        syncGate.cancelAll()
    }

    func waitUntilAllSyncFinishes() async {
        await syncGate.waitUntilIdle()
    }

    func checkOrdinarySyncCancellation(
        _ cancellationGeneration: Int,
        store: LibraryStore
    ) throws {
        guard cancellationGeneration == ordinarySyncCancellationGeneration else {
            throw CancellationError()
        }
        if store.requiresDuplicateRepair {
            throw CancellationError()
        }
        if store.libraryCloudSyncPolicyBlockReason() == .disabled {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    func resolveNamespace(
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

    private func currentScopeRequiringBootstrap(store: LibraryStore) async throws
        -> LibraryCloudSyncScope?
    {
        guard let namespace = try await resolveNamespace(reportingTo: store) else {
            return nil
        }
        let currentScope = LibraryCloudSyncScope(namespace: namespace)
        if store.libraryCloudSyncStatus.lastCompletedScope == currentScope {
            return nil
        }

        if store.libraryCloudSyncStatus.lastCompletedScope == nil,
            changeTokenStore.token(
                for: CloudLibrarySyncClient.recordZoneID,
                namespace: namespace
            ) != nil
        {
            store.updateLibraryCloudSyncStatus { status in
                status.lastCompletedScope = currentScope
            }
            librarySyncCoordinatorLogger.info(
                "Adopted the current iCloud sync scope from compatible legacy completed state."
            )
            return nil
        }

        return currentScope
    }

    /// Throws the bootstrap-specific cancellation sentinel.
    ///
    /// The dedicated type is what lets `runFirstEnableBootstrap` tell a
    /// deliberate cancel apart from an ambient `CancellationError` raised
    /// somewhere inside the pass. Only the former may return without recording
    /// an outcome, because only then has the caller already reset the
    /// bootstrap state. An ambient cancellation must fall through to
    /// `recordPipelineFailure` so the bootstrap lands on `.failed` with a
    /// reason instead of stranding the persisted state at `.running`.
    func checkFirstEnableBootstrapCancellation(_ bootstrapID: UUID) throws {
        if canceledFirstEnableBootstrapIDs.contains(bootstrapID) {
            throw FirstEnableBootstrapCancellation.cancelled
        }
    }

    func applyImportedSettingsIfNeeded(
        _ remoteSnapshot: LibrarySettingsSyncSnapshot?,
        to store: LibraryStore
    ) {
        guard let remoteSnapshot else { return }
        let localUpdatedAt = store.preferences.cloudSyncedDefaultsUpdatedAt() ?? .distantPast
        guard remoteSnapshot.updatedAt > localUpdatedAt else {
            librarySyncCoordinatorLogger.debug(
                "Skipped iCloud settings snapshot updated at \(remoteSnapshot.updatedAt, privacy: .public) because the local settings clock is not older."
            )
            return
        }
        store.applyRemoteCloudSyncedPreferences(remoteSnapshot)
    }

    func localSettingsSnapshotState(for store: LibraryStore) -> LocalSettingsSnapshotState {
        let updatedAt = store.preferences.cloudSyncedDefaultsUpdatedAt()
        return .init(
            updatedAt: updatedAt,
            snapshot: store.preferences.loadCloudSyncedSettingsSnapshot(
                fallbackUpdatedAt: updatedAt ?? .distantPast
            )
        )
    }

    func settingsSnapshotForExport(
        localState: LocalSettingsSnapshotState,
        remoteSnapshot: LibrarySettingsSyncSnapshot?,
        store: LibraryStore
    ) -> LibrarySettingsSyncSnapshot? {
        guard let localUpdatedAt = localState.updatedAt else {
            guard remoteSnapshot == nil, !localState.snapshot.payload.isEmpty else { return nil }
            let updatedAt = dateProvider()
            store.preferences.saveCloudSyncedDefaultsUpdatedAt(updatedAt)
            let snapshot = store.preferences.loadCloudSyncedSettingsSnapshot(
                fallbackUpdatedAt: updatedAt
            )
            librarySyncCoordinatorLogger.info(
                "Initialized iCloud settings clock at \(updatedAt, privacy: .public) for first settings export with \(snapshot.payload.count, privacy: .public) keys."
            )
            return snapshot
        }
        guard let remoteSnapshot else { return localState.snapshot }
        guard localUpdatedAt > remoteSnapshot.updatedAt else { return nil }
        return localState.snapshot
    }

    func logSettingsExportResult(
        _ snapshot: LibrarySettingsSyncSnapshot?,
        exportResult: CloudLibrarySyncExportResult
    ) {
        guard let snapshot else { return }
        if exportResult.settingsExported {
            librarySyncCoordinatorLogger.info(
                "Exported iCloud settings snapshot updated at \(snapshot.updatedAt, privacy: .public) with \(snapshot.payload.count, privacy: .public) keys."
            )
        } else {
            librarySyncCoordinatorLogger.warning(
                "CloudKit did not accept the iCloud settings snapshot updated at \(snapshot.updatedAt, privacy: .public); settings remain pending."
            )
        }
    }

    func reconciledCloudSyncedSettingsUpdatedAt(
        store: LibraryStore,
        exportedSnapshot: LibrarySettingsSyncSnapshot?,
        settingsExported: Bool
    ) -> Date? {
        if let exportedSnapshot, settingsExported {
            return exportedSnapshot.updatedAt
        }
        if exportedSnapshot != nil {
            return store.libraryCloudSyncStatus.lastReconciledCloudSyncedSettingsUpdatedAt
        }
        guard let updatedAt = store.preferences.cloudSyncedDefaultsUpdatedAt() else { return nil }
        let payload = store.preferences.loadCloudSyncedSettingsSnapshot(
            fallbackUpdatedAt: updatedAt
        ).payload
        guard !payload.isEmpty else { return nil }
        return updatedAt
    }

    private func runFirstEnableBootstrap(
        preference: LibraryCloudSyncConflictPreference?,
        bootstrapID: UUID
    ) async -> SyncResult {
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
            status.currentPhase = nil
            status.lastResult = nil
            status.lastFailureReason = nil
        }

        let pass = bootstrapSyncPass(bootstrapID: bootstrapID)
        let state = SyncPipelineState(dateProvider: dateProvider)
        do {
            guard let head = try await runImportHead(pass: pass, state: state, store: store) else {
                return .permanentFailure
            }
            let preImportSnapshots = head.preImportSnapshots
            let fetchedBatch = head.importBatch

            let ambiguousConflicts = try await pass.run(
                .conflictDetection,
                state: state,
                store: store
            ) {
                self.ambiguousConflicts(
                    localSnapshotsByIdentity: preImportSnapshots,
                    remoteChanges: fetchedBatch.remoteChanges
                )
            }
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

            try pass.checkCancellation()
            if preference == .preferLocal, !ambiguousConflicts.isEmpty {
                try stampLocalClocks(
                    for: ambiguousConflicts,
                    at: dateProvider(),
                    in: store
                )
            }
            try pass.checkCancellation()

            let decisionSnapshots = try localSnapshotsByIdentity(for: store)
            try await pass.run(.dirtyQueueSeeding, state: state, store: store) {
                try seedDirtyQueue(
                    with: decisionSnapshots,
                    at: dateProvider(),
                    in: store
                )
            }

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
            try pass.checkCancellation()
            let result = try await runApplyExportTail(
                pass: pass,
                state: state,
                store: store,
                importBatch: importBatch,
                forcedDomainsByIdentity: preference == .preferCloud
                    ? ambiguousConflicts.domainsByIdentity
                    : [:]
            )
            librarySyncCoordinatorLogger.info(
                "Finished iCloud library first-enable bootstrap."
            )
            return result
        } catch is FirstEnableBootstrapCancellation {
            store.recordLibraryCloudSyncCancellation()
            librarySyncCoordinatorLogger.info(
                "Cancelled iCloud library first-enable bootstrap."
            )
            return .skipped(.disabled)
        } catch is CancellationError {
            store.recordLibraryCloudSyncCancellation()
            librarySyncCoordinatorLogger.info(
                "Cancelled iCloud library first-enable bootstrap."
            )
            return .skipped(.disabled)
        } catch {
            return recordPipelineFailure(error, pass: pass, state: state, store: store)
        }
    }

}

struct LocalSettingsSnapshotState {
    var updatedAt: Date?
    var snapshot: LibrarySettingsSyncSnapshot
}

extension Error {
    var isPermanentLibrarySyncFailure: Bool {
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

/// Marks a first-enable bootstrap that the caller deliberately cancelled.
///
/// Kept distinct from `CancellationError` so an ambient cancellation surfacing
/// from inside the shared pipeline is still recorded as a failure.
fileprivate enum FirstEnableBootstrapCancellation: Error {
    case cancelled
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
