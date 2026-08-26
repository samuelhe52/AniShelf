//
//  LibrarySyncCoordinator+Pipeline.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import Foundation
import LibrarySync

extension LibrarySyncCoordinator {
    struct SyncPass {
        let trigger: Trigger
        let completedBootstrap: Bool
        let noNamespaceDegradedReason: String
        let permanentFailureDegradedReason: String
        let checkCancellation: () throws -> Void
        let markBootstrapFailed: () -> Void

        @MainActor func run<T>(
            _ phase: SyncPhase,
            state: SyncPipelineState,
            store: LibraryStore,
            checkCancellationAfter: Bool = true,
            _ operation: () async throws -> T
        ) async throws -> T {
            state.currentPhase = phase
            store.recordLibraryCloudSyncPhase(
                trigger: trigger,
                phase: phase,
                at: state.dateProvider()
            )
            let value = try await operation()
            if checkCancellationAfter {
                try checkCancellation()
            }
            return value
        }
    }

    final class SyncPipelineState {
        var currentPhase: SyncPhase?
        let dateProvider: () -> Date

        init(dateProvider: @escaping () -> Date) {
            self.dateProvider = dateProvider
        }
    }

    struct ImportHead {
        let namespace: CloudLibrarySyncChangeTokenStore.Namespace
        let preImportSnapshots: [LibraryEntryIdentity: LibraryEntrySyncSnapshot]
        let importBatch: CloudLibrarySyncImportBatch
    }

    func ordinarySyncPass(
        trigger: Trigger,
        cancellationGeneration: Int,
        store: LibraryStore
    ) -> SyncPass {
        .init(
            trigger: trigger,
            completedBootstrap: false,
            noNamespaceDegradedReason:
                "iCloud library sync is blocked until iCloud account access is available.",
            permanentFailureDegradedReason: "iCloud library sync is blocked by a permanent failure.",
            checkCancellation: { [weak self, weak store] in
                guard let self, let store else { throw CancellationError() }
                try self.checkOrdinarySyncCancellation(cancellationGeneration, store: store)
            },
            markBootstrapFailed: {}
        )
    }

    func bootstrapSyncPass(bootstrapID: UUID) -> SyncPass {
        .init(
            trigger: .firstEnableBootstrap,
            completedBootstrap: true,
            noNamespaceDegradedReason:
                "iCloud library sync enablement is blocked until iCloud account access is available.",
            permanentFailureDegradedReason:
                "iCloud library sync enablement is blocked by a permanent failure.",
            checkCancellation: { [weak self] in
                guard let self else { throw CancellationError() }
                try self.checkFirstEnableBootstrapCancellation(bootstrapID)
            },
            markBootstrapFailed: { [weak self] in
                self?.store?.updateLibraryCloudSyncStatus { status in
                    status.bootstrapState = .failed
                }
            }
        )
    }

    func runImportHead(
        pass: SyncPass,
        state: SyncPipelineState,
        store: LibraryStore
    ) async throws -> ImportHead? {
        try pass.checkCancellation()
        try await pass.run(.prepareZoneSubscription, state: state, store: store) {
            try await importer.prepareRemoteSync()
        }

        let resolvedNamespace = try await pass.run(
            .namespaceResolution,
            state: state,
            store: store
        ) {
            try await resolveNamespace(reportingTo: store)
        }
        guard let namespace = resolvedNamespace else {
            try pass.checkCancellation()
            librarySyncCoordinatorLogger.warning(
                "Skipped iCloud library sync for \(pass.trigger.rawValue, privacy: .public) because no iCloud account namespace was available."
            )
            store.recordLibraryCloudSyncFailure(
                trigger: pass.trigger,
                phase: state.currentPhase,
                result: .permanentFailure,
                reason: "No iCloud account namespace was available.",
                degradedReason: pass.noNamespaceDegradedReason,
                at: dateProvider()
            )
            pass.markBootstrapFailed()
            return nil
        }
        if !pass.completedBootstrap,
            store.libraryCloudSyncStatus.lastCompletedScope
                != LibraryCloudSyncScope(namespace: namespace)
        {
            throw LibraryCloudSyncScopeChangedDuringSync()
        }

        let preImportSnapshots = try localSnapshotsByIdentity(for: store)
        let importBatch = try await pass.run(.remoteFetch, state: state, store: store) {
            if pass.completedBootstrap {
                try await importer.fetchChangesFromBeginning(
                    namespace: namespace,
                    localSnapshotsByIdentity: preImportSnapshots
                )
            } else {
                try await importer.fetchChanges(
                    namespace: namespace,
                    localSnapshotsByIdentity: preImportSnapshots
                )
            }
        }
        return .init(
            namespace: namespace,
            preImportSnapshots: preImportSnapshots,
            importBatch: importBatch
        )
    }

