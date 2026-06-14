//
//  LibrarySyncRecorderBehaviorTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import SwiftData
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

struct LibrarySyncRecorderBehaviorTests {
    @Test @MainActor func testLibrarySyncRecorderQueuesUpsertsAndIgnoresMetadataOnlySaves() throws {
        let queueURL = makeTemporaryQueueURL(name: "metadata-only-save")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let dataProvider = DataProvider(inMemory: true)
        var writeCount = 0
        let dirtyQueueStore = LibraryEntrySyncDirtyQueueStore(url: queueURL) { queue in
            writeCount += 1
            try persistQueue(queue, to: queueURL)
        }
        let recorder = LibrarySyncChangeRecorder(
            dataProvider: dataProvider,
            dirtyQueueStore: dirtyQueueStore,
            notificationCenter: .default
        )
        var dirtyQueueChangeCount = 0
        recorder.onDirtyQueueChanged = {
            dirtyQueueChangeCount += 1
        }
        let repository = LibraryRepository(
            dataProvider: dataProvider,
            syncChangeRecorder: recorder
        )
        let entry = AnimeEntry(
            name: "Tracked Entry",
            type: .series,
            tmdbID: 200_001
        )
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 30))

        try repository.newEntry(entry)

        var queue = recorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        #expect(queue.entries.first?.identity.rawID == entry.syncIdentity.rawID)
        #expect(writeCount == 1)
        #expect(dirtyQueueChangeCount == 1)

        entry.name = "Metadata Only"
        try repository.save()

        queue = recorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        #expect(writeCount == 1)
        #expect(dirtyQueueChangeCount == 1)

        entry.updateFavorite(true, at: referenceDate(year: 2026, month: 5, day: 31))
        try repository.save()

        queue = recorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        #expect(writeCount == 2)
        #expect(dirtyQueueChangeCount == 2)
        if case .upsert(let pendingUpsert)? = queue.entries.first {
            #expect(pendingUpsert.dirtyAt == entry.trackingUpdatedAt)
        } else {
            #expect(Bool(false))
        }
    }

    @Test @MainActor func testLibrarySyncRecorderKeepsBaselineWhenUpsertWriteFails() throws {
        let queueURL = makeTemporaryQueueURL(name: "upsert-write-failure")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let dataProvider = DataProvider(inMemory: true)
        var shouldFailWrite = true
        let dirtyQueueStore = LibraryEntrySyncDirtyQueueStore(url: queueURL) { queue in
            if shouldFailWrite {
                throw QueueWriteTestError.injectedWriteFailure
            }
            try persistQueue(queue, to: queueURL)
        }
        let recorder = LibrarySyncChangeRecorder(
            dataProvider: dataProvider,
            dirtyQueueStore: dirtyQueueStore,
            notificationCenter: .init()
        )
        var dirtyQueueChangeCount = 0
        recorder.onDirtyQueueChanged = {
            dirtyQueueChangeCount += 1
        }
        let entry = AnimeEntry(
            name: "Failed Queue Entry",
            type: .series,
            tmdbID: 200_002
        )
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 5, day: 30))
        try dataProvider.dataHandler.newEntry(entry)

        let notification = Notification(
            name: ModelContext.didSave,
            object: nil,
            userInfo: [
                ModelContext.NotificationKey.insertedIdentifiers.rawValue: Set([entry.id])
            ]
        )

        recorder.processSaveNotification(notification)
        #expect(recorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(dirtyQueueChangeCount == 0)

        shouldFailWrite = false
        recorder.processSaveNotification(notification)

        let queue = recorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        #expect(queue.entries.first?.identity == entry.syncIdentity)
        #expect(dirtyQueueChangeCount == 1)
    }

    @Test @MainActor func testLibrarySyncRecorderSkipsDetailIdentifiersThatResolveToEntry() throws {
        let queueURL = makeTemporaryQueueURL(name: "detail-identifier-skip")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let dataProvider = DataProvider(inMemory: true)
        var writeCount = 0
        let dirtyQueueStore = LibraryEntrySyncDirtyQueueStore(url: queueURL) { queue in
            writeCount += 1
            try persistQueue(queue, to: queueURL)
        }
        let recorder = LibrarySyncChangeRecorder(
            dataProvider: dataProvider,
            dirtyQueueStore: dirtyQueueStore,
            notificationCenter: .init()
        )
        var dirtyQueueChangeCount = 0
        recorder.onDirtyQueueChanged = {
            dirtyQueueChangeCount += 1
        }

        let entry = AnimeEntry(
            name: "Detail Identifier",
            type: .series,
            tmdbID: 200_004
        )
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 6, day: 12))
        entry.replaceDetail(
            from: AnimeEntryDetailDTO(
                language: "en-US",
                title: "Detail Identifier"
            ))
        try dataProvider.dataHandler.newEntry(entry)
        let detailID = try #require(entry.detail?.id)

        try recorder.dirtyQueueStore.replaceEntries([])
        recorder.rebuildBaseline()
        writeCount = 0
        dirtyQueueChangeCount = 0

        let notification = Notification(
            name: ModelContext.didSave,
            object: nil,
            userInfo: [
                ModelContext.NotificationKey.updatedIdentifiers.rawValue: Set([detailID])
            ]
        )

        recorder.processSaveNotification(notification)

        #expect(recorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(writeCount == 0)
        #expect(dirtyQueueChangeCount == 0)
    }

    @Test @MainActor func testLibrarySyncRecorderHandlesSaveNotificationsPostedOffMainActor()
        async throws
    {
        let queueURL = makeTemporaryQueueURL(name: "off-main-save-notification")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let notificationCenter = NotificationCenter()
        let dataProvider = DataProvider(inMemory: true)
        let dirtyQueueStore = LibraryEntrySyncDirtyQueueStore(url: queueURL) { queue in
            try persistQueue(queue, to: queueURL)
        }
        let recorder = LibrarySyncChangeRecorder(
            dataProvider: dataProvider,
            dirtyQueueStore: dirtyQueueStore,
            notificationCenter: notificationCenter
        )
        let entry = AnimeEntry(
            name: "Off Main Notification",
            type: .movie,
            tmdbID: 200_003
        )
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 6, day: 11))
        try dataProvider.dataHandler.newEntry(entry)
        let entryID = entry.id

        await Task.detached {
            notificationCenter.post(
                name: ModelContext.didSave,
                object: nil,
                userInfo: [
                    ModelContext.NotificationKey.insertedIdentifiers.rawValue: Set([entryID])
                ]
            )
        }.value

        for _ in 0..<20 where recorder.dirtyQueueStore.load().entries.isEmpty {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let queue = recorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        #expect(queue.entries.first?.identity == entry.syncIdentity)
    }

    @Test @MainActor func testLibrarySyncRecorderQueuesDeleteTombstonesAndBulkDeletes() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let first = AnimeEntry(
            name: "Delete Me 1",
            type: .movie,
            tmdbID: 300_001
        )
        let second = AnimeEntry(
            name: "Delete Me 2",
            type: .movie,
            tmdbID: 300_002
        )
        store.applyNewEntryDefaults(to: first)
        store.applyNewEntryDefaults(to: second)
        try store.repository.newEntry(first)
        try store.repository.newEntry(second)

        try store.repository.deleteEntry(first)

        var queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 2)
        #expect(
            queue.entries.contains { entry in
                guard case .delete(let pendingDelete) = entry else { return false }
                return pendingDelete.identity == first.syncIdentity
            })

        let actions = LibraryProfileSettingsActions(store: store)
        actions.clearLibrary()

        queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 2)
        #expect(
            queue.entries.allSatisfy {
                if case .delete = $0 { return true }
                return false
            })
    }

    @Test @MainActor func testLibrarySyncRecorderRecordsBulkDeletesWithSingleQueueRewrite() throws {
        let queueURL = makeTemporaryQueueURL(name: "batch-delete")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let retainedUpsert = LibraryEntrySyncPendingUpsert(
            identity: .init(entryType: .series, tmdbID: 399_999),
            dirtyAt: referenceDate(year: 2026, month: 5, day: 29)
        )
        try persistQueue(
            .init(entries: [.upsert(retainedUpsert)]),
            to: queueURL
        )

        let dataProvider = DataProvider(inMemory: true)
        var writeCount = 0
        let dirtyQueueStore = LibraryEntrySyncDirtyQueueStore(url: queueURL) { queue in
            writeCount += 1
            if writeCount > 1 {
                throw QueueWriteTestError.unexpectedAdditionalWrite
            }
            try persistQueue(queue, to: queueURL)
        }
        let recorder = LibrarySyncChangeRecorder(
            dataProvider: dataProvider,
            dirtyQueueStore: dirtyQueueStore,
            notificationCenter: .init()
        )
        var dirtyQueueChangeCount = 0
        recorder.onDirtyQueueChanged = {
            dirtyQueueChangeCount += 1
        }

        let first = AnimeEntry(name: "Batch Delete 1", type: .movie, tmdbID: 300_101)
        let second = AnimeEntry(name: "Batch Delete 2", type: .movie, tmdbID: 300_102)
        let deletedAt = referenceDate(year: 2026, month: 5, day: 30)

        let tokens = try recorder.recordDeletions(for: [first, second], deletedAt: deletedAt)

        #expect(writeCount == 1)
        #expect(tokens.count == 2)
        #expect(dirtyQueueChangeCount == 1)

        let queue = dirtyQueueStore.load()
        #expect(queue.entries.count == 3)
        #expect(queue.entry(for: retainedUpsert.identity) == .upsert(retainedUpsert))
        #expect(
            queue.entry(for: first.syncIdentity)
                == .delete(
                    .init(
                        tombstone: .init(entry: first, deletedAt: deletedAt)
                    )))
        #expect(
            queue.entry(for: second.syncIdentity)
                == .delete(
                    .init(
                        tombstone: .init(entry: second, deletedAt: deletedAt)
                    )))
    }

    @Test @MainActor func testLibrarySyncRecorderRestoreDeleteRecordsRewritesPriorQueueOnce() throws {
        let queueURL = makeTemporaryQueueURL(name: "delete-rollback")
        defer { try? FileManager.default.removeItem(at: queueURL.deletingLastPathComponent()) }

        let restoredUpsert = LibraryEntrySyncPendingUpsert(
            identity: .init(entryType: .movie, tmdbID: 300_201),
            dirtyAt: referenceDate(year: 2026, month: 5, day: 27)
        )
        let retainedUpsert = LibraryEntrySyncPendingUpsert(
            identity: .init(entryType: .series, tmdbID: 300_202),
            dirtyAt: referenceDate(year: 2026, month: 5, day: 28)
        )
        let deletedAt = referenceDate(year: 2026, month: 5, day: 30)
        let deletedFirst = AnimeEntry(name: "Rollback Delete 1", type: .movie, tmdbID: 300_201)
        let deletedSecond = AnimeEntry(name: "Rollback Delete 2", type: .movie, tmdbID: 300_203)

        try persistQueue(
            .init(entries: [
                .delete(.init(tombstone: .init(entry: deletedFirst, deletedAt: deletedAt))),
                .delete(.init(tombstone: .init(entry: deletedSecond, deletedAt: deletedAt))),
                .upsert(retainedUpsert)
            ]),
            to: queueURL
        )

        let dataProvider = DataProvider(inMemory: true)
        var writeCount = 0
        let dirtyQueueStore = LibraryEntrySyncDirtyQueueStore(url: queueURL) { queue in
            writeCount += 1
            if writeCount > 1 {
                throw QueueWriteTestError.unexpectedAdditionalWrite
            }
            try persistQueue(queue, to: queueURL)
        }
        let recorder = LibrarySyncChangeRecorder(
            dataProvider: dataProvider,
            dirtyQueueStore: dirtyQueueStore,
            notificationCenter: .init()
        )

        try recorder.restoreDeleteRecords([
            .init(identity: deletedFirst.syncIdentity, previousEntry: .upsert(restoredUpsert)),
            .init(identity: deletedSecond.syncIdentity, previousEntry: nil)
        ])

        #expect(writeCount == 1)

        let queue = dirtyQueueStore.load()
        #expect(queue.entries.count == 2)
        #expect(queue.entry(for: restoredUpsert.identity) == .upsert(restoredUpsert))
        #expect(queue.entry(for: retainedUpsert.identity) == .upsert(retainedUpsert))
        #expect(queue.entry(for: deletedSecond.syncIdentity) == nil)
    }
}


fileprivate enum QueueWriteTestError: Error {
    case injectedWriteFailure
    case unexpectedAdditionalWrite
}

fileprivate func makeTemporaryQueueURL(name: String) -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AniShelfTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    return directoryURL.appendingPathComponent("queue.json")
}

fileprivate func persistQueue(_ queue: LibraryEntrySyncDirtyQueue, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(queue)
    try data.write(to: url, options: [.atomic])
}
