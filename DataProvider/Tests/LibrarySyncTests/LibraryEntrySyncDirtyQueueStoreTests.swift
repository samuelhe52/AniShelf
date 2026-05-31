//
//  LibraryEntrySyncDirtyQueueStoreTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync

struct LibraryEntrySyncDirtyQueueStoreTests {
    @Test func queueStorePersistsCoalescesAndReplacesEntriesAtomically() throws {
        let url = makeTemporaryQueueURL()
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = LibraryEntrySyncDirtyQueueStore(url: url)
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 42)
        let firstUpsert = LibraryEntrySyncPendingUpsert(
            identity: identity,
            dirtyAt: referenceDate(year: 2026, month: 5, day: 1)
        )
        let newerUpsert = LibraryEntrySyncPendingUpsert(
            identity: identity,
            dirtyAt: referenceDate(year: 2026, month: 5, day: 3)
        )
        let tombstoneEntry = AnimeEntry(
            name: "Queue Delete",
            type: .series,
            tmdbID: 42
        )
        let delete = LibraryEntrySyncPendingDelete(
            tombstone: .init(entry: tombstoneEntry, deletedAt: referenceDate(year: 2026, month: 5, day: 4))
        )

        try store.setPendingUpsert(firstUpsert)
        let firstBytes = try Data(contentsOf: url)
        let firstQueue = store.load()
        #expect(firstQueue.entries.count == 1)
        #expect(firstQueue.entry(for: identity) == .upsert(firstUpsert))

        try store.setPendingUpsert(newerUpsert)
        let secondBytes = try Data(contentsOf: url)
        let secondQueue = store.load()
        #expect(secondQueue.entries.count == 1)
        #expect(secondQueue.entry(for: identity) == .upsert(newerUpsert))
        #expect(firstBytes != secondBytes)

        try store.setPendingDelete(delete)
        let finalQueue = store.load()
        #expect(finalQueue.entries.count == 1)
        #expect(finalQueue.entry(for: identity) == .delete(delete))
    }

    @Test func malformedQueueFileFailsSafe() throws {
        let url = makeTemporaryQueueURL()
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: url, options: [.atomic])

        let store = LibraryEntrySyncDirtyQueueStore(url: url)
        let queue = store.load()

        #expect(queue.entries.isEmpty)
    }

    @Test func queueStoreResetsMismatchedSchemaVersion() throws {
        let url = makeTemporaryQueueURL()
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"schemaVersion":1,"entries":[]}"#.utf8).write(to: url, options: [.atomic])

        let store = LibraryEntrySyncDirtyQueueStore(url: url)
        let queue = store.load()

        #expect(queue.schemaVersion == LibraryEntrySyncDirtyQueue.currentSchemaVersion)
        #expect(queue.entries.isEmpty)
    }

    @Test func tombstonePersistsOnlyLeanDeleteFields() throws {
        let entry = AnimeEntry(
            name: "Lean Delete",
            type: .season(seasonNumber: 2, parentSeriesID: 100),
            tmdbID: 200
        )
        entry.notes = "Should not be copied into the tombstone"
        let deletedAt = referenceDate(year: 2026, month: 5, day: 5)

        let tombstone = LibraryEntrySyncTombstone(entry: entry, deletedAt: deletedAt)

        #expect(tombstone.identity == entry.syncIdentity)
        #expect(tombstone.tmdbID == 200)
        #expect(tombstone.parentSeriesID == 100)
        #expect(tombstone.seasonNumber == 2)
        #expect(tombstone.entryType == .season(seasonNumber: 2, parentSeriesID: 100))
        #expect(tombstone.deletedAt == deletedAt)
    }

    @Test func queueStoreHandlesConcurrentWritesWithoutLosingEntries() async throws {
        let url = makeTemporaryQueueURL()
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = LibraryEntrySyncDirtyQueueStore(url: url)
        let identityCount = 32

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<identityCount {
                group.addTask {
                    let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: index)
                    let dirtyAt = referenceDate(year: 2026, month: 5, day: (index % 28) + 1)
                    try store.setPendingUpsert(
                        .init(identity: identity, dirtyAt: dirtyAt)
                    )
                }
            }
            try await group.waitForAll()
        }

        let queue = store.load()
        #expect(queue.entries.count == identityCount)
        for index in 0..<identityCount {
            let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: index)
            #expect(queue.entry(for: identity) != nil)
        }
    }

    private func makeTemporaryQueueURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelf.LibrarySyncTests.\(UUID().uuidString).json")
    }
}

fileprivate func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}
