//
//  LibrarySyncCoordinatorTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

@Suite(.serialized)
struct LibrarySyncCoordinatorTests {
    @Test @MainActor func dirtyQueueSchedulerDebouncesLocalChanges() async throws {
        var syncCount = 0
        var hasPendingDirtyWork = true
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.05,
            failureRetryIntervals: [0.1],
            hasPendingDirtyWork: {
                hasPendingDirtyWork
            },
            sync: { trigger in
                #expect(trigger == .localDirtyQueueChange)
                syncCount += 1
                hasPendingDirtyWork = false
                return .success
            }
        )

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 20_000_000)
        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 0)

        try await Task.sleep(nanoseconds: 60_000_000)

        #expect(syncCount == 1)
    }

    @Test @MainActor func dirtyQueueSchedulerBacksOffAfterFailure() async throws {
        var syncCount = 0
        var hasPendingDirtyWork = true
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.08],
            hasPendingDirtyWork: {
                hasPendingDirtyWork
            },
            sync: { _ in
                syncCount += 1
                if syncCount == 1 {
                    return .retryableFailure
                }
                hasPendingDirtyWork = false
                return .success
            }
        )

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 1)

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(syncCount == 1)

        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(syncCount == 2)
    }

    @Test @MainActor func dirtyQueueSchedulerStopsAfterFinalIntervalRetryLimit() async throws {
        var syncCount = 0
        var retryStates: [LibraryCloudSyncRetryState] = []
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.001,
            failureRetryIntervals: [0.01, 0.02],
            maximumRetryAttemptsAtFinalInterval: 3,
            hasPendingDirtyWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .retryableFailure
            },
            retryStateDidChange: { retryStates.append($0) },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 110_000_000)

        #expect(syncCount == 5)
        #expect(retryStates.last?.automaticRetriesExhausted == true)
        #expect(degradedReason != nil)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(syncCount == 5)
    }

    @Test @MainActor func dirtyQueueSchedulerDoesNotRetryPermanentFailure() async throws {
        var syncCount = 0
        var degradedReason: String?
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.02],
            hasPendingDirtyWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .permanentFailure
            },
            degradedStateDidChange: { degradedReason = $0 }
        )

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(syncCount == 1)
        #expect(degradedReason != nil)
    }

    @Test @MainActor func ordinarySyncSkipsWhenCloudSyncDisabled() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .completed,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.disabled))
        #expect(database.ensureZoneCallCount == 0)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
    }

    @Test @MainActor func ordinarySyncSkipsWhenTMDbAPIKeyIsMissing() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .completed,
            hasTMDbAPIKey: false
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.missingTMDbAPIKey))
        #expect(database.ensureZoneCallCount == 0)
    }

    @Test @MainActor func ordinarySyncSkipsWhenBootstrapIsIncomplete() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .needsConflictChoice,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.bootstrapIncomplete))
        #expect(database.ensureZoneCallCount == 0)
    }

    @Test @MainActor func manualRetryClearsDegradedStateAfterSuccessfulSync() async throws {
        let store = makeSyncReadyStore()
        store.updateLibraryCloudSyncStatus { status in
            status.degradedReason = "Automatic retries were exhausted."
        }
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let succeeded = await store.retryLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .success)
    }

    @Test @MainActor func remoteUpdateDoesNotEnqueueDirtyUpsert() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Remote Update", type: .series, tmdbID: 701)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let namespace = makeNamespace()
        let remoteSnapshot = makeSnapshot(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote notes",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 5)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.syncIdentity): try client.record(from: remoteSnapshot)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let refreshed = try #require(store.library.first { $0.syncIdentity == entry.syncIdentity })
        #expect(refreshed.notes == "Remote notes")
        #expect(database.savedRecords.isEmpty)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func missingRowHydratesInsertsAndAppliesSnapshot() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let identity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 702)
        let client = CloudLibrarySyncClient()
        let snapshot = makeSnapshot(
            identity: identity,
            tmdbID: 702,
            entryType: .movie,
            notes: "Hydrated"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: snapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, store in
                let entry = AnimeEntry(
                    name: "Hydrated Placeholder",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                store.repository.insert(entry)
                return entry
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let hydrated = try #require(store.library.first { $0.syncIdentity == identity })
        #expect(hydrated.notes == "Hydrated")
        #expect(hydrated.tmdbID == 702)
    }

    @Test @MainActor func missingRowWithNilClocksAppliesRemoteState() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 706)
        let client = CloudLibrarySyncClient()
        var snapshot = makeSnapshot(
            identity: identity,
            tmdbID: 706,
            notes: "Nil clock remote",
            trackingUpdatedAt: nil
        )
        snapshot.libraryUpdatedAt = nil
        snapshot.favorite = true
        snapshot.score = 5
        snapshot.watchStatus = .dropped
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: snapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, store in
                let entry = AnimeEntry(
                    name: "Hydrated Defaults",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                store.repository.insert(entry)
                return entry
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let hydrated = try #require(store.library.first { $0.syncIdentity == identity })
        #expect(hydrated.notes == "Nil clock remote")
        #expect(hydrated.favorite)
        #expect(hydrated.score == 5)
        #expect(hydrated.watchStatus == .dropped)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func staleTombstonePreservesNewerLocalState() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Stale Tombstone",
            type: .series,
            tmdbID: 703,
            dateSaved: referenceDate(year: 2026, month: 5, day: 20)
        )
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 20)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 20)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteTombstone = LibraryEntrySyncTombstone(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: referenceDate(year: 2026, month: 5, day: 3)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.syncIdentity): try client.record(from: remoteTombstone)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let refreshed = try #require(store.library.first { $0.syncIdentity == entry.syncIdentity })
        #expect(refreshed.onDisplay)
        #expect(database.savedRecords.count == 1)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func newerTombstoneSuppressesStaleLocalDirtyExport() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Fresh Tombstone",
            type: .series,
            tmdbID: 704,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 3)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 3)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteTombstone = LibraryEntrySyncTombstone(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: referenceDate(year: 2026, month: 5, day: 11)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.syncIdentity): try client.record(from: remoteTombstone)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        let stored = try #require(store.repository.existingEntry(identity: entry.syncIdentity))
        #expect(!stored.onDisplay)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: entry.syncIdentity) == nil)
        #expect(database.savedRecords.isEmpty)
    }

    @Test @MainActor func partialExportOnlyDequeuesAcceptedDirtyEntries() async throws {
        let store = makeSyncReadyStore()
        let first = AnimeEntry(name: "First Export", type: .movie, tmdbID: 707)
        let second = AnimeEntry(name: "Second Export", type: .series, tmdbID: 708)
        first.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        second.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(first)
        try store.repository.newEntry(second)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: first.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
                )),
            .upsert(
                .init(
                    identity: second.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 9)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(
            changes: [
                .init(
                    modifiedRecordsByID: [:],
                    deletedRecordIDs: [],
                    changeToken: makeToken(),
                    moreComing: false
                )
            ],
            successfulSaveRecordIDs: [client.recordID(for: first.syncIdentity)]
        )
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        let remainingEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        #expect(database.savedRecords.count == 2)
        #expect(remainingEntries.count == 1)
        #expect(remainingEntries.first?.identity == second.syncIdentity)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: first.syncIdentity) == nil)
    }

    @Test @MainActor func failedHydrationLeavesTokenUncommitted() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let namespace = makeNamespace()
        let identity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 705)
        let snapshot = makeSnapshot(
            identity: identity,
            tmdbID: 705,
            entryType: .movie,
            notes: "Needs hydrate"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: snapshot)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let tokenStore = CloudLibrarySyncChangeTokenStore(
            userDefaults: UserDefaults(suiteName: "LibrarySyncCoordinatorTests.\(UUID().uuidString)")!)
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { _, _ in
                throw HydrationFailure.unavailable
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

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
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() },
            dateProvider: { referenceDate(year: 2026, month: 6, day: 1) }
        )

        let succeeded = await store.enableLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate != nil)
        #expect(store.preferences.load().cloudSyncStatus.lastSuccessfulSyncDate != nil)
        #expect(database.savedRecords.count == 1)
        let savedSnapshot = try savedSnapshot(from: database.savedRecords[0], client: client)
        #expect(savedSnapshot.identity == entry.syncIdentity)
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
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(database.savedRecords.isEmpty)
    }
}

