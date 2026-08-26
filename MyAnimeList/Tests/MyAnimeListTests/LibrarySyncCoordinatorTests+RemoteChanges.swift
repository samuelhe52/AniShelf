//
//  LibrarySyncCoordinatorTests+RemoteChanges.swift
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
            identity: entry.libraryIdentity,
            tmdbID: entry.tmdbID,
            notes: "Remote notes",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 5)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.libraryIdentity): try client.record(from: remoteSnapshot)
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
        let refreshed = try #require(store.library.first { $0.libraryIdentity == entry.libraryIdentity })
        #expect(refreshed.notes == "Remote notes")
        #expect(database.savedRecords.isEmpty)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func missingRowHydratesInsertsAndAppliesSnapshot() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let identity = LibraryEntryIdentity(entryType: .movie, tmdbID: 702)
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
            hydrateMissingEntry: { snapshot, _ in
                AnimeEntry(
                    name: "Hydrated Placeholder",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let hydrated = try #require(store.library.first { $0.libraryIdentity == identity })
        #expect(hydrated.notes == "Hydrated")
        #expect(hydrated.tmdbID == 702)
    }

    @Test @MainActor func missingRowWithNilClocksAppliesRemoteState() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 706)
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
            hydrateMissingEntry: { snapshot, _ in
                AnimeEntry(
                    name: "Hydrated Defaults",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
            }
        )

        await coordinator.sync(trigger: .manualRetry)

        try store.refreshLibrary()
        let hydrated = try #require(store.library.first { $0.libraryIdentity == identity })
        #expect(hydrated.notes == "Nil clock remote")
        #expect(hydrated.favorite)
        #expect(hydrated.score == 5)
        #expect(hydrated.watchStatus == .dropped)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func userEditDuringHydrationStillExports() async throws {
        let store = makeSyncReadyStore()
        let unrelated = AnimeEntry(name: "Unrelated Local", type: .movie, tmdbID: 709)
        unrelated.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(unrelated)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let namespace = makeNamespace()
        let remoteIdentity = LibraryEntryIdentity(entryType: .movie, tmdbID: 710)
        let client = CloudLibrarySyncClient()
        let remoteSnapshot = makeSnapshot(
            identity: remoteIdentity,
            tmdbID: 710,
            entryType: .movie,
            notes: "Hydrated remote"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: remoteIdentity): try client.record(from: remoteSnapshot)
                ],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        var hydrationContinuation: CheckedContinuation<Void, Never>?
        var isHydrationSuspended = false
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, _ in
                isHydrationSuspended = true
                await withCheckedContinuation { continuation in
                    hydrationContinuation = continuation
                }
                return AnimeEntry(
                    name: "Hydrated Placeholder",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
            }
        )

        let syncTask = Task {
            await coordinator.sync(trigger: .manualRetry)
        }
        while !isHydrationSuspended {
            await Task.yield()
        }

        unrelated.updateNotes(
            "User edit during hydration",
            at: referenceDate(year: 2026, month: 5, day: 12)
        )
        try store.repository.save()
        hydrationContinuation?.resume()

        _ = await syncTask.value

        let savedSnapshots = try database.savedRecords.map {
            try savedSnapshot(from: $0, client: client)
        }
        #expect(
            savedSnapshots.contains { snapshot in
                snapshot.identity == unrelated.libraryIdentity
                    && snapshot.notes == "User edit during hydration"
            })
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func cancellationDoesNotLeaveHydratedPendingInserts() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let firstIdentity = LibraryEntryIdentity(entryType: .movie, tmdbID: 712)
        let secondIdentity = LibraryEntryIdentity(entryType: .movie, tmdbID: 713)
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(
                client: client,
                snapshots: [
                    makeSnapshot(identity: firstIdentity, tmdbID: 712, entryType: .movie),
                    makeSnapshot(identity: secondIdentity, tmdbID: 713, entryType: .movie)
                ]
            )
        ])
        var hydrationCount = 0
        var hydrationContinuation: CheckedContinuation<Void, Never>?
        var isSecondHydrationSuspended = false
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                hydrationCount += 1
                let entry = AnimeEntry(
                    name: "Detached Hydration",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                if hydrationCount == 2 {
                    isSecondHydrationSuspended = true
                    await withCheckedContinuation { continuation in
                        hydrationContinuation = continuation
                    }
                }
                return entry
            }
        )

        let syncTask = Task {
            await coordinator.syncResult(trigger: .manualRetry)
        }
        while !isSecondHydrationSuspended {
            await Task.yield()
        }

        #expect(store.repository.existingEntry(identity: firstIdentity) == nil)
        #expect(store.repository.existingEntry(identity: secondIdentity) == nil)

        syncTask.cancel()
        hydrationContinuation?.resume()
        let result = await syncTask.value

        let unrelated = AnimeEntry(name: "Later local save", type: .movie, tmdbID: 714)
        try store.repository.newEntry(unrelated)

        #expect(result == .success)
        #expect(store.repository.existingEntry(identity: firstIdentity) == nil)
        #expect(store.repository.existingEntry(identity: secondIdentity) == nil)
    }

    @Test @MainActor func pendingLocalDeletePreventsStaleRemoteSnapshotHydration() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Deleted Local",
            type: .series,
            tmdbID: 711,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 1)
        try store.repository.newEntry(entry)
        let identity = entry.libraryIdentity
        try store.repository.deleteEntry(entry)

        let client = CloudLibrarySyncClient()
        let staleRemoteSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 711,
            notes: "Stale remote",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 1)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: identity): try client.record(from: staleRemoteSnapshot)
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

        let result = await coordinator.syncResult(trigger: .localChange)

        #expect(result == .success)
        #expect(store.repository.existingEntry(identity: identity) == nil)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: identity) == nil)
        let savedRecord = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: identity) }
        )
        guard case .tombstone(let savedTombstone) = try client.remoteChange(from: savedRecord) else {
            Issue.record("Expected the pending local delete to export a tombstone.")
            return
        }
        #expect(savedTombstone.identity == identity)
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
                    identity: entry.libraryIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 20)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let remoteTombstone = LibraryEntrySyncTombstone(
            identity: entry.libraryIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: referenceDate(year: 2026, month: 5, day: 3)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.libraryIdentity): try client.record(from: remoteTombstone)
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
        let refreshed = try #require(store.library.first { $0.libraryIdentity == entry.libraryIdentity })
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
                    identity: entry.libraryIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 3)
                ))
        ])
        store.rebuildSyncChangeTracking()
        try store.refreshLibrary()

        let client = CloudLibrarySyncClient()
        let remoteTombstone = LibraryEntrySyncTombstone(
            identity: entry.libraryIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: referenceDate(year: 2026, month: 5, day: 11)
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entry.libraryIdentity): try client.record(from: remoteTombstone)
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

        await coordinator.sync(trigger: .cloudNotification)

        let stored = try #require(store.repository.existingEntry(identity: entry.libraryIdentity))
        #expect(!stored.onDisplay)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: entry.libraryIdentity) == nil)
        #expect(database.savedRecords.isEmpty)
    }

    @Test @MainActor func duplicateRemoteChangesCoalesceBeforeDirtyQueueReconciliation() throws {
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 712)
        let olderRemoteSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 712,
            notes: "Older remote",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 2)
        )
        let newerRemoteSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 712,
            notes: "Newer remote",
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 9)
        )

        let changesByIdentity = try LibrarySyncCoordinator.coalescedRemoteChangesByIdentity([
            .snapshot(olderRemoteSnapshot),
            .snapshot(newerRemoteSnapshot)
        ])

        let mergedChange = try #require(changesByIdentity[identity])
        guard case .snapshot(let mergedSnapshot) = mergedChange else {
            Issue.record("Expected duplicate snapshots to merge into a snapshot.")
            return
        }
        #expect(mergedSnapshot.notes == "Newer remote")
        #expect(mergedSnapshot.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 9))
    }

    @Test @MainActor func failedHydrationLeavesTokenUncommitted() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let namespace = makeNamespace()
        let identity = LibraryEntryIdentity(entryType: .movie, tmdbID: 705)
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
