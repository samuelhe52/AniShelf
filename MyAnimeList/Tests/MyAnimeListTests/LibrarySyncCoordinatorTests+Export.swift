//
//  LibrarySyncCoordinatorTests+Export.swift
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
    @Test @MainActor
    func cancellationImmediatelyAfterExportDequeuesConfirmedDirtyEntriesWithoutRecordingSuccess() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Cancelled Export", type: .movie, tmdbID: 706)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.libraryIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextSave = true
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await coordinator.syncResult(trigger: .manualRetry)
        }
        while !database.isSaveSuspended {
            await Task.yield()
        }

        database.resumeSuspendedSave()
        coordinator.cancelAllSync()

        // `merged(with:)` seeds `.success`, so a skipped pass reports `.success`
        // here; the recorded status below is what reflects the cancellation.
        #expect(await syncTask.value == .success)
        #expect(database.savedRecords.count == 1)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
        // A pass cancelled after export must not stamp success over the status
        // the disable path already reset.
        #expect(store.libraryCloudSyncStatus.lastResult == nil)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate == nil)
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
                    identity: first.libraryIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
                )),
            .upsert(
                .init(
                    identity: second.libraryIdentity,
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
            successfulSaveRecordIDs: [client.recordID(for: first.libraryIdentity)]
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
        #expect(remainingEntries.first?.identity == second.libraryIdentity)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: first.libraryIdentity) == nil)
    }

    @Test @MainActor func partialExportFailureDequeuesAcceptedBatchesBeforeRetry() async throws {
        let store = makeSyncReadyStore()
        var dirtyEntries: [LibraryEntrySyncDirtyQueueEntry] = []
        for offset in 0..<360 {
            let tmdbID = 10_000 + offset
            let entry = AnimeEntry(
                name: "Large Export \(offset)",
                type: .series,
                tmdbID: tmdbID
            )
            entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
            store.repository.insert(entry)
            dirtyEntries.append(
                .upsert(
                    .init(
                        identity: entry.libraryIdentity,
                        dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
                    ))
            )
        }
        try store.repository.save()
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(dirtyEntries)
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(
            changes: [makeEmptyChangeBatch()],
            saveErrorsByCallIndex: [2: CKError(.networkFailure)]
        )
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.sync(trigger: .manualRetry)

        #expect(!result)
        #expect(store.libraryCloudSyncStatus.lastResult == .retryableFailure)
        #expect(database.saveBatchSizes == [350, 10])
        #expect(database.savedRecords.count == 350)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.count == 10)
    }

    @Test @MainActor func duplicateDirtyQueueEntriesDoNotCrashExportConfirmation() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Duplicate Dirty", type: .movie, tmdbID: 713)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        try store.repository.newEntry(entry)
        store.rebuildSyncChangeTracking()

        let olderEntry = LibraryEntrySyncDirtyQueueEntry.upsert(
            .init(
                identity: entry.libraryIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 8)
            ))
        let newerEntry = LibraryEntrySyncDirtyQueueEntry.upsert(
            .init(
                identity: entry.libraryIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 9)
            ))
        try writeRawDirtyQueueEntries([olderEntry, newerEntry], in: store)

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        #expect(database.savedRecords.count == 1)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func duplicateLocalSnapshotsChooseRepositoryPreferredWinner() async throws {
        let store = makeSyncReadyStore()
        let olderEntry = AnimeEntry(
            name: "Older Duplicate",
            type: .movie,
            tmdbID: 714,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        olderEntry.notes = "Older local"
        let newerEntry = AnimeEntry(
            name: "Newer Duplicate",
            type: .movie,
            tmdbID: 714,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        newerEntry.notes = "Preferred local"
        try store.repository.newEntry(olderEntry)
        try store.repository.newEntry(newerEntry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: newerEntry.libraryIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 9)
                ))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        await coordinator.sync(trigger: .manualRetry)

        let savedSnapshot = try savedSnapshot(from: try #require(database.savedRecords.first), client: client)
        #expect(database.savedRecords.count == 1)
        #expect(savedSnapshot.identity == newerEntry.libraryIdentity)
        #expect(savedSnapshot.notes == "Preferred local")
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func exportConfirmationKeepsNewerSameIdentityDirtyEntry() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(name: "Export Race", type: .movie, tmdbID: 711)
        let initialDirtyAt = referenceDate(year: 2026, month: 5, day: 8)
        let newerDirtyAt = referenceDate(year: 2026, month: 5, day: 9)
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 1))
        entry.updateNotes("Before export", at: initialDirtyAt)
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(.init(identity: entry.libraryIdentity, dirtyAt: initialDirtyAt))
        ])
        store.rebuildSyncChangeTracking()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextSave = true
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await coordinator.sync(trigger: .manualRetry)
        }
        while !database.isSaveSuspended {
            await Task.yield()
        }

        entry.updateNotes("After export started", at: newerDirtyAt)
        try store.repository.save()
        database.resumeSuspendedSave()

        _ = await syncTask.value

        let remainingEntry = try #require(
            store.syncChangeRecorder.dirtyQueueStore.load().entry(for: entry.libraryIdentity))
        guard case .upsert(let pendingUpsert) = remainingEntry else {
            Issue.record("Expected the newer same-identity upsert to remain queued.")
            return
        }
        #expect(pendingUpsert.dirtyAt == newerDirtyAt)
        #expect(database.savedRecords.count == 1)
    }
}