fileprivate enum HydrationFailure: Error {
    case unavailable
}

@MainActor
fileprivate func makeSyncReadyStore() -> LibraryStore {
    makeStore(
        enabled: true,
        bootstrapState: .completed,
        hasTMDbAPIKey: true
    )
}

@MainActor
fileprivate func makeStore(
    enabled: Bool,
    bootstrapState: LibraryCloudSyncBootstrapState,
    hasTMDbAPIKey: Bool
) -> LibraryStore {
    let suiteName = "LibrarySyncCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let preferences = LibraryPreferences(defaults: defaults)
    var status = LibraryCloudSyncStatus.defaultValue
    status.isEnabled = enabled
    status.bootstrapState = bootstrapState
    preferences.saveCloudSyncStatus(status)
    return LibraryStore(
        dataProvider: DataProvider(inMemory: true),
        preferences: preferences,
        hasTMDbAPIKey: { hasTMDbAPIKey }
    )
}

fileprivate struct ClocklessTrackingConflictFixture {
    let store: LibraryStore
    let client: CloudLibrarySyncClient
    let database: FakeCloudLibrarySyncDatabase
    let identity: LibraryEntrySyncIdentity
}

@MainActor
fileprivate func makeClocklessTrackingConflictFixture(
    repeatedRemoteFetches: Int = 1,
    dateProvider: @escaping @MainActor @Sendable () -> Date = {
        referenceDate(year: 2026, month: 6, day: 1)
    }
) throws -> ClocklessTrackingConflictFixture {
    let store = makeStore(
        enabled: false,
        bootstrapState: .notStarted,
        hasTMDbAPIKey: true
    )
    let entry = AnimeEntry(
        name: "Clockless Local",
        type: .series,
        tmdbID: 803,
        dateSaved: referenceDate(year: 2026, month: 5, day: 1)
    )
    entry.notes = "Local notes"
    entry.libraryUpdatedAt = nil
    entry.trackingUpdatedAt = nil
    try store.repository.newEntry(entry)
    try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
    store.rebuildSyncChangeTracking()

    let client = CloudLibrarySyncClient()
    var remoteSnapshot = makeSnapshot(
        identity: entry.syncIdentity,
        tmdbID: entry.tmdbID,
        notes: "Remote notes",
        trackingUpdatedAt: nil
    )
    remoteSnapshot.libraryUpdatedAt = nil
    let batch = try makeChangeBatch(client: client, snapshots: [remoteSnapshot])
    let database = FakeCloudLibrarySyncDatabase(
        changes: Array(repeating: batch, count: repeatedRemoteFetches)
    )
    store.configureLibrarySyncCoordinator(
        client: client,
        database: database,
        namespaceProvider: { makeNamespace() },
        dateProvider: dateProvider
    )
    return .init(
        store: store,
        client: client,
        database: database,
        identity: entry.syncIdentity
    )
}

