//
//  LibrarySortingAndDeletionTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibrarySortingAndDeletionTests {
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
            var scrolledID: Int?

            #expect(store.deleteEntry(second) { scrolledID = $0 })
            #expect(scrolledID == first.tmdbID)
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: Int?

            #expect(store.deleteEntry(first) { scrolledID = $0 })
            #expect(scrolledID == second.tmdbID)
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: Int?

            #expect(store.deleteEntry(third) { scrolledID = $0 })
            #expect(scrolledID == second.tmdbID)
        }

        do {
            let solo = makeEntry(name: "Solo", tmdbID: 10, day: 10)
            let store = try makeStore(with: [solo])
            var scrolledID: Int? = solo.tmdbID

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
}
