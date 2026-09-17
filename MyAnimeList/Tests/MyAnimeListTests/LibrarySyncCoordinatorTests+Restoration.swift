//
//  LibrarySyncCoordinatorTests+Restoration.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/9/12.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

extension LibrarySyncCoordinatorTests {
    @Test @MainActor func restorationSavesBatchesAndRetriesOnlyMissingEntries() async throws {
        let store = makeStore(enabled: true, bootstrapState: .notStarted, hasTMDbAPIKey: true)
        let client = CloudLibrarySyncClient()
        let snapshots = restorationSnapshots(count: 34)
        let batch = try makeChangeBatch(client: client, snapshots: snapshots)
        let database = FakeCloudLibrarySyncDatabase(changes: [batch, batch])
        let tokens = CloudLibrarySyncChangeTokenStore(
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client, database: database, changeTokenStore: tokens,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, store in
                if snapshot.tmdbID == 1016 { #expect(store.library.count == 15) }
                if snapshot.tmdbID == 1001 || snapshot.tmdbID == 1032 { throw HydrationFailure.unavailable }
                return restorationEntry(snapshot)
            }
        )
        #expect(await coordinator.bootstrapFirstEnablement(preference: nil) == .retryableFailure)
        #expect(store.library.count == 32)
        #expect(store.libraryCloudSyncStatus.restoration?.restoredEntries == 32)
        #expect(store.libraryCloudSyncStatus.restoration?.failures.count == 2)
        #expect(tokens.token(for: CloudLibrarySyncClient.recordZoneID, namespace: makeNamespace()) == nil)
        #expect(database.savedRecords.isEmpty)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)

        let edited = try #require(store.repository.existingEntry(identity: snapshots[0].identity))
        edited.updateNotes("Edited between retries", at: .now)
        try store.repository.save()
        let deleted = try #require(store.repository.existingEntry(identity: snapshots[2].identity))
        try store.repository.deleteEntry(deleted)
        // Recreate the store/coordinator using the persisted data and preferences.
        let resumed = LibraryStore(
            dataProvider: store.dataProvider, preferences: store.preferences, hasTMDbAPIKey: { true })
        // In-memory providers deliberately allocate a fresh temporary queue per
        // recorder. Carry the saved queue over as a disk-backed relaunch would.
        try resumed.syncChangeRecorder.dirtyQueueStore.replaceEntries(
            store.syncChangeRecorder.dirtyQueueStore.load().entries
        )
        var retriedIDs: [Int] = []
        let retry = LibrarySyncCoordinator(
            store: resumed, client: client, database: database, changeTokenStore: tokens,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                retriedIDs.append(snapshot.tmdbID)
                return restorationEntry(snapshot)
            }
        )
        #expect(await retry.bootstrapFirstEnablement(preference: nil, isUserRetry: true) == .success)
        #expect(retriedIDs == [1001, 1032])
        #expect(resumed.library.count == 33)
        #expect(resumed.repository.existingEntry(identity: snapshots[0].identity)?.notes == "Edited between retries")
        #expect(resumed.repository.existingEntry(identity: snapshots[2].identity) == nil)
        #expect(resumed.libraryCloudSyncStatus.restoration == nil)
        #expect(tokens.token(for: CloudLibrarySyncClient.recordZoneID, namespace: makeNamespace()) != nil)
        let exported = try database.savedRecords.filter { $0.recordType == CloudLibrarySyncClient.recordType }
            .map { try client.remoteChange(from: $0) }
        #expect(Set(exported.map(\.identity)) == [snapshots[0].identity, snapshots[2].identity])
    }

    @Test @MainActor func interruptedRestorationRetainsOnlyCompletedBatch() async throws {
        let store = makeStore(enabled: true, bootstrapState: .notStarted, hasTMDbAPIKey: true)
        let client = CloudLibrarySyncClient()
        let snapshots = restorationSnapshots(count: 18)
        let database = FakeCloudLibrarySyncDatabase(changes: [try makeChangeBatch(client: client, snapshots: snapshots)]
        )
        var resume: CheckedContinuation<Void, Never>?
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client, database: database, namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                if snapshot.tmdbID == 1017 {
                    await withCheckedContinuation { resume = $0 }
                }
                return restorationEntry(snapshot)
            }
        )
        let task = Task { await coordinator.bootstrapFirstEnablement(preference: nil) }
        while resume == nil { await Task.yield() }
        #expect(store.library.count == 16)
        task.cancel()
        resume?.resume()
        #expect(await task.value == .skipped(.disabled))
        try store.repository.save()
        #expect(store.repository.existingEntry(identity: snapshots[16].identity) == nil)
        #expect(store.library.count == 16)
        #expect(store.libraryCloudSyncStatus.restoration?.restoredEntries == 16)
        #expect(database.savedRecords.isEmpty)
    }

    @Test @MainActor func discardEligibilityCountsOnlyRecentExplicitRetriesForSameSnapshot() throws {
        let snapshot = restorationSnapshots(count: 1)[0]
        let now = Date.now
        var state = LibraryRestorationState(scope: makeSyncScope())
        let error = LibrarySyncHydrationError(
            identity: snapshot.identity, underlyingError: HydrationFailure.unavailable)
        state.recordFailure(snapshot: snapshot, error: error, isUserRetry: false, at: now)
        for index in 1...2 {
            state.recordFailure(
                snapshot: snapshot, error: error, isUserRetry: true, at: now.addingTimeInterval(Double(index)))
        }
        state.recordFailure(snapshot: snapshot, error: error, isUserRetry: false, at: now.addingTimeInterval(3))
        #expect(!state.failures[0].canDiscard(at: now.addingTimeInterval(3)))
        state.recordFailure(snapshot: snapshot, error: error, isUserRetry: true, at: now.addingTimeInterval(4))
        #expect(state.failures[0].canDiscard(at: now.addingTimeInterval(4)))
        #expect(!state.failures[0].canDiscard(at: now.addingTimeInterval(LibraryRestorationFailure.retryWindow + 5)))
        var changed = snapshot
        changed.notes = "Changed on another device"
        state.recordFailure(snapshot: changed, error: error, isUserRetry: true, at: now.addingTimeInterval(5))
        #expect(!state.failures[0].canDiscard(at: now.addingTimeInterval(5)))
    }

    @Test @MainActor func seasonRestorationSavesParentCloudStateInTheSameBatch() async throws {
        let store = makeStore(enabled: true, bootstrapState: .notStarted, hasTMDbAPIKey: true)
        let client = CloudLibrarySyncClient()
        let type = AnimeType.season(seasonNumber: 1, parentSeriesID: 555)
        let season = makeSnapshot(identity: .init(entryType: type, tmdbID: 777), tmdbID: 777, entryType: type)
        var parent = makeSnapshot(
            identity: .init(entryType: .series, tmdbID: 555), tmdbID: 555, notes: "Parent cloud notes")
        parent.trackingUpdatedAt = nil
        parent.libraryUpdatedAt = nil
        // Put the season before its parent's own remote record, across a batch boundary.
        let filler = (2...16).map { number in
            let type = AnimeType.season(seasonNumber: number, parentSeriesID: 555)
            return makeSnapshot(
                identity: .init(entryType: type, tmdbID: 776 + number), tmdbID: 776 + number, entryType: type)
        }
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(client: client, snapshots: [season] + filler + [parent])
        ])
        var parentHydrations = 0
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client, database: database, namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                if snapshot.identity == parent.identity { parentHydrations += 1 }
                return restorationEntry(snapshot)
            }
        )
        #expect(await coordinator.bootstrapFirstEnablement(preference: nil) == .success)
        let restoredSeason = try #require(store.repository.existingEntry(identity: season.identity))
        #expect(restoredSeason.parentSeriesEntry?.notes == "Parent cloud notes")
        #expect(parentHydrations == 1)
        #expect(database.savedRecords.isEmpty)
    }

    @Test(arguments: [false, true])
    @MainActor func discardRequiresThreeRetriesAndMatchingAccount(accountChanged: Bool) async throws {
        let store = makeStore(enabled: true, bootstrapState: .notStarted, hasTMDbAPIKey: true)
        let client = CloudLibrarySyncClient()
        let snapshot = restorationSnapshots(count: 1)[0]
        let batch = try makeChangeBatch(client: client, snapshots: [snapshot])
        let database = FakeCloudLibrarySyncDatabase(
            changes: Array(repeating: batch, count: 4) + [makeEmptyChangeBatch()])
        let namespace = TestNamespaceState(makeNamespace())
        store.configureLibrarySyncCoordinator(
            client: client, database: database, namespaceProvider: { namespace.value },
            hydrateMissingEntry: { _, _ in throw HydrationFailure.unavailable }
        )
        #expect(!(await store.enableLibraryCloudSync()))
        let first = try #require(store.libraryCloudSyncStatus.restoration?.failures.first)
        #expect(!(await store.discardFailedRestorationEntry(first)))
        #expect(!(await store.retryLibraryCloudSync()))
        #expect(!(await store.rebuildLibraryCloudSync()))
        #expect(!(await store.retryLibraryCloudSync()))
        let eligible = try #require(store.libraryCloudSyncStatus.restoration?.failures.first)
        #expect(eligible.canDiscard(at: .now))
        #expect(store.preferences.load().cloudSyncStatus.restoration?.failures.first == eligible)
        if accountChanged {
            namespace.value = .init(
                containerIdentifier: namespace.value.containerIdentifier, accountIdentifier: "different-account")
        }
        _ = await store.discardFailedRestorationEntry(eligible)
        if accountChanged {
            #expect(database.savedRecords.isEmpty)
        } else {
            #expect(database.savedRecords.count == 1)
            guard case .tombstone(let deletion) = try client.remoteChange(from: #require(database.savedRecords.first))
            else {
                Issue.record("Expected only the explicitly selected entry's deletion")
                return
            }
            #expect(deletion.identity == snapshot.identity)
            #expect(deletion.deletedAt > (snapshot.latestUserStateClock ?? .distantPast))
        }
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
    }

    @Test @MainActor func unconfirmedDiscardRemainsPendingUntilRetryConfirmsIt() async throws {
        let store = makeStore(enabled: true, bootstrapState: .notStarted, hasTMDbAPIKey: true)
        let client = CloudLibrarySyncClient()
        let snapshot = restorationSnapshots(count: 1)[0]
        let batch = try makeChangeBatch(client: client, snapshots: [snapshot])
        let database = FakeCloudLibrarySyncDatabase(
            changes: Array(repeating: batch, count: 4) + [makeEmptyChangeBatch()],
            saveErrorsByCallIndex: [1: CKError(.networkFailure)]
        )
        store.configureLibrarySyncCoordinator(
            client: client, database: database, namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { _, _ in throw HydrationFailure.unavailable }
        )
        _ = await store.enableLibraryCloudSync()
        for _ in 0..<3 { _ = await store.retryLibraryCloudSync() }
        let eligible = try #require(store.libraryCloudSyncStatus.restoration?.failures.first)
        #expect(!(await store.discardFailedRestorationEntry(eligible)))
        let pending = try #require(store.preferences.load().cloudSyncStatus.restoration?.failures.first)
        #expect(pending.discardDate != nil)
        #expect(database.savedRecords.isEmpty)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(await store.retryLibraryCloudSync())
        guard case .tombstone(let confirmed) = try client.remoteChange(from: #require(database.savedRecords.first))
        else {
            Issue.record("Expected a confirmed deletion")
            return
        }
        #expect(confirmed.deletedAt == pending.discardDate)
        #expect(store.libraryCloudSyncStatus.restoration == nil)
    }
}

@MainActor
fileprivate final class TestNamespaceState {
    var value: CloudLibrarySyncChangeTokenStore.Namespace

    init(_ value: CloudLibrarySyncChangeTokenStore.Namespace) {
        self.value = value
    }
}

@MainActor
fileprivate func restorationEntry(_ snapshot: LibraryEntrySyncSnapshot) -> AnimeEntry {
    AnimeEntry(name: "Restored \(snapshot.tmdbID)", type: snapshot.entryType, tmdbID: snapshot.tmdbID)
}

fileprivate func restorationSnapshots(count: Int) -> [LibraryEntrySyncSnapshot] {
    (1000..<(1000 + count)).map { id in
        makeSnapshot(
            identity: .init(entryType: .movie, tmdbID: id), tmdbID: id, entryType: .movie, notes: "Saved \(id)")
    }
}
