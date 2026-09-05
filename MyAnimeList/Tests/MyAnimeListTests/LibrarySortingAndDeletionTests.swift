//
//  LibrarySortingAndDeletionTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

struct LibrarySortingAndDeletionTests {
    @Test @MainActor func testRefreshLibraryCanonicalizesVisibleDuplicateIdentities() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let olderEntry = AnimeEntry(
            name: "Duplicate Movie",
            type: .movie,
            tmdbID: 500_001,
            dateSaved: referenceDate(year: 2026, month: 1, day: 1)
        )
        let newerEntry = AnimeEntry(
            name: "Duplicate Movie",
            type: .movie,
            tmdbID: 500_001,
            dateSaved: referenceDate(year: 2026, month: 1, day: 2)
        )

        try store.repository.newEntry(olderEntry)
        try store.repository.newEntry(newerEntry)
        try store.refreshLibrary()

        #expect(store.requiresDuplicateRepair)
        #expect(store.library.count == 1)
        #expect(store.library.first === newerEntry)
        #expect(store.libraryDisplayItems.map(\.id) == [newerEntry.libraryIdentity])
        #expect(store.duplicateEntryGroups.count == 1)
        #expect(store.duplicateEntryGroups.first?.entries.count == 2)
        #expect(store.duplicateEntryGroups.first?.recommendedEntry === newerEntry)
        #expect(store.libraryCloudSyncPolicyBlockReason() == .duplicateRepairRequired)
    }

    @Test @MainActor func testDuplicateRepairKeepsSelectedEntryWithoutQueuingTombstone()
        async throws
    {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }

        let store = LibraryStore(
            dataProvider: DataProvider(inMemory: true),
            preferences: LibraryPreferences(defaults: defaults)
        )
        store.updateLibraryCloudSyncStatus { status in
            status.isEnabled = true
            status.bootstrapState = .completed
        }

        let keeper = AnimeEntry(
            name: "Series to Keep",
            type: .series,
            tmdbID: 500_002,
            dateSaved: referenceDate(year: 2026, month: 1, day: 1)
        )
        let discarded = AnimeEntry(
            name: "Series to Remove",
            type: .series,
            tmdbID: 500_002,
            dateSaved: referenceDate(year: 2026, month: 1, day: 2)
        )
        let childSeason = AnimeEntry(
            name: "Child Season",
            type: .season(seasonNumber: 1, parentSeriesID: 500_002),
            tmdbID: 500_003
        )
        childSeason.parentSeriesEntry = discarded

        try store.repository.newEntry(keeper)
        try store.repository.newEntry(discarded)
        try store.repository.newEntry(childSeason)
        try store.refreshLibrary()

        let identity = keeper.libraryIdentity
        try store.syncChangeRecorder.dirtyQueueStore.setPendingDelete(
            .init(tombstone: .init(entry: discarded))
        )

        try await store.resolveDuplicateEntryGroup(identity, keeping: keeper)

        let storedEntries = try store.dataProvider.getAllModels(ofType: AnimeEntry.self)
        #expect(storedEntries.filter { $0.libraryIdentity == identity }.count == 1)
        #expect(storedEntries.contains { $0 === keeper })
        #expect(childSeason.parentSeriesEntry === keeper)
        #expect(!store.requiresDuplicateRepair)
        #expect(store.library.contains { $0 === keeper })

        let queuedEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries
        let repairedIdentityWork = queuedEntries.filter { $0.identity == identity }
        #expect(repairedIdentityWork.count == 1)
        #expect(
            repairedIdentityWork.allSatisfy {
                if case .upsert = $0 { return true }
                return false
            }
        )
    }

    @Test @MainActor func testBatchDeletionRefreshesOnceAndKeepsUnselectedEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entries = (1...3).map { AnimeEntry(name: "Entry \($0)", type: .movie, tmdbID: 510_000 + $0) }
        for entry in entries {
            try store.repository.newEntry(entry)
        }
        let deletedIDs = Set(entries.prefix(2).map(\.libraryIdentity))
        let revision = store.libraryRevision

        #expect(store.deleteEntries(Array(entries.prefix(2))))

        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.map(\.libraryIdentity) == [entries[2].libraryIdentity])
        let tombstoneIDs = Set(
            store.syncChangeRecorder.dirtyQueueStore.load().entries.compactMap { entry in
                if case .delete(let pending) = entry { return pending.identity }
                return nil
            })
        #expect(tombstoneIDs == deletedIDs)
    }

    @Test @MainActor func testBatchDeletionRollsBackModelsAndQueueOnSaveFailure() throws {
        struct SaveFailure: Error {}
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entries = (1...2).map { AnimeEntry(name: "Entry \($0)", type: .movie, tmdbID: 520_000 + $0) }
        for entry in entries {
            try store.repository.newEntry(entry)
        }
        let initialQueue = store.syncChangeRecorder.dirtyQueueStore.load()
        var saves = 0
        let repository = LibraryRepository(
            dataProvider: store.dataProvider,
            syncChangeRecorder: store.syncChangeRecorder,
            transactionSaver: { _ in
                saves += 1
                throw SaveFailure()
            }
        )

        #expect(throws: SaveFailure.self) { try repository.deleteEntries(entries) }

        #expect(saves == 1)
        #expect(try repository.visibleLibraryEntries().count == 2)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load() == initialQueue)
    }

    @Test @MainActor func testDeletionScrollTargetFallbacks() throws {
        let sortStrategyKey = String.librarySortStrategy
        let sortReversedKey = String.librarySortReversed
        let defaults = UserDefaults.standard
        let originalSortStrategy = defaults.object(forKey: sortStrategyKey)
        let originalSortReversed = defaults.object(forKey: sortReversedKey)

        defer {
            if let originalSortStrategy {
                defaults.set(originalSortStrategy, forKey: sortStrategyKey)
            } else {
                defaults.removeObject(forKey: sortStrategyKey)
            }

            if let originalSortReversed {
                defaults.set(originalSortReversed, forKey: sortReversedKey)
            } else {
                defaults.removeObject(forKey: sortReversedKey)
            }
        }

        func makeEntry(name: String, tmdbID: Int, day: Int) -> AnimeEntry {
            AnimeEntry(
                name: name,
                type: .movie,
                tmdbID: tmdbID,
                dateSaved: referenceDate(year: 2026, month: 1, day: day)
            )
        }

        func makeStore(with entries: [AnimeEntry]) throws -> LibraryStore {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            for entry in entries {
                try store.repository.newEntry(entry)
            }
            try store.refreshLibrary()
            return store
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: LibraryEntryIdentity?

            #expect(store.deleteEntry(second) { scrolledID = $0 })
            #expect(scrolledID == first.libraryIdentity)
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: LibraryEntryIdentity?

            #expect(store.deleteEntry(first) { scrolledID = $0 })
            #expect(scrolledID == second.libraryIdentity)
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: LibraryEntryIdentity?

            #expect(store.deleteEntry(third) { scrolledID = $0 })
            #expect(scrolledID == second.libraryIdentity)
        }

        do {
            let solo = makeEntry(name: "Solo", tmdbID: 10, day: 10)
            let store = try makeStore(with: [solo])
            var scrolledID: LibraryEntryIdentity? = solo.libraryIdentity

            #expect(store.deleteEntry(solo) { scrolledID = $0 })
            #expect(scrolledID == nil)
        }
    }

    @Test @MainActor func testWatchStatusGroupingUsesCurrentSortWithinBuckets() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .watchStatus
            store.sortStrategy = .dateSaved
            store.sortReversed = false
            store.hideDroppedByDefault = false

            let entries = [
                makeLibraryEntry(name: "Watched Early", tmdbID: 31, watchStatus: .watched, daySaved: 1),
                makeLibraryEntry(name: "Watching Early", tmdbID: 11, watchStatus: .watching, daySaved: 2),
                makeLibraryEntry(name: "Dropped", tmdbID: 41, watchStatus: .dropped, daySaved: 3),
                makeLibraryEntry(name: "Watching Late", tmdbID: 12, watchStatus: .watching, daySaved: 4),
                makeLibraryEntry(name: "Planned", tmdbID: 21, watchStatus: .planToWatch, daySaved: 5),
                makeLibraryEntry(name: "Watched Late", tmdbID: 32, watchStatus: .watched, daySaved: 6)
            ]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [11, 12, 21, 31, 32, 41])
        }
    }

    @Test @MainActor func testScoreGroupingPlacesUnscoredEntriesLast() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .score
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            let entries = [
                makeLibraryEntry(name: "Unscored", tmdbID: 61, daySaved: 1),
                makeLibraryEntry(name: "Score Five Early", tmdbID: 51, daySaved: 2, score: 5),
                makeLibraryEntry(name: "Score Three", tmdbID: 31, daySaved: 3, score: 3),
                makeLibraryEntry(name: "Score Two", tmdbID: 21, daySaved: 4, score: 2),
                makeLibraryEntry(name: "Score Five Late", tmdbID: 52, daySaved: 5, score: 5),
                makeLibraryEntry(name: "Score Four", tmdbID: 41, daySaved: 6, score: 4),
                makeLibraryEntry(name: "Score One", tmdbID: 11, daySaved: 7, score: 1)
            ]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [51, 52, 41, 31, 21, 11, 61])
        }
    }

    @Test @MainActor func testFavoriteGroupingKeepsBucketOrderWhenReversed() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .favorite
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            let favoriteEarly = makeLibraryEntry(
                name: "Favorite Early",
                tmdbID: 71,
                daySaved: 1,
                favorite: true
            )
            let otherEarly = makeLibraryEntry(name: "Other Early", tmdbID: 81, daySaved: 2)
            let favoriteLate = makeLibraryEntry(
                name: "Favorite Late",
                tmdbID: 72,
                daySaved: 3,
                favorite: true
            )
            let otherLate = makeLibraryEntry(name: "Other Late", tmdbID: 82, daySaved: 4)
            let entries = [favoriteEarly, otherEarly, favoriteLate, otherLate]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [71, 72, 81, 82])

            store.sortReversed = true
            #expect(store.filterAndSort(entries).map(\.tmdbID) == [72, 71, 82, 81])
        }
    }

    @Test @MainActor func testNoGroupingMatchesCurrentFlatSortBehavior() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .none
            store.sortStrategy = .dateSaved
            store.sortReversed = true

            let entries = [
                makeLibraryEntry(name: "Favorite", tmdbID: 91, daySaved: 1, favorite: true),
                makeLibraryEntry(name: "Watched", tmdbID: 92, watchStatus: .watched, daySaved: 4),
                makeLibraryEntry(name: "Watching", tmdbID: 93, watchStatus: .watching, daySaved: 2),
                makeLibraryEntry(name: "Scored", tmdbID: 94, daySaved: 3, score: 5)
            ]

            let expected = Array(entries.sorted(by: LibraryStore.AnimeSortStrategy.dateSaved.compare).reversed())
            #expect(store.filterAndSort(entries).map(\.tmdbID) == expected.map(\.tmdbID))
        }
    }

    @Test @MainActor func testAlphabeticalSortUsesEntryNames() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .none
            store.sortStrategy = .alphabetical
            store.sortReversed = false

            let entries = [
                makeLibraryEntry(name: "Naruto", tmdbID: 101, daySaved: 4),
                makeLibraryEntry(name: "Bleach", tmdbID: 102, daySaved: 3),
                makeLibraryEntry(name: "Attack on Titan", tmdbID: 103, daySaved: 2),
                makeLibraryEntry(name: "Bleach", tmdbID: 104, daySaved: 1)
            ]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [103, 104, 102, 101])
        }
    }

    @Test @MainActor func testLibraryOnDisplayRespectsFiltersAndHiddenDroppedState() throws {
        let hideDroppedKey = String.libraryHideDroppedByDefault
        let defaults = UserDefaults.standard
        let originalHideDropped = defaults.object(forKey: hideDroppedKey)

        defer {
            if let originalHideDropped {
                defaults.set(originalHideDropped, forKey: hideDroppedKey)
            } else {
                defaults.removeObject(forKey: hideDroppedKey)
            }
        }

        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let favorite = makeLibraryEntry(
            name: "Favorite",
            tmdbID: 201,
            daySaved: 1,
            favorite: true
        )
        let plain = makeLibraryEntry(name: "Plain", tmdbID: 202, daySaved: 2)
        let dropped = makeLibraryEntry(
            name: "Dropped",
            tmdbID: 203,
            watchStatus: .dropped,
            daySaved: 3
        )

        try store.repository.newEntry(favorite)
        try store.repository.newEntry(plain)
        try store.repository.newEntry(dropped)
        try store.refreshLibrary()

        store.filters = [.favorited]
        #expect(store.libraryOnDisplay.contains { $0.tmdbID == favorite.tmdbID })
        #expect(!store.libraryOnDisplay.contains { $0.tmdbID == plain.tmdbID })
        #expect(!store.libraryOnDisplay.contains { $0.tmdbID == dropped.tmdbID })

        store.filters = []
        store.hideDroppedByDefault = true
        #expect(!store.libraryOnDisplay.contains { $0.tmdbID == dropped.tmdbID })

        store.hideDroppedByDefault = false
        #expect(store.libraryOnDisplay.contains { $0.tmdbID == dropped.tmdbID })
    }
}
