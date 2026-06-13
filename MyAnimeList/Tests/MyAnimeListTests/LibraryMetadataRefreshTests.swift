//
//  LibraryMetadataRefreshTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import SwiftData
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibraryMetadataRefreshTests {
    @Test @MainActor func testLibraryImageCacheBuildsCorePrefetchTargets() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://example.com/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))

        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterURL: posterURL,
                backdropURL: backdropURL,
                logoImageURL: logoURL
            )
        )

        #expect(
            targets
                == Set([
                    .init(url: posterURL, targetSize: CGSize(width: 240, height: 360)),
                    .init(url: posterURL, targetSize: CGSize(width: 360, height: 540)),
                    .init(url: posterURL, targetSize: CGSize(width: 1_000, height: 1_500)),
                    .init(url: backdropURL, targetSize: CGSize(width: 1_200, height: 675)),
                    .init(url: logoURL, targetSize: CGSize(width: 500, height: 500))
                ])
        )
    }

    @Test @MainActor func testLibraryImageCacheBuildsURLLevelPrefetchWorkItems() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))

        let targets = [
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 240, height: 360)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 360, height: 540)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 240, height: 360)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: heroURL,
                targetSize: CGSize(width: 1_200, height: 675)
            )
        ]

        let workItems = LibraryImageCacheService.imagePrefetchWorkItems(from: targets)
            .sorted { $0.url.absoluteString < $1.url.absoluteString }

        #expect(workItems.count == 2)
        #expect(
            workItems
                == [
                    .init(
                        url: heroURL,
                        targetSizes: [CGSize(width: 1_200, height: 675)]
                    ),
                    .init(
                        url: posterURL,
                        targetSizes: [
                            CGSize(width: 240, height: 360),
                            CGSize(width: 360, height: 540)
                        ]
                    )
                ]
        )
    }

    @Test @MainActor func testLibraryImageCacheCollectsRelatedDetailURLs() throws {
        let posterURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/logo.png"))
        let characterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/character.jpg"))
        let staffURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/staff.jpg"))
        let seasonURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/season.jpg"))
        let episodeURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/episode.jpg"))

        let entry = AnimeEntry(
            name: "Cache Test",
            type: .series,
            posterURL: posterURL,
            backdropURL: backdropURL,
            tmdbID: 4
        )
        entry.detail = AnimeEntryDetail(
            language: "en",
            title: "Cache Test",
            logoImageURL: logoURL,
            characters: [
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Character",
                    actorName: "Actor",
                    profileURL: characterURL
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Director",
                    role: "Director",
                    profileURL: staffURL
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 2,
                    seasonNumber: 1,
                    title: "Season",
                    posterURL: seasonURL
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 3,
                    episodeNumber: 1,
                    title: "Episode",
                    imageURL: episodeURL
                )
            ]
        )

        let urls = LibraryImageCacheService.relatedImageURLs(for: entry)

        #expect(
            urls
                == Set([
                    posterURL,
                    backdropURL,
                    logoURL,
                    characterURL,
                    staffURL,
                    seasonURL,
                    episodeURL
                ])
        )
    }

    @Test @MainActor func testLibrarySearchServiceUsesCurrentLibraryStoreEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "First Match",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 500_001,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        let service = LibrarySearchService(
            entriesProvider: { store.library }
        )

        service.updateResults(query: "first")
        #expect(service.results.map(\.tmdbID) == [500_001])

        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "Second Match",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 500_002,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        service.updateResults(query: "second")
        #expect(service.results.map(\.tmdbID) == [500_002])
    }

    @Test @MainActor func testRefreshInfosIncludesSharedHiddenParentEntryOnce() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let parent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        parent.onDisplay = false

        let firstSeason = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209_867),
            tmdbID: 400_234
        )
        firstSeason.parentSeriesEntry = parent

        let secondSeason = AnimeEntry(
            name: "Season 2",
            type: .season(seasonNumber: 2, parentSeriesID: 209_867),
            tmdbID: 400_235
        )
        secondSeason.parentSeriesEntry = parent

        try store.repository.newEntry(parent)
        try store.repository.newEntry(firstSeason)
        try store.repository.newEntry(secondSeason)
        try store.refreshLibrary()

        #expect(store.library.count == 2)

        let capturedEntries = try LibraryProfileSettingsActions.getRefreshEntries(for: store)

        #expect(capturedEntries.count == 3)
        #expect(Set(capturedEntries.map(\.id)).count == 3)
        #expect(capturedEntries.filter { !$0.onDisplay && $0.tmdbID == 209_867 }.count == 1)
    }

    @Test @MainActor func testMetadataRefreshSaveDoesNotEnqueueDirtyWork() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.updateDisplayState(false, at: referenceDate(year: 2026, month: 6, day: 5))
        store.repository.insert(hiddenParent)

        try store.saveMetadataRefreshWithoutSyncRecording()

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)

        hiddenParent.name = "Frieren: Beyond Journey's End"
        try store.saveMetadataRefreshWithoutSyncRecording()

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func testBackgroundMetadataRefreshWriterRepairsParentLinksWithoutSyncDirtyWork()
        async throws
    {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let oldParent = AnimeEntry(
            name: "Old Parent",
            type: .series,
            tmdbID: 100
        )
        oldParent.setDisplayState(false)
        let child = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 100),
            tmdbID: 200
        )
        child.parentSeriesEntry = oldParent

        try store.repository.newEntry(oldParent)
        try store.repository.newEntry(child)
        store.rebuildSyncChangeTracking()
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])

        let modelContainer = store.dataProvider.sharedModelContainer
        let writer = await Task.detached(priority: .utility) {
            LibraryMetadataRefreshWriter(modelContainer: modelContainer)
        }.value
        try await writer.apply(
            updates: [
                .init(
                    entryID: child.id,
                    info: EntryMetadata(
                        name: "Season 1 Refreshed",
                        nameTranslations: [:],
                        overview: nil,
                        overviewTranslations: [:],
                        posterURL: nil,
                        backdropURL: nil,
                        logoURL: nil,
                        tmdbID: 200,
                        onAirDate: nil,
                        linkToDetails: nil,
                        type: .season(seasonNumber: 1, parentSeriesID: 300)
                    ),
                    detail: AnimeEntryDetailDTO(
                        language: "en-US",
                        title: "Season 1 Refreshed"
                    ),
                    preservingCustomPoster: false
                )
            ],
            parentUpdates: [
                .init(
                    childEntryID: child.id,
                    parentSeriesID: 300,
                    parentInfo: EntryMetadata(
                        name: "New Parent",
                        nameTranslations: [:],
                        overview: nil,
                        overviewTranslations: [:],
                        posterURL: nil,
                        backdropURL: nil,
                        logoURL: nil,
                        tmdbID: 300,
                        onAirDate: nil,
                        linkToDetails: nil,
                        type: .series
                    ),
                    parentDetail: AnimeEntryDetailDTO(
                        language: "en-US",
                        title: "New Parent"
                    )
                )
            ]
        )
        store.rebuildSyncChangeTracking()
        try store.refreshLibrary()

        let refreshedChild = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 200 }
            ).first
        )
        let insertedParent = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 300 }
            ).first
        )

        #expect(refreshedChild.name == "Season 1 Refreshed")
        #expect(refreshedChild.parentSeriesEntry?.tmdbID == 300)
        #expect(insertedParent.onDisplay == false)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func testHydrateHiddenHelperParentAppliesDefaultsAndDetail() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.defaultNewEntryWatchStatus = .watching

        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.onDisplay = false
        try store.repository.newEntry(hiddenParent)

        try store.hydrateExistingEntry(
            hiddenParent,
            from: EntryMetadata(
                name: "Frieren: Beyond Journey's End",
                nameTranslations: [:],
                overview: "Elf mage travels onward.",
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 209_867,
                onAirDate: nil,
                linkToDetails: nil,
                type: .series
            ),
            detail: AnimeEntryDetailDTO(
                language: "en-US",
                title: "Frieren: Beyond Journey's End",
                runtimeMinutes: 24,
                episodeCount: 28,
                seasonCount: 1
            )
        )

        #expect(hiddenParent.onDisplay)
        #expect(hiddenParent.watchStatus == .watching)
        #expect(hiddenParent.dateStarted == nil)
        #expect(hiddenParent.detail?.runtimeMinutes == 24)
        #expect(hiddenParent.detail?.episodeCount == 28)
        #expect(hiddenParent.name == "Frieren: Beyond Journey's End")

        try store.refreshLibrary()
        #expect(store.library.map(\.tmdbID) == [209_867])
    }
}