    func runApplyExportTail(
        pass: SyncPass,
        state: SyncPipelineState,
        store: LibraryStore,
        importBatch: CloudLibrarySyncImportBatch,
        forcedDomainsByIdentity: [LibraryEntryIdentity: Set<LibraryCloudSyncConflictDomain>] = [:]
    ) async throws -> SyncResult {
        _ = try await pass.run(.hydrationApply, state: state, store: store) {
            try await applyImportedChanges(
                importBatch,
                to: store,
                forcedDomainsByIdentity: forcedDomainsByIdentity
            )
        }
        applyImportedSettingsIfNeeded(importBatch.settingsSnapshot, to: store)
        try pass.checkCancellation()

        try await pass.run(.tokenCommit, state: state, store: store) {
            importer.commit(importBatch)
        }
        try await pass.run(.libraryRefresh, state: state, store: store) {
            try refreshLibraryAfterImport(in: store)
        }
        _ = try await pass.run(.dirtyQueueReconciliation, state: state, store: store) {
            try reconcileDirtyQueue(with: importBatch, in: store)
        }

        let postImportSnapshots = try localSnapshotsByIdentity(for: store)
        let dirtyEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        let localSettingsState = localSettingsSnapshotState(for: store)
        let exportSettingsSnapshot = settingsSnapshotForExport(
            localState: localSettingsState,
            remoteSnapshot: importBatch.settingsSnapshot,
            store: store
        )
        let exportResult = try await pass.run(
            .export,
            state: state,
            store: store,
            checkCancellationAfter: false
        ) {
            try await export(
                entries: dirtyEntries,
                localSnapshotsByIdentity: postImportSnapshots,
                settingsSnapshot: exportSettingsSnapshot,
                observedDirtyEntries: dirtyEntries,
                store: store
            )
        }
        logSettingsExportResult(exportSettingsSnapshot, exportResult: exportResult)

        // Once CloudKit has confirmed an export, dequeue its local work even
        // if cancellation arrived while the export request was in flight.
        try removeExportedDirtyEntries(
            exportResult.exportedIdentities,
            from: dirtyEntries,
            in: store
        )
        // The dequeue above is safe to keep, but a cancelled pass must not
        // stamp success over the status the disable path already reset.
        try pass.checkCancellation()
        let reconciledCloudSyncedSettingsUpdatedAt =
            reconciledCloudSyncedSettingsUpdatedAt(
                store: store,
                exportedSnapshot: exportSettingsSnapshot,
                settingsExported: exportResult.settingsExported
            )
        store.recordLibraryCloudSyncSuccess(
            trigger: pass.trigger,
            completedBootstrap: pass.completedBootstrap,
            completedScope: pass.completedBootstrap
                ? LibraryCloudSyncScope(
                    namespace: importBatch.namespace,
                    zoneID: importBatch.zoneID
                )
                : nil,
            reconciledCloudSyncedSettingsUpdatedAt: reconciledCloudSyncedSettingsUpdatedAt,
            at: dateProvider()
        )
        return .success
    }

    func recordPipelineFailure(
        _ error: Error,
        pass: SyncPass,
        state: SyncPipelineState,
        store: LibraryStore
    ) -> SyncResult {
        let result: SyncResult = error.isPermanentLibrarySyncFailure ? .permanentFailure : .retryableFailure
        store.recordLibraryCloudSyncFailure(
            trigger: pass.trigger,
            phase: state.currentPhase,
            result: result.resultClass,
            reason: error.localizedDescription,
            degradedReason: result == .permanentFailure
                ? pass.permanentFailureDegradedReason
                : nil,
            at: dateProvider()
        )
        pass.markBootstrapFailed()
        librarySyncCoordinatorLogger.error(
            "iCloud library sync triggered by \(pass.trigger.rawValue, privacy: .public) failed during \(state.currentPhase?.rawValue ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .private)"
        )
        return result
    }
}

fileprivate struct LibraryCloudSyncScopeChangedDuringSync: LocalizedError {
    var errorDescription: String? {
        String(
            localized:
                "Your iCloud account changed while iCloud Sync was starting. Try again to rebuild sync for the new account."
        )
    }
}

@MainActor
final class SyncGate {
    private var isSyncing = false
    private var syncRequestedWhileRunning = false
    private var waiters: [CheckedContinuation<LibrarySyncCoordinator.SyncResult, Never>] = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRunningPass() async -> LibrarySyncCoordinator.SyncResult? {
        guard isSyncing else { return nil }
        syncRequestedWhileRunning = true
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func begin() {
        precondition(!isSyncing)
        isSyncing = true
    }

    func waitUntilIdle() async {
        guard isSyncing else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    func consumeRerunRequest() -> Bool {
        defer { syncRequestedWhileRunning = false }
        return syncRequestedWhileRunning
    }

    func finish(_ result: LibrarySyncCoordinator.SyncResult, parkingWaiters: Bool = false) {
        isSyncing = false
        let pendingIdleWaiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in pendingIdleWaiters {
            waiter.resume()
        }
        guard !parkingWaiters else { return }
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(returning: result)
        }
    }

    func cancelAll() {
        syncRequestedWhileRunning = false
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(returning: .skipped(.disabled))
        }
    }
}
