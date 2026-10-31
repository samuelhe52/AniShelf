//
//  LibrarySaveInvalidationTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/31.
//

import DataProvider
import Foundation
import SwiftData
import Testing

@testable import MyAnimeList

@MainActor
struct LibrarySaveInvalidationTests {
    @Test func childOnlySaveKeepsMembershipAndUnrelatedWindowProjections() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Movie", type: .movie, tmdbID: 901,
            detail: AnimeEntryDetail(
                language: "en-US", title: "Movie", runtimeMinutes: 90,
                characters: [AnimeEntryCharacter(id: 1, characterName: "Character", actorName: "Actor")],
                staff: [AnimeEntryStaff(id: 2, name: "Staff", role: "Director")]
            )
        )
        try store.repository.newEntry(entry)
        let scopes = [LibraryBrowseScope(store: store), LibraryBrowseScope(store: store)]
        for scope in scopes { _ = scope.displayItems }
        let counts = scopes.map(\.displayComputeCount)
        let revision = store.libraryRevision
        let detail = try #require(entry.detail)
        detail.overview = "Changed inspector-only overview"
        detail.characters.first?.actorName = "Changed actor"
        detail.staff.first?.role = "Writer"
        try store.repository.save()

        #expect(store.libraryRevision == revision)
        #expect(store.library.first === entry)
        for (index, scope) in scopes.enumerated() {
            _ = scope.displayItems
            #expect(scope.displayComputeCount == counts[index])
        }
    }

    @Test func rowVisibleDetailAndProgressChangesUpdateWithoutMembershipRefresh() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let movie = AnimeEntry(
            name: "Movie", type: .movie, tmdbID: 902,
            detail: AnimeEntryDetail(language: "en-US", title: "Movie", runtimeMinutes: 90)
        )
        let series = AnimeEntry(
            name: "Series", type: .series, tmdbID: 903,
            detail: AnimeEntryDetail(
                language: "en-US", title: "Series", episodeCount: 12, seasonCount: 1,
                seasons: [AnimeEntrySeasonSummary(id: 1, seasonNumber: 1, title: "Season", episodeCount: 12)]
            )
        )
        series.watchStatus = .watching
        series.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 1, updatedAt: .now)
        try store.repository.newEntry(movie)
        try store.repository.newEntry(series)
        let scope = LibraryBrowseScope(store: store)
        let before = Dictionary(uniqueKeysWithValues: scope.displayItems.map { ($0.id, $0.snapshot) })
        let revision = store.libraryRevision
        movie.detail?.runtimeMinutes = 110
        series.incrementEpisodeProgress(seasonNumber: 1, by: 1)
        try store.repository.save()
        let after = Dictionary(uniqueKeysWithValues: scope.displayItems.map { ($0.id, $0.snapshot) })

        #expect(store.libraryRevision == revision)
        #expect(before[movie.libraryIdentity]?.primaryMetadata != after[movie.libraryIdentity]?.primaryMetadata)
        #expect(
            before[series.libraryIdentity]?.episodeProgressLabel != after[series.libraryIdentity]?.episodeProgressLabel)
    }

    @Test func entryMembershipChangesRefreshButOrdinaryEntryEditsDoNot() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(name: "Movie", type: .movie, tmdbID: 904)
        var revision = store.libraryRevision
        try store.repository.newEntry(entry)
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.first === entry)

        revision = store.libraryRevision
        entry.name = "Renamed"
        entry.favorite = true
        try store.repository.save()
        #expect(store.libraryRevision == revision)

        entry.updateDisplayState(false)
        try store.repository.save()
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.isEmpty)
        revision = store.libraryRevision
        entry.updateDisplayState(true)
        try store.repository.save()
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.first === entry)

        revision = store.libraryRevision
        entry.tmdbID = 905
        try store.repository.save()
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.first?.libraryIdentity == entry.libraryIdentity)
        revision = store.libraryRevision
        try store.repository.deleteEntry(entry)
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.isEmpty)
    }

    @Test(arguments: ["detail", "name", "date", "parent"])
    func duplicateWinnerChangesRefreshMembership(change: String) throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let date = Date(timeIntervalSince1970: 1_000)
        let first = AnimeEntry(name: "A", type: .series, tmdbID: 906, dateSaved: date)
        let second = AnimeEntry(name: "B", type: .series, tmdbID: 906, dateSaved: date)
        let child = AnimeEntry(name: "Season", type: .season(seasonNumber: 1, parentSeriesID: 906), tmdbID: 907)
        child.onDisplay = false
        for entry in [first, second, child] { store.repository.insert(entry) }
        try store.repository.save()
        #expect(store.library.first === first)
        let revision = store.libraryRevision

        switch change {
        case "detail": second.detail = AnimeEntryDetail(language: "en-US", title: "B")
        case "name": second.name = "0"
        case "date": second.dateSaved = date.addingTimeInterval(1)
        default: child.parentSeriesEntry = second
        }
        try store.repository.save()
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.first === second)
    }

    @Test func backgroundMembershipSavesRefreshAndOtherContainersAreIgnored() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(name: "Movie", type: .movie, tmdbID: 908)
        try store.repository.newEntry(entry)
        let id = entry.id
        let container = store.dataProvider.sharedModelContainer
        for visible in [false, true] {
            let revision = store.libraryRevision
            try await store.performWithDeferredLibrarySaveRefresh {
                try await Task.detached {
                    let context = ModelContext(container)
                    let model = try #require(context.model(for: id) as? AnimeEntry)
                    model.onDisplay = visible
                    try context.save()
                }.value
            }
            #expect(store.libraryRevision == revision + 1)
            #expect(store.library.isEmpty == !visible)
        }

        let revision = store.libraryRevision
        let unrelated = DataProvider(inMemory: true)
        try unrelated.dataHandler.newEntry(AnimeEntry(name: "Other store", type: .movie, tmdbID: 909))
        #expect(store.libraryRevision == revision)
        #expect(store.library.map(\.tmdbID) == [908])
    }

    @Test func backgroundDetailSaveUpdatesRowsWithoutMembershipRefresh() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Movie", type: .movie, tmdbID: 910,
            detail: AnimeEntryDetail(language: "en-US", title: "Movie", runtimeMinutes: 90)
        )
        try store.repository.newEntry(entry)
        let scope = LibraryBrowseScope(store: store)
        let before = try #require(scope.displayItems.first?.snapshot.primaryMetadata)
        let revision = store.libraryRevision
        let id = entry.id
        let container = store.dataProvider.sharedModelContainer
        try await store.performWithDeferredLibrarySaveRefresh {
            try await Task.detached {
                let context = ModelContext(container)
                let model = try #require(context.model(for: id) as? AnimeEntry)
                model.detail?.runtimeMinutes = 110
                try context.save()
            }.value
        }
        #expect(store.libraryRevision == revision)
        // The UI's models receive the merged values without observation, so the row
        // snapshot must be rebuilt explicitly, as after Refresh All.
        #expect(entry.detail?.runtimeMinutes == 110)
        #expect(scope.displayItems.first?.snapshot.primaryMetadata != before)
    }

    @Test func explicitImportBoundaryRefreshesReplayChanges() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Imported Movie", type: .movie, tmdbID: 912,
            detail: AnimeEntryDetail(language: "en-US", title: "Movie", runtimeMinutes: 90)
        )
        try store.repository.newEntry(entry)
        let scope = LibraryBrowseScope(store: store)
        let before = try #require(scope.displayItems.first?.snapshot.primaryMetadata)
        let revision = store.libraryRevision
        // RemoteApply writes through the UI repository, then explicitly refreshes.
        entry.detail?.runtimeMinutes = 110
        try store.repository.save()
        #expect(store.libraryRevision == revision)
        try #require(store.syncCoordinator).refreshLibraryAfterImport(in: store)
        #expect(store.libraryRevision == revision + 1)
        #expect(scope.displayItems.first?.snapshot.primaryMetadata != before)
    }

    @Test func firstDetailResponseDoesNotRefreshSingletonMembership() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(name: "Movie", type: .movie, tmdbID: 911)
        try store.repository.newEntry(entry)
        let scope = LibraryBrowseScope(store: store)
        let before = try #require(scope.displayItems.first?.snapshot.primaryMetadata)
        let revision = store.libraryRevision
        entry.replaceDetail(from: AnimeEntryDetailDTO(language: "en-US", title: "New Detail", runtimeMinutes: 110))
        try store.repository.save()
        #expect(store.libraryRevision == revision)
        #expect(scope.displayItems.first?.snapshot.primaryMetadata != before)
    }

    @Test func savesAfterReplacingTheContainerStillRefreshMembership() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        // Restoring a backup replaces the container behind the same provider.
        store.dataProvider.reloadDataStore()
        try store.refreshLibrary()
        let revision = store.libraryRevision
        let entry = AnimeEntry(name: "After Restore", type: .movie, tmdbID: 913)
        try store.repository.newEntry(entry)
        #expect(store.libraryRevision == revision + 1)
        #expect(store.library.first === entry)
    }
}
