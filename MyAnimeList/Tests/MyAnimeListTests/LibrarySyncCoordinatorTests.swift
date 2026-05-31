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
                modifiedRecordsByID: [client.recordID(for: entry.syncIdentity): try client.record(from: remoteSnapshot)],
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
            .upsert(.init(
                identity: entry.syncIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 20)
            ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        var remoteSnapshot = makeSnapshot(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote stale",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 2)
        )
        remoteSnapshot.deletedAt = referenceDate(year: 2026, month: 5, day: 3)
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: entry.syncIdentity): try client.record(from: remoteSnapshot)],
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
            .upsert(.init(
                identity: entry.syncIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 3)
            ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        var remoteSnapshot = makeSnapshot(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote delete",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 10)
        )
        remoteSnapshot.deletedAt = referenceDate(year: 2026, month: 5, day: 11)
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: entry.syncIdentity): try client.record(from: remoteSnapshot)],
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
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: UserDefaults(suiteName: "LibrarySyncCoordinatorTests.\(UUID().uuidString)")!)
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

private enum HydrationFailure: Error {
    case unavailable
}

private final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    var savedRecords: [CKRecord] = []

    init(changes: [CloudLibrarySyncZoneChangeBatch]) {
        self.changes = changes
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
        return records.map(\.recordID)
    }
}

private func makeNamespace() -> CloudLibrarySyncChangeTokenStore.Namespace {
    .init(
        containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
        accountIdentifier: "test-account"
    )
}

private func makeToken() -> CKServerChangeToken {
    class_createInstance(CKServerChangeToken.self, 0) as! CKServerChangeToken
}

private func makeSnapshot(
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
