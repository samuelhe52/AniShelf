//
//  LibrarySyncCoordinatorTests+Status.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

extension LibrarySyncCoordinatorTests {
    @Test @MainActor func syncInProgressIncludesBootstrapBeforeItsFirstPhase() {
        var status = LibraryCloudSyncStatus.defaultValue
        status.isEnabled = true
        status.bootstrapState = .running

        #expect(status.isSyncInProgress)

        status.bootstrapState = .completed
        status.currentPhase = .syncing
        #expect(status.isSyncInProgress)

        status.currentPhase = nil
        status.lastResult = .success
        #expect(!status.isSyncInProgress)
    }

    @Test @MainActor func disablingLibraryCloudSyncClearsTransientStateAndPersists() {
        let store = makeStore(
            enabled: true,
            bootstrapState: .completed,
            hasTMDbAPIKey: true
        )
        store.updateLibraryCloudSyncStatus { status in
            status.currentPhase = .syncing
            status.pendingConflictSummary = .init(
                entryCount: 2,
                libraryDomainCount: 1,
                trackingDomainCount: 1,
                episodeProgressDomainCount: 0
            )
            status.retryState = .init(
                failureRetryAttempt: 2,
                nextRetryAllowedAt: referenceDate(year: 2026, month: 6, day: 2),
                automaticRetriesExhausted: true
            )
            status.lastResult = .retryableFailure
            status.lastFailureReason = "Network unavailable."
            status.degradedReason = "Automatic retries are exhausted."
        }

        store.disableLibraryCloudSync()

        #expect(!store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(store.libraryCloudSyncStatus.pendingConflictSummary == nil)
        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.retryState == .idle)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == nil)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)
        #expect(store.preferences.load().cloudSyncStatus == store.libraryCloudSyncStatus)
    }

    @Test @MainActor func recordingLibraryCloudSyncFailureClearsActivePhase() {
        let store = makeSyncReadyStore()
        let lastSuccessDate = referenceDate(year: 2026, month: 6, day: 1)
        let retryDate = referenceDate(year: 2026, month: 6, day: 2)
        let failureDate = referenceDate(year: 2026, month: 6, day: 3)
        store.updateLibraryCloudSyncStatus { status in
            status.lastResult = .retryableFailure
            status.lastFailureReason = "Network unavailable."
            status.degradedReason = "Automatic retries are exhausted."
            status.lastSuccessfulSyncDate = lastSuccessDate
        }

        store.recordLibraryCloudSyncPhase(
            trigger: .manualRetry,
            phase: .exporting,
            at: retryDate
        )

        #expect(store.libraryCloudSyncStatus.currentPhase == .exporting)
        #expect(store.libraryCloudSyncStatus.lastResult == nil)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == nil)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)

        store.recordLibraryCloudSyncFailure(
            trigger: .manualRetry,
            phase: .exporting,
            result: .retryableFailure,
            reason: "Network unavailable.",
            at: failureDate
        )

        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .retryableFailure)
        #expect(store.libraryCloudSyncStatus.lastAttemptDate == failureDate)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate == lastSuccessDate)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == "Network unavailable.")
        #expect(store.preferences.load().cloudSyncStatus == store.libraryCloudSyncStatus)
    }
}
