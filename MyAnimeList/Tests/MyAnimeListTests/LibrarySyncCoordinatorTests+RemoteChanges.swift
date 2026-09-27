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
    @Test @MainActor func episodeCountCapDoesNotRepairUploadOrLowerCloudProgress() throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 724)
        let progressDate = referenceDate(year: 2026, month: 5, day: 5)
        var remote = makeSnapshot(identity: identity, tmdbID: 724)
        remote.episodeProgresses = [
            .init(seasonNumber: 1, watchedThroughEpisode: 12, updatedAt: progressDate)
        ]
        var cappedLocal = remote
        cappedLocal.episodeProgresses = [
            .init(seasonNumber: 1, watchedThroughEpisode: 10, updatedAt: progressDate)
        ]
        let batch = CloudLibrarySyncImportBatch(
            changes: [.snapshot(remote)], remoteChanges: [.snapshot(remote)],
            settingsSnapshot: nil, ignoredDeletedRecordIDs: [],
            changeToken: makeToken(), namespace: makeNamespace(),
            zoneID: CloudLibrarySyncClient.recordZoneID
        )
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client,
            database: FakeCloudLibrarySyncDatabase(changes: []),
            namespaceProvider: { makeNamespace() }
        )
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(.init(identity: identity, dirtyAt: progressDate))
        ])
        var snapshots = [identity: cappedLocal]

        _ = try coordinator.reconcileDirtyQueue(
            with: batch, localSnapshotsByIdentity: &snapshots, in: store
        )
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: identity) == nil)

        cappedLocal.notes = "New local note"
        cappedLocal.trackingUpdatedAt = progressDate.addingTimeInterval(60)
        snapshots = [identity: cappedLocal]
        _ = try coordinator.reconcileDirtyQueue(
            with: batch, localSnapshotsByIdentity: &snapshots, in: store
        )
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: identity) != nil)
        #expect(snapshots[identity]?.notes == "New local note")
        #expect(snapshots[identity]?.episodeProgresses.first?.watchedThroughEpisode == 12)
    }

    @Test @MainActor func newerRemoteLibraryEditKeepsUnsentLocalTrackingEdit() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Independent edits",
            type: .series,
            tmdbID: 715,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(entry)
        entry.updateNotes("Unsent local notes", at: referenceDate(year: 2026, month: 5, day: 10))
        try store.repository.save()

        let client = CloudLibrarySyncClient()
        var remote = LibraryEntrySyncSnapshot(entry: entry)
        remote.notes = ""
        remote.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 1)
        remote.onDisplay = false
        remote.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 20)
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: entry.libraryIdentity): try client.record(from: remote)],
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

        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        let saved = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: entry.libraryIdentity) })
        let uploaded = try savedSnapshot(from: saved, client: client)
        #expect(uploaded.notes == "Unsent local notes")
        #expect(!uploaded.onDisplay)
        #expect(store.repository.existingEntry(identity: entry.libraryIdentity)?.notes == "Unsent local notes")
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: entry.libraryIdentity) == nil)

        let echoDatabase = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: entry.libraryIdentity): saved],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let echoCoordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: echoDatabase,
            namespaceProvider: { makeNamespace() }
        )
        #expect(await echoCoordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(echoDatabase.savedRecords.isEmpty)
    }

    @Test @MainActor func equalClockPeersConvergeAfterImportAndEcho() async throws {
        let clock = referenceDate(year: 2026, month: 5, day: 5)
        let savedAt = referenceDate(year: 2026, month: 5, day: 1)
        let client = CloudLibrarySyncClient()

        func makePeer(notes: String) throws -> (LibraryStore, AnimeEntry) {
            let store = makeSyncReadyStore()
            let entry = AnimeEntry(name: "Tie", type: .series, tmdbID: 718, dateSaved: savedAt)
            entry.libraryUpdatedAt = savedAt
            entry.notes = notes
            entry.trackingUpdatedAt = clock
            try store.repository.newEntry(entry)
            try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
            store.rebuildSyncChangeTracking()
            return (store, entry)
        }

        let (firstStore, firstEntry) = try makePeer(notes: "Alpha")
        let (secondStore, secondEntry) = try makePeer(notes: "Zulu")
        let firstRecord = try client.record(from: LibraryEntrySyncSnapshot(entry: firstEntry))
        let secondRecord = try client.record(from: LibraryEntrySyncSnapshot(entry: secondEntry))

        func database(with record: CKRecord) -> FakeCloudLibrarySyncDatabase {
            FakeCloudLibrarySyncDatabase(changes: [
                .init(
                    modifiedRecordsByID: [record.recordID: record],
                    deletedRecordIDs: [], changeToken: makeToken(), moreComing: false
                )
            ])
        }

        let firstDatabase = database(with: secondRecord)
        let secondDatabase = database(with: firstRecord)
        let firstCoordinator = LibrarySyncCoordinator(
            store: firstStore, client: client, database: firstDatabase,
            namespaceProvider: { makeNamespace() }
        )
        let secondCoordinator = LibrarySyncCoordinator(
            store: secondStore, client: client, database: secondDatabase,
            namespaceProvider: { makeNamespace() }
        )
        #expect(await firstCoordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(await secondCoordinator.syncResult(trigger: .manualRetry) == .success)

        let firstSnapshot = LibraryEntrySyncSnapshot(entry: firstEntry)
        let secondSnapshot = LibraryEntrySyncSnapshot(entry: secondEntry)
        #expect(firstSnapshot.hasSameWireState(as: secondSnapshot))
        let winningRecord = try client.record(from: firstSnapshot)

        let firstEcho = database(with: winningRecord)
        let secondEcho = database(with: winningRecord)
        #expect(
            await LibrarySyncCoordinator(
                store: firstStore, client: client, database: firstEcho,
                namespaceProvider: { makeNamespace() }
            ).syncResult(trigger: .manualRetry) == .success)
        #expect(
            await LibrarySyncCoordinator(
                store: secondStore, client: client, database: secondEcho,
                namespaceProvider: { makeNamespace() }
            ).syncResult(trigger: .manualRetry) == .success)
        #expect(firstEcho.savedRecords.isEmpty)
        #expect(secondEcho.savedRecords.isEmpty)
    }

    @Test @MainActor func fixedPeerRepairsRecordOverwrittenAfterItsUpload() async throws {
        let savedAt = referenceDate(year: 2026, month: 5, day: 1)
        let client = CloudLibrarySyncClient()
        let firstStore = makeSyncReadyStore()
        let secondStore = makeSyncReadyStore()
        let firstEntry = AnimeEntry(name: "First", type: .series, tmdbID: 722, dateSaved: savedAt)
        let secondEntry = AnimeEntry(name: "Second", type: .series, tmdbID: 722, dateSaved: savedAt)
        for entry in [firstEntry, secondEntry] { entry.libraryUpdatedAt = savedAt }
        firstEntry.updateNotes("Middle notes", at: referenceDate(year: 2026, month: 5, day: 10))
        secondEntry.updateNotes("Newest notes", at: referenceDate(year: 2026, month: 5, day: 20))
        try firstStore.repository.newEntry(firstEntry)
        try secondStore.repository.newEntry(secondEntry)
        for (store, entry) in [(firstStore, firstEntry), (secondStore, secondEntry)] {
            try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
                .upsert(.init(identity: entry.libraryIdentity, dirtyAt: entry.trackingUpdatedAt ?? savedAt))
            ])
            store.rebuildSyncChangeTracking()
        }

        var initial = LibraryEntrySyncSnapshot(entry: firstEntry)
        initial.notes = "Old notes"
        initial.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 5)
        let database = InterleavingCloudLibrarySyncDatabase(cloudRecord: try client.record(from: initial))
        let first = LibrarySyncCoordinator(
            store: firstStore, client: client, database: database,
            namespaceProvider: { makeNamespace() }
        )
        let second = LibrarySyncCoordinator(
            store: secondStore, client: client, database: database,
            namespaceProvider: { makeNamespace() }
        )
        database.beforeNextSave = {
            #expect(await second.syncResult(trigger: .manualRetry) == .success)
            let concurrentSnapshot = try savedSnapshot(from: database.cloudRecord, client: client)
            #expect(concurrentSnapshot.notes == "Newest notes")
        }

        #expect(await first.syncResult(trigger: .manualRetry) == .success)
        #expect(database.savedRecords.count == 2)
        #expect(try savedSnapshot(from: database.cloudRecord, client: client).notes == "Middle notes")

        #expect(await second.syncResult(trigger: .cloudNotification) == .success)
        #expect(try savedSnapshot(from: database.cloudRecord, client: client).notes == "Newest notes")
        #expect(secondStore.syncChangeRecorder.dirtyQueueStore.load().entry(for: secondEntry.libraryIdentity) == nil)
    }


    @Test @MainActor func remoteUpdateDoesNotEnqueueDirtyUpsert() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Remote Update",
            type: .series,
            tmdbID: 701,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
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

    @Test @MainActor func sameIdentityEditDuringHydrationWinsOverPreimportMerge() async throws {
        let store = makeSyncReadyStore()
        let local = AnimeEntry(
            name: "Locally edited during import", type: .series, tmdbID: 720,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        local.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(local)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let missingIdentity = LibraryEntryIdentity(entryType: .movie, tmdbID: 719)
        let remoteLocal = makeSnapshot(
            identity: local.libraryIdentity, tmdbID: local.tmdbID,
            notes: "Remote notes", trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 5)
        )
        let missing = makeSnapshot(identity: missingIdentity, tmdbID: 719, entryType: .movie)
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(client: client, snapshots: [missing, remoteLocal])
        ])
        var continuation: CheckedContinuation<Void, Never>?
        var suspended = false
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client, database: database,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                suspended = true
                await withCheckedContinuation { continuation = $0 }
                return AnimeEntry(name: "Hydrated", type: snapshot.entryType, tmdbID: snapshot.tmdbID)
            }
        )
        let task = Task { await coordinator.syncResult(trigger: .manualRetry) }
        while !suspended { await Task.yield() }

        local.updateNotes("Later local notes", at: referenceDate(year: 2026, month: 5, day: 10))
        try store.repository.save()
        continuation?.resume()
        #expect(await task.value == .success)
        #expect(local.notes == "Later local notes")
        let exported = try database.savedRecords.map { try savedSnapshot(from: $0, client: client) }
        #expect(exported.contains { $0.identity == local.libraryIdentity && $0.notes == "Later local notes" })
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

    @Test @MainActor func equalClockRemoteSnapshotBeatsPendingDelete() async throws {
        let store = makeSyncReadyStore()
        let identity = LibraryEntryIdentity(entryType: .movie, tmdbID: 721)
        let snapshot = makeSnapshot(
            identity: identity, tmdbID: 721, entryType: .movie,
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 10)
        )
        let deletedAt = try #require(snapshot.latestUserStateClock)
        let tombstone = LibraryEntrySyncTombstone(
            identity: identity, tmdbID: 721, parentSeriesID: nil,
            seasonNumber: nil, entryType: .movie, deletedAt: deletedAt
        )
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .delete(.init(tombstone: tombstone))
        ])
        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(client: client, snapshots: [snapshot])
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client, database: database,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                AnimeEntry(name: "Restored equal-clock entry", type: snapshot.entryType, tmdbID: snapshot.tmdbID)
            }
        )

        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(store.repository.existingEntry(identity: identity)?.onDisplay == true)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: identity) == nil)
        #expect(database.savedRecords.isEmpty)
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

    enum HydrationFailureKind: CaseIterable {
        case network
        case permission
        case cancellation
    }

    @Test(arguments: HydrationFailureKind.allCases)
    @MainActor func bootstrapHydrationRetainsFailureContextAndCancellation(kind: HydrationFailureKind) async throws {
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
        let underlyingError: NSError =
            kind == .permission
            ? CKError(.permissionFailure) as NSError
            : URLError(.notConnectedToInternet) as NSError
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { _, _ in
                if kind == .cancellation { throw CancellationError() }
                throw underlyingError
            }
        )

        let result = await coordinator.bootstrapFirstEnablement(preference: nil)
        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(store.library.isEmpty)
        #expect(store.repository.existingEntry(identity: identity) == nil)
        #expect(database.savedRecords.isEmpty)
        if kind == .cancellation {
            #expect(result == .skipped(.disabled))
            #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
            #expect(store.libraryCloudSyncStatus.lastFailureReason == nil)
            #expect(store.libraryCloudSyncStatus.lastFailurePhase == nil)
            return
        }
        #expect(result == (kind == .permission ? .permanentFailure : .retryableFailure))
        let failure = store.libraryCloudSyncStatus
        #expect(failure.bootstrapState == .failed)
        #expect(failure.lastFailurePhase == .hydrationApply)
        #expect(!failure.isSyncInProgress)
        let reason = try #require(failure.lastFailureReason)
        #expect(reason.contains(identity.rawID))
        #expect(reason.contains(underlyingError.localizedDescription))
        #expect(reason.contains("\(underlyingError.domain):\(underlyingError.code)"))
        #expect(failure.failureReasonDisplay?.contains("hydrationApply") == true)

        let skipped = await coordinator.syncResult(trigger: .foreground)
        #expect(skipped == .skipped(.bootstrapIncomplete))
        #expect(store.libraryCloudSyncStatus == failure)
        #expect(store.preferences.load().cloudSyncStatus == failure)
    }
}
