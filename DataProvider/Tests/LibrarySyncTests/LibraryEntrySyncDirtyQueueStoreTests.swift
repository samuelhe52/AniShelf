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
