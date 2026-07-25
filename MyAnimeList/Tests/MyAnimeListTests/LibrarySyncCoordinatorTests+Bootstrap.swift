//
//  LibrarySyncCoordinatorTests+Bootstrap.swift
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
    @Test @MainActor func firstEnableBootstrapWithoutRemoteOverlapSeedsAndExportsLocalLibrary() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .notStarted,
            hasTMDbAPIKey: true
        )
        let entry = AnimeEntry(
            name: "Local Only",
            type: .movie,
            tmdbID: 801,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.preferences.saveSortReversed(false)
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let exportDate = referenceDate(year: 2026, month: 6, day: 1)
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() },
            dateProvider: { exportDate }
        )

        let succeeded = await store.enableLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate != nil)
        #expect(store.preferences.load().cloudSyncStatus.lastSuccessfulSyncDate != nil)
        #expect(database.savedRecords.count == 2)
        let savedEntryRecord = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: entry.syncIdentity) }
        )
        let savedSnapshot = try savedSnapshot(from: savedEntryRecord, client: client)
        #expect(savedSnapshot.identity == entry.syncIdentity)
        let savedSettingsRecord = try #require(
            database.savedRecords.first { $0.recordID == client.librarySettingsRecordID }
        )
        let savedSettings = try client.settingsSnapshot(from: savedSettingsRecord)
        #expect(savedSettings.updatedAt == exportDate)
        #expect(savedSettings.payload[.librarySortReversed] == .bool(false))
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == exportDate)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func firstEnableBootstrapClockedOverlapUsesNormalResolutionWithoutPrompting()
        async throws
    {
        let store = makeStore(
            enabled: false,
            bootstrapState: .notStarted,
            hasTMDbAPIKey: true
        )
        let entry = AnimeEntry(
            name: "Clocked Local",
            type: .series,
            tmdbID: 802,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        entry.notes = "Local notes"
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 10)
        entry.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 10)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteSnapshot = makeSnapshot(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote notes",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 2)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(client: client, snapshots: [remoteSnapshot])
        ])
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let succeeded = await store.enableLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.pendingConflictSummary == nil)
        let savedSnapshot = try savedSnapshot(from: try #require(database.savedRecords.first), client: client)
        #expect(savedSnapshot.notes == "Local notes")
        #expect(savedSnapshot.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 10))
    }

    @Test @MainActor func firstEnableBootstrapClocklessDifferingOverlapPausesForConflictChoice()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture()

        let succeeded = await fixture.store.enableLibraryCloudSync()

        #expect(!succeeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .needsConflictChoice)
        #expect(fixture.store.libraryCloudSyncStatus.pendingConflictSummary?.entryCount == 1)
        #expect(fixture.store.libraryCloudSyncStatus.pendingConflictSummary?.trackingDomainCount == 1)
        #expect(fixture.database.savedRecords.isEmpty)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Local notes")
    }

    @Test @MainActor func resolvingFirstEnableConflictPreferCloudAppliesRemoteAmbiguousDomain()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture(repeatedRemoteFetches: 2)

        _ = await fixture.store.enableLibraryCloudSync()
        let succeeded = await fixture.store.resolveLibraryCloudSyncConflicts(preference: .preferCloud)

        #expect(succeeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .completed)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Remote notes")
        #expect(local.trackingUpdatedAt == nil)
        #expect(fixture.database.savedRecords.isEmpty)
        #expect(fixture.store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func resolvingFirstEnableConflictStillWorksAfterSkippedOrdinarySync()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture(repeatedRemoteFetches: 2)

        _ = await fixture.store.enableLibraryCloudSync()
        let skippedResult = await fixture.store.performLibrarySyncResult(trigger: .foreground)
        let succeeded = await fixture.store.resolveLibraryCloudSyncConflicts(preference: .preferCloud)

        #expect(skippedResult == .skipped(.bootstrapIncomplete))
        #expect(succeeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .completed)
    }

    @Test @MainActor func queuedOrdinarySyncDuringConflictBootstrapWaitsForConflictResolution()
        async throws
    {
        let fixture = try makeClocklessTrackingConflictFixture(repeatedRemoteFetches: 3)
        fixture.database.suspendedFetchCount = 1

        let bootstrapTask = Task { await fixture.store.enableLibraryCloudSync() }
        while !fixture.database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let queuedSyncTask = Task {
            await fixture.store.performLibrarySyncResult(trigger: .foreground)
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .running)

        fixture.database.resumeSuspendedFetch()
        let bootstrapSucceeded = await bootstrapTask.value
        #expect(!bootstrapSucceeded)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .needsConflictChoice)

        let resolutionSucceeded = await fixture.store.resolveLibraryCloudSyncConflicts(
            preference: .preferCloud
        )
        let queuedSyncResult = await queuedSyncTask.value

        #expect(resolutionSucceeded)
        #expect(queuedSyncResult == .success)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(fixture.database.ensureZoneCallCount == 3)
    }

    @Test @MainActor func resolvingFirstEnableConflictPreferLocalStampsAndExportsAmbiguousDomain()
        async throws
    {
        let decisionDate = referenceDate(year: 2026, month: 6, day: 2)
        let fixture = try makeClocklessTrackingConflictFixture(
            repeatedRemoteFetches: 2,
            dateProvider: { decisionDate }
        )

        _ = await fixture.store.enableLibraryCloudSync()
        let succeeded = await fixture.store.resolveLibraryCloudSyncConflicts(preference: .preferLocal)

        #expect(succeeded)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Local notes")
        #expect(local.trackingUpdatedAt == decisionDate)
        #expect(local.libraryUpdatedAt == nil)
        let savedSnapshot = try savedSnapshot(
            from: try #require(fixture.database.savedRecords.first),
            client: fixture.client
        )
        #expect(savedSnapshot.notes == "Local notes")
        #expect(savedSnapshot.trackingUpdatedAt == decisionDate)
    }

    @Test @MainActor func cancelingFirstEnableConflictLeavesSyncDisabledAndAvoidsMutation() async throws {
        let fixture = try makeClocklessTrackingConflictFixture()

        _ = await fixture.store.enableLibraryCloudSync()
        fixture.store.cancelLibraryCloudSyncEnablement()

        #expect(!fixture.store.libraryCloudSyncStatus.isEnabled)
        #expect(fixture.store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        let local = try #require(fixture.store.repository.existingEntry(identity: fixture.identity))
        #expect(local.notes == "Local notes")
        #expect(fixture.database.savedRecords.isEmpty)
    }

    @Test @MainActor func cancelingInFlightFirstEnableBootstrapStopsBeforeExport() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .notStarted,
            hasTMDbAPIKey: true
        )
        let entry = AnimeEntry(
            name: "Cancelable Local",
            type: .movie,
            tmdbID: 804,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let bootstrapTask = Task { await store.enableLibraryCloudSync() }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        store.cancelLibraryCloudSyncEnablement()
        database.resumeSuspendedFetch()
        let succeeded = await bootstrapTask.value

        #expect(!succeeded)
        #expect(!store.libraryCloudSyncStatus.isEnabled)
        // A deliberate cancel must return without recording an outcome, leaving
        // the reset the cancel itself performed intact. If the bootstrap ever
        // stops distinguishing its own cancellation sentinel from an ambient
        // `CancellationError`, this lands on `.failed` with a reason instead.
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
        #expect(store.libraryCloudSyncStatus.lastFailureReason == nil)
        #expect(database.savedRecords.isEmpty)
    }
}
