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
            }
        )

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 110_000_000)

        #expect(syncCount == 5)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(syncCount == 5)
    }

    @Test @MainActor func dirtyQueueSchedulerDoesNotRetryPermanentFailure() async throws {
        var syncCount = 0
        let scheduler = LibrarySyncScheduler(
            localDebounceInterval: 0.01,
            failureRetryIntervals: [0.02],
            hasPendingDirtyWork: {
                true
            },
            sync: { _ in
                syncCount += 1
                return .permanentFailure
            }
        )

        scheduler.scheduleLocalDirtyQueueSync()
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(syncCount == 1)
    }

    @Test @MainActor func remoteUpdateDoesNotEnqueueDirtyUpsert() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
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
}

fileprivate enum HydrationFailure: Error {
    case unavailable
}

fileprivate final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    private let successfulSaveRecordIDs: [CKRecord.ID]?
    var savedRecords: [CKRecord] = []

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
    ) async throws {}

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        changes.removeFirst()
    }

    func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        savedRecords.append(contentsOf: records)
        return successfulSaveRecordIDs ?? records.map(\.recordID)
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