fileprivate final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    private let successfulSaveRecordIDs: [CKRecord.ID]?
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    var savedRecords: [CKRecord] = []
    var ensureZoneCallCount = 0
    var suspendNextFetch = false
    var suspendedFetchCount = 0
    var isFetchSuspended = false

    init(
        changes: [CloudLibrarySyncZoneChangeBatch],
        successfulSaveRecordIDs: [CKRecord.ID]? = nil
    ) {
        self.changes = changes
        self.successfulSaveRecordIDs = successfulSaveRecordIDs
    }

    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        ensureZoneCallCount += 1
    }

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        if suspendNextFetch || suspendedFetchCount > 0 {
            if suspendNextFetch {
                suspendNextFetch = false
            }
            if suspendedFetchCount > 0 {
                suspendedFetchCount -= 1
            }
            isFetchSuspended = true
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
            }
            isFetchSuspended = false
        }
        return changes.removeFirst()
    }

    func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        savedRecords.append(contentsOf: records)
        return successfulSaveRecordIDs ?? records.map(\.recordID)
    }

    func resumeSuspendedFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }
}

fileprivate func makeNamespace() -> CloudLibrarySyncChangeTokenStore.Namespace {
    .init(
        containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
        accountIdentifier: "test-account"
    )
}

fileprivate func makeToken() -> CKServerChangeToken {
    class_createInstance(CKServerChangeToken.self, 0) as! CKServerChangeToken
}

fileprivate func makeEmptyChangeBatch() -> CloudLibrarySyncZoneChangeBatch {
    .init(
        modifiedRecordsByID: [:],
        deletedRecordIDs: [],
        changeToken: makeToken(),
        moreComing: false
    )
}

fileprivate func makeChangeBatch(
    client: CloudLibrarySyncClient,
    snapshots: [LibraryEntrySyncSnapshot]
) throws -> CloudLibrarySyncZoneChangeBatch {
    .init(
        modifiedRecordsByID: Dictionary(
            uniqueKeysWithValues: try snapshots.map { snapshot in
                (client.recordID(for: snapshot.identity), try client.record(from: snapshot))
            }
        ),
        deletedRecordIDs: [],
        changeToken: makeToken(),
        moreComing: false
    )
}

fileprivate func savedSnapshot(
    from record: CKRecord,
    client: CloudLibrarySyncClient
) throws -> LibraryEntrySyncSnapshot {
    guard case .snapshot(let snapshot) = try client.remoteChange(from: record) else {
        throw SavedRecordError.expectedSnapshot
    }
    return snapshot
}

fileprivate func makeSnapshot(
    identity: LibraryEntrySyncIdentity,
    tmdbID: Int,
    entryType: AnimeType = .series,
    notes: String = "",
    trackingUpdatedAt: Date? = referenceDate(year: 2026, month: 5, day: 1)
) -> LibraryEntrySyncSnapshot {
    LibraryEntrySyncSnapshot(
        identity: identity,
        tmdbID: tmdbID,
        parentSeriesID: entryType.parentSeriesID,
        seasonNumber: entryType.seasonNumber,
        entryType: entryType,
        onDisplay: true,
        dateSaved: referenceDate(year: 2026, month: 5, day: 1),
        watchStatus: .planToWatch,
        dateStarted: nil,
        dateFinished: nil,
        isDateTrackingEnabled: true,
        score: nil,
        favorite: false,
        notes: notes,
        usingCustomPoster: false,
        customPosterURL: nil,
        episodeProgresses: [],
        libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: 1),
        trackingUpdatedAt: trackingUpdatedAt
    )
}

fileprivate enum SavedRecordError: Error {
    case expectedSnapshot
}
