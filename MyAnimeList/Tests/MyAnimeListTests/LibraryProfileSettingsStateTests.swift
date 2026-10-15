//
//  LibraryProfileSettingsStateTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/13.
//

import Foundation
import Testing

@testable import MyAnimeList

struct LibraryProfileSettingsStateTests {
    @Test @MainActor func successfulSyncStillSurfacesOutstandingIssues() {
        var status = LibraryCloudSyncStatus.defaultValue
        status.isEnabled = true
        status.bootstrapState = .completed
        status.lastResult = .success
        status.rejectedUploadCount = 2
        status.quarantinedRecordCount = 1
        #expect(status.settingsSyncIssues.map(\.count) == [2, 1])
        #expect(status.settingsIssueCount == 3)
        #expect(status.settingsHubStatus.systemImage == "exclamationmark.triangle.fill")
        status.isEnabled = false
        #expect(status.settingsSyncIssues.isEmpty)
        #expect(status.settingsIssueCount == 0)
        #expect(status.settingsHubStatus.systemImage == "icloud.slash")
    }

    @Test @MainActor func restorationFailuresAreCountedWithoutDuplicatingPendingReconstructions() {
        let snapshot = makeSnapshot(identity: .init(entryType: .series, tmdbID: 42), tmdbID: 42)
        var status = LibraryCloudSyncStatus.defaultValue
        status.isEnabled = true
        status.restoration = LibraryRestorationState(
            scope: makeSyncScope(), totalEntries: 1, restoredEntries: 0,
            failures: [
                .init(
                    snapshot: snapshot, metadataIdentity: snapshot.identity, reason: "Unavailable",
                    retryDates: [], lastAttempt: .now)
            ]
        )
        status.lastCompletedScope = makeSyncScope()
        status.pendingReconstructions = [
            .init(
                scope: makeSyncScope(),
                failures: [
                    .init(
                        snapshot: snapshot, metadataIdentity: snapshot.identity, reason: "Unavailable",
                        lastAttempt: .now)
                ])
        ]
        status.rejectedUploadCount = 1
        #expect(status.settingsSyncIssues.map(\.count) == [1])
        #expect(status.settingsIssueCount == 2)
        status.restoration = nil
        #expect(status.settingsSyncIssues.map(\.count) == [1, 1])
        #expect(status.settingsIssueCount == 2)
        #expect(status.settingsHubStatus.systemImage == "exclamationmark.triangle.fill")
    }

    @Test @MainActor func conflictWaitsForModalAndCanResolveBeforeModalCloses() {
        let controller = LibraryProfileCloudSyncController()
        controller.reconcileConflict(needsChoice: true, presentationBlocked: true)
        #expect(!controller.showConflictAlert)
        controller.actionInFlight = true
        controller.reconcileConflict(needsChoice: true, presentationBlocked: false)
        #expect(!controller.showConflictAlert)
        controller.actionInFlight = false
        controller.reconcileConflict(needsChoice: true, presentationBlocked: false)
        #expect(controller.showConflictAlert)
        controller.reconcileConflict(needsChoice: false, presentationBlocked: true)
        #expect(!controller.showConflictAlert)
        controller.reconcileConflict(needsChoice: false, presentationBlocked: false)
        #expect(!controller.showConflictAlert)
    }
}
