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
                phase: phase.progressPhase,
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
        if !pass.completedBootstrap,
            store.libraryCloudSyncStatus.currentPendingReconstructionFailures.contains(where: { $0.discardDate != nil })
        {
            // The scope check above confirms the active account supplied these failures.
            try await pass.run(.export, state: state, store: store) {
                try await exportPendingReconstructionDiscards(
                    in: LibraryCloudSyncScope(namespace: namespace),
                    store: store,
                    checkCancellation: pass.checkCancellation
                )
            }
        }

        if pass.completedBootstrap {
            let scope = LibraryCloudSyncScope(namespace: namespace)
            if store.libraryCloudSyncStatus.restoration?.scope != scope {
                store.updateLibraryCloudSyncStatus { $0.restoration = .init(scope: scope) }
            }
            try await pass.run(.export, state: state, store: store) {
                try await exportRestorationDiscards(in: store, checkCancellation: pass.checkCancellation)
            }
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
        store.updateLibraryCloudSyncStatus {
            $0.quarantinedRecordCount = importBatch.quarantinedRecordIDs.count
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
        forcedDomainsByIdentity: [LibraryEntryIdentity: Set<LibraryCloudSyncConflictDomain>] = [:],
        isUserRetry: Bool = false
    ) async throws -> SyncResult {
        _ = try await pass.run(.hydrationApply, state: state, store: store) {
            try await applyImportedChanges(
                importBatch,
                to: store,
                forcedDomainsByIdentity: forcedDomainsByIdentity,
                isBootstrap: pass.completedBootstrap,
                isUserRetry: isUserRetry,
                replaysPermanentFailures: pass.trigger == .manualRetry,
                checkCancellation: pass.checkCancellation
            )
        }
        applyImportedSettingsIfNeeded(importBatch.settingsSnapshot, to: store)
        try pass.checkCancellation()

        try await pass.run(.tokenCommit, state: state, store: store) {
            try importer.commit(importBatch)
        }
        try await pass.run(.libraryRefresh, state: state, store: store) {
            try refreshLibraryAfterImport(in: store)
        }
        var postImportSnapshots = try localSnapshotsByIdentity(for: store)
        _ = try await pass.run(.dirtyQueueReconciliation, state: state, store: store) {
            try reconcileDirtyQueue(
                with: importBatch,
                localSnapshotsByIdentity: &postImportSnapshots,
                in: store
            )
        }

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
                blockedRecordIDs: importBatch.quarantinedRecordIDs,
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
        // Rejected uploads and failed reconstructions affect only their own
        // entries. They stay pending for later passes and the scheduler's item
        // retries, so they do not turn this pass into a failure.
        store.updateLibraryCloudSyncStatus { status in
            status.rejectedUploadCount = exportResult.rejectedChangeCount
        }
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
        let availability = error.libraryCloudKitAvailability
        if availability == .noAccount || availability == .restricted {
            store.updateLibraryCloudKitAvailability(availability)
        }
        store.recordLibraryCloudSyncFailure(
            trigger: pass.trigger,
            phase: state.currentPhase,
            result: result.resultClass,
            reason: error.librarySyncFailureReason,
            degradedReason: result == .permanentFailure
                ? (error.librarySyncDegradedReason ?? pass.permanentFailureDegradedReason)
                : nil,
            retryAfterSeconds: error.librarySyncRetryAfterSeconds,
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
    enum PassKind { case ordinary, bootstrap }

    private struct Waiter {
        let continuation: CheckedContinuation<LibrarySyncCoordinator.SyncOutcome, Never>
        let canHandleResult: Bool
    }

    private var isSyncing = false
    private var passKind: PassKind = .ordinary
    private var passOwnerHandlesResult = true
    private var syncRequestedWhileRunning = false
    private var waiters: [Waiter] = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForRunningPass(canHandleResult: Bool = true) async -> LibrarySyncCoordinator.SyncOutcome? {
        guard isSyncing else { return nil }
        syncRequestedWhileRunning = true
        return await withCheckedContinuation { continuation in
            waiters.append(.init(continuation: continuation, canHandleResult: canHandleResult))
        }
    }

    func begin(kind: PassKind, ownerHandlesResult: Bool) {
        precondition(!isSyncing)
        isSyncing = true
        passKind = kind
        passOwnerHandlesResult = ownerHandlesResult
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
        var bootstrapRetryOwnerAssigned = passOwnerHandlesResult
        for waiter in pendingWaiters {
            let shouldHandleResult = passKind == .bootstrap
                && waiter.canHandleResult && !bootstrapRetryOwnerAssigned
            if shouldHandleResult { bootstrapRetryOwnerAssigned = true }
            waiter.continuation.resume(returning: .init(
                result, wasCoalesced: true, shouldHandleResult: shouldHandleResult
            ))
        }
    }

    func cancelAll() {
        syncRequestedWhileRunning = false
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.continuation.resume(returning: .init(
                .skipped(.disabled), wasCoalesced: true, shouldHandleResult: false
            ))
        }
    }
}
