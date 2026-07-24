//
//  LibraryMetadataRefreshTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibraryMetadataRefreshTests {
    @Test @MainActor func testDetailComparatorTreatsReorderedEquivalentPayloadsAsEqual() throws {
        let persisted = AnimeEntryDetail(
            language: "en-US",
            title: "Frieren",
            subtitle: "Season 1",
            overview: "Elf mage travels onward.",
            status: "Ended",
            airDate: referenceDate(year: 2026, month: 6, day: 1),
            primaryLinkURL: URL(string: "https://example.com/frieren"),
            logoImagePath: "/logos/frieren.png",
            genreIDs: [16, 10765],
            voteAverage: 8.9,
            runtimeMinutes: 24,
            episodeCount: 28,
            seasonCount: 1,
            characters: [
                AnimeEntryCharacter(
                    id: 2,
                    characterName: "Fern",
                    actorName: "Kana Ichinose",
                    profilePath: "/profiles/fern.jpg",
                    displayOrder: 0
                ),
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Frieren",
                    actorName: "Atsumi Tanezaki",
                    profilePath: "/profiles/frieren.jpg",
                    displayOrder: 1
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 11,
                    name: "Tomohiro Suzuki",
                    role: "Series Composition",
                    department: "Writing",
                    profilePath: "/staff/writer.jpg",
                    jobs: [
                        AnimeEntryStaffJob(
                            creditID: "writer-main",
                            job: "Writer",
                            episodeCount: 28,
                            displayOrder: 0
                        )
                    ],
                    displayOrder: 0
                ),
                AnimeEntryStaff(
                    id: 10,
                    name: "Keiichiro Saito",
                    role: "Director",
                    department: "Directing",
                    profilePath: "/staff/director.jpg",
                    jobs: [
                        AnimeEntryStaffJob(
                            creditID: "director-secondary",
                            job: "Storyboard",
                            episodeCount: 4,
                            displayOrder: 0
                        ),
                        AnimeEntryStaffJob(
                            creditID: "director-main",
                            job: "Director",
                            episodeCount: 28,
                            displayOrder: 1
                        )
                    ],
                    displayOrder: 1
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 100,
                    seasonNumber: 1,
                    title: "Season 1",
                    posterPath: "/seasons/1.jpg",
                    episodeCount: 28
                ),
                AnimeEntrySeasonSummary(
                    id: 101,
                    seasonNumber: 0,
                    title: "Specials",
                    posterPath: "/seasons/0.jpg",
                    episodeCount: 2
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 1001,
                    episodeNumber: 2,
                    title: "A Better Start",
                    airDate: referenceDate(year: 2026, month: 6, day: 3),
                    imagePath: "/episodes/2.jpg",
                    displayOrder: 0
                ),
                AnimeEntryEpisodeSummary(
                    id: 1000,
                    episodeNumber: 1,
                    title: "The Journey's End",
                    airDate: referenceDate(year: 2026, month: 6, day: 2),
                    imagePath: "/episodes/1.jpg",
                    displayOrder: 1
                )
            ]
        )

        let fetched = AnimeEntryDetailDTO(
            language: "en-US",
            title: "Frieren",
            subtitle: "Season 1",
            overview: "Elf mage travels onward.",
            status: "Ended",
            airDate: referenceDate(year: 2026, month: 6, day: 1),
            primaryLinkURL: URL(string: "https://example.com/frieren"),
            logoImagePath: "/logos/frieren.png",
            genreIDs: [10765, 16],
            voteAverage: 8.9,
            runtimeMinutes: 24,
            episodeCount: 28,
            seasonCount: 1,
            characters: [
                AnimeEntryCharacterDTO(
                    id: 1,
                    characterName: "Frieren",
                    actorName: "Atsumi Tanezaki",
                    profilePath: "/profiles/frieren.jpg"
                ),
                AnimeEntryCharacterDTO(
                    id: 2,
                    characterName: "Fern",
                    actorName: "Kana Ichinose",
                    profilePath: "/profiles/fern.jpg"
                )
            ],
            staff: [
                AnimeEntryStaffDTO(
                    id: 10,
                    name: "Keiichiro Saito",
                    role: "Director",
                    department: "Directing",
                    profilePath: "/staff/director.jpg",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "director-main",
                            job: "Director",
                            episodeCount: 28
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "director-secondary",
                            job: "Storyboard",
                            episodeCount: 4
                        )
                    ]
                ),
                AnimeEntryStaffDTO(
                    id: 11,
                    name: "Tomohiro Suzuki",
                    role: "Series Composition",
                    department: "Writing",
                    profilePath: "/staff/writer.jpg",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "writer-main",
                            job: "Writer",
                            episodeCount: 28
                        )
                    ]
                )
            ],
            seasons: [
                AnimeEntrySeasonSummaryDTO(
                    id: 101,
                    seasonNumber: 0,
                    title: "Specials",
                    posterPath: "/seasons/0.jpg",
                    episodeCount: 2
                ),
                AnimeEntrySeasonSummaryDTO(
                    id: 100,
                    seasonNumber: 1,
                    title: "Season 1",
                    posterPath: "/seasons/1.jpg",
                    episodeCount: 28
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummaryDTO(
                    id: 1000,
                    episodeNumber: 1,
                    title: "The Journey's End",
                    airDate: referenceDate(year: 2026, month: 6, day: 2),
                    imagePath: "/episodes/1.jpg"
                ),
                AnimeEntryEpisodeSummaryDTO(
                    id: 1001,
                    episodeNumber: 2,
                    title: "A Better Start",
                    airDate: referenceDate(year: 2026, month: 6, day: 3),
                    imagePath: "/episodes/2.jpg"
                )
            ]
        )

        #expect(
            LibraryMetadataRefreshDetailComparator.matches(
                existing: persisted,
                fetched: fetched
            )
        )
    }

    @Test @MainActor func testDetailComparatorDetectsSemanticDifferences() throws {
        let persisted = AnimeEntryDetail(
            language: "en-US",
            title: "Frieren",
            runtimeMinutes: 24
        )
        let fetched = AnimeEntryDetailDTO(
            language: "en-US",
            title: "Frieren",
            runtimeMinutes: 25
        )

        #expect(
            !LibraryMetadataRefreshDetailComparator.matches(
                existing: persisted,
                fetched: fetched
            )
        )
    }

    @Test @MainActor func testLibraryImageCacheBuildsDefaultPrefetchTargetsWithoutLargeGalleryPoster()
        throws
    {
        let backdropURL = try #require(URL(string: "https://example.com/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))

        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterPath: "/poster.jpg",
                backdropURL: backdropURL,
                logoImageURL: logoURL,
                longTermGalleryPosterCachingEnabled: false
            )
        )

        let listPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg"))
        let gridPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))

        #expect(
            targets
                == Set([
                    .init(url: listPosterURL, targetSize: CGSize(width: 240, height: 360)),
                    .init(url: gridPosterURL, targetSize: CGSize(width: 360, height: 540)),
                    .init(url: backdropURL, targetSize: CGSize(width: 1_200, height: 675)),
                    .init(url: logoURL, targetSize: CGSize(width: 500, height: 500))
                ])
        )
    }

    @Test @MainActor func testLibraryImageCacheIncludesLargeGalleryPosterWhenEnabled() throws {
        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterPath: "/poster.jpg",
                backdropURL: nil,
                logoImageURL: nil,
                longTermGalleryPosterCachingEnabled: true
            )
        )

        let galleryPosterURL = try #require(
            URL(string: "https://image.tmdb.org/t/p/original/poster.jpg")
        )

        #expect(
            targets.contains(
                .init(url: galleryPosterURL, targetSize: CGSize(width: 1_000, height: 1_500))
            )
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
        let listPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg"))
        let gridPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://image.tmdb.org/t/p/w1280/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/logo.png"))
        let characterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/character.jpg"))
        let staffURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/staff.jpg"))
        let seasonURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/season.jpg"))
        let episodeURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/episode.jpg"))

        let entry = AnimeEntry(
            name: "Cache Test",
            type: .series,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            tmdbID: 4
        )
        entry.detail = AnimeEntryDetail(
            language: "en",
            title: "Cache Test",
            logoImagePath: "/logo.png",
            characters: [
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Character",
                    actorName: "Actor",
                    profilePath: "/character.jpg"
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Director",
                    role: "Director",
                    profilePath: "/staff.jpg"
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 2,
                    seasonNumber: 1,
                    title: "Season",
                    posterPath: "/season.jpg"
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 3,
                    episodeNumber: 1,
                    title: "Episode",
                    imagePath: "/episode.jpg"
                )
            ]
        )

        let urls = LibraryImageCacheService.relatedImageURLs(for: entry)

        #expect(
            urls
                == Set([
                    posterURL,
                    listPosterURL,
                    gridPosterURL,
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

    @Test @MainActor func testMetadataRefreshSaveDoesNotEnqueueDirtyWork() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.updateDisplayState(false, at: referenceDate(year: 2026, month: 6, day: 5))
        store.repository.insert(hiddenParent)

        try await store.performWithoutSyncRecording {
            try store.repository.save()
        }

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)

        hiddenParent.name = "Frieren: Beyond Journey's End"
        try await store.performWithoutSyncRecording {
            try store.repository.save()
        }

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func testDeferredLibrarySaveRefreshUpdatesVisibleLibraryAfterScope() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))

        try await store.performWithDeferredLibrarySaveRefresh {
            try store.repository.newEntry(
                AnimeEntry(
                    name: "Deferred Refresh",
                    type: .movie,
                    tmdbID: 500_100
                )
            )

            #expect(store.library.isEmpty)
        }

        #expect(store.library.map(\.tmdbID) == [500_100])
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
        try await store.performWithoutSyncRecording {
            let writer = LibraryMetadataRefreshWriter(
                modelContainer: modelContainer
            )
            let result = try await writer.apply(
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
            #expect(result.writtenCount == 1)
            #expect(result.skippedCount == 0)
        }
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

    @Test @MainActor func testBackgroundMetadataRefreshWriterSkipsEquivalentDetailWrites()
        async throws
    {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let persistedDetailDTO = AnimeEntryDetailDTO(
            language: "en-US",
            title: "Frieren",
            subtitle: "Season 1",
            overview: "Elf mage travels onward.",
            status: "Ended",
            airDate: referenceDate(year: 2026, month: 6, day: 1),
            primaryLinkURL: URL(string: "https://example.com/frieren"),
            logoImagePath: "/logos/frieren.png",
            genreIDs: [16, 10765],
            voteAverage: 8.9,
            runtimeMinutes: 24,
            episodeCount: 28,
            seasonCount: 1,
            characters: [
                AnimeEntryCharacterDTO(
                    id: 2,
                    characterName: "Fern",
                    actorName: "Kana Ichinose",
                    profilePath: "/profiles/fern.jpg"
                ),
                AnimeEntryCharacterDTO(
                    id: 1,
                    characterName: "Frieren",
                    actorName: "Atsumi Tanezaki",
                    profilePath: "/profiles/frieren.jpg"
                )
            ],
            staff: [
                AnimeEntryStaffDTO(
                    id: 11,
                    name: "Tomohiro Suzuki",
                    role: "Series Composition",
                    department: "Writing",
                    profilePath: "/staff/writer.jpg",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "writer-main",
                            job: "Writer",
                            episodeCount: 28
                        )
                    ]
                ),
                AnimeEntryStaffDTO(
                    id: 10,
                    name: "Keiichiro Saito",
                    role: "Director",
                    department: "Directing",
                    profilePath: "/staff/director.jpg",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "director-secondary",
                            job: "Storyboard",
                            episodeCount: 4
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "director-main",
                            job: "Director",
                            episodeCount: 28
                        )
                    ]
                )
            ],
            seasons: [
                AnimeEntrySeasonSummaryDTO(
                    id: 101,
                    seasonNumber: 0,
                    title: "Specials",
                    posterPath: "/seasons/0.jpg",
                    episodeCount: 2
                ),
                AnimeEntrySeasonSummaryDTO(
                    id: 100,
                    seasonNumber: 1,
                    title: "Season 1",
                    posterPath: "/seasons/1.jpg",
                    episodeCount: 28
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummaryDTO(
                    id: 1001,
                    episodeNumber: 2,
                    title: "A Better Start",
                    airDate: referenceDate(year: 2026, month: 6, day: 3),
                    imagePath: "/episodes/2.jpg"
                ),
                AnimeEntryEpisodeSummaryDTO(
                    id: 1000,
                    episodeNumber: 1,
                    title: "The Journey's End",
                    airDate: referenceDate(year: 2026, month: 6, day: 2),
                    imagePath: "/episodes/1.jpg"
                )
            ]
        )
        let entry = AnimeEntry(
            name: "Frieren",
            nameTranslations: ["en-US": "Frieren"],
            overview: "Elf mage travels onward.",
            overviewTranslations: ["en-US": "Elf mage travels onward."],
            onAirDate: referenceDate(year: 2026, month: 6, day: 1),
            type: .series,
            linkToDetails: URL(string: "https://example.com/frieren"),
            posterPath: "/posters/frieren.jpg",
            backdropPath: "/backdrops/frieren.jpg",
            tmdbID: 209_867,
            originalLanguageCode: "ja"
        )
        entry.replaceDetail(from: persistedDetailDTO)

        try store.repository.newEntry(entry)

        let originalEntry = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 209_867 }
            ).first
        )
        let originalDetail = try #require(originalEntry.detail)
        let originalCharacterID = try #require(originalDetail.characters.first?.id)
        let originalCharacterModelID = try #require(originalDetail.characters.first?.persistentModelID)
        let originalStaffModelID = try #require(originalDetail.staff.first?.persistentModelID)
        let originalSeasonModelID = try #require(originalDetail.seasons.first?.persistentModelID)
        let originalEpisodeModelID = try #require(originalDetail.episodes.first?.persistentModelID)

        let modelContainer = store.dataProvider.sharedModelContainer
        let reorderedFetchedDetailDTO = AnimeEntryDetailDTO(
            language: "en-US",
            title: "Frieren",
            subtitle: "Season 1",
            overview: "Elf mage travels onward.",
            status: "Ended",
            airDate: referenceDate(year: 2026, month: 6, day: 1),
            primaryLinkURL: URL(string: "https://example.com/frieren"),
            logoImagePath: "/logos/frieren.png",
            genreIDs: [10765, 16],
            voteAverage: 8.9,
            runtimeMinutes: 24,
            episodeCount: 28,
            seasonCount: 1,
            characters: [
                AnimeEntryCharacterDTO(
                    id: 1,
                    characterName: "Frieren",
                    actorName: "Atsumi Tanezaki",
                    profilePath: "/profiles/frieren.jpg"
                ),
                AnimeEntryCharacterDTO(
                    id: 2,
                    characterName: "Fern",
                    actorName: "Kana Ichinose",
                    profilePath: "/profiles/fern.jpg"
                )
            ],
            staff: [
                AnimeEntryStaffDTO(
                    id: 10,
                    name: "Keiichiro Saito",
                    role: "Director",
                    department: "Directing",
                    profilePath: "/staff/director.jpg",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "director-main",
                            job: "Director",
                            episodeCount: 28
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "director-secondary",
                            job: "Storyboard",
                            episodeCount: 4
                        )
                    ]
                ),
                AnimeEntryStaffDTO(
                    id: 11,
                    name: "Tomohiro Suzuki",
                    role: "Series Composition",
                    department: "Writing",
                    profilePath: "/staff/writer.jpg",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "writer-main",
                            job: "Writer",
                            episodeCount: 28
                        )
                    ]
                )
            ],
            seasons: [
                AnimeEntrySeasonSummaryDTO(
                    id: 100,
                    seasonNumber: 1,
                    title: "Season 1",
                    posterPath: "/seasons/1.jpg",
                    episodeCount: 28
                ),
                AnimeEntrySeasonSummaryDTO(
                    id: 101,
                    seasonNumber: 0,
                    title: "Specials",
                    posterPath: "/seasons/0.jpg",
                    episodeCount: 2
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummaryDTO(
                    id: 1000,
                    episodeNumber: 1,
                    title: "The Journey's End",
                    airDate: referenceDate(year: 2026, month: 6, day: 2),
                    imagePath: "/episodes/1.jpg"
                ),
                AnimeEntryEpisodeSummaryDTO(
                    id: 1001,
                    episodeNumber: 2,
                    title: "A Better Start",
                    airDate: referenceDate(year: 2026, month: 6, day: 3),
                    imagePath: "/episodes/2.jpg"
                )
            ]
        )
        try await store.performWithoutSyncRecording {
            let writer = LibraryMetadataRefreshWriter(modelContainer: modelContainer)
            let result = try await writer.apply(
                updates: [
                    .init(
                        entryID: originalEntry.id,
                        info: EntryMetadata(
                            name: "Frieren",
                            nameTranslations: ["en-US": "Frieren"],
                            overview: "Elf mage travels onward.",
                            overviewTranslations: ["en-US": "Elf mage travels onward."],
                            posterPath: "/posters/frieren.jpg",
                            backdropPath: "/backdrops/frieren.jpg",
                            logoPath: "/logos/frieren.png",
                            originalLanguageCode: "ja",
                            tmdbID: 209_867,
                            onAirDate: referenceDate(year: 2026, month: 6, day: 1),
                            linkToDetails: URL(string: "https://example.com/frieren"),
                            type: .series
                        ),
                        detail: reorderedFetchedDetailDTO,
                        preservingCustomPoster: false
                    )
                ],
                parentUpdates: []
            )
            #expect(result.writtenCount == 0)
            #expect(result.skippedCount == 1)
        }

        let refreshedEntry = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 209_867 }
            ).first
        )
        let refreshedDetail = try #require(refreshedEntry.detail)

        #expect(refreshedDetail.persistentModelID == originalDetail.persistentModelID)
        #expect(refreshedDetail.characters.first?.persistentModelID == originalCharacterModelID)
        #expect(refreshedDetail.characters.first?.id == originalCharacterID)
        #expect(refreshedDetail.staff.first?.persistentModelID == originalStaffModelID)
        #expect(refreshedDetail.seasons.first?.persistentModelID == originalSeasonModelID)
        #expect(refreshedDetail.episodes.first?.persistentModelID == originalEpisodeModelID)
    }

    @Test @MainActor func testRefreshInfosReportsAllFetchedEntriesSkippedWhenApplyWritesNothing()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...3).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        var completions: [LibraryRefreshCompletion] = []
        let reporter = LibraryRefreshReporter { event in
            if case .refreshComplete(let completion) = event {
                completions.append(completion)
            }
        }
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                LibraryMetadataRefreshApplyResult(
                    writtenCount: 0,
                    skippedCount: updates.count
                )
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: makeLibraryMetadataRefreshTestFetcher(),
            language: .english,
            options: .init(
                reporter: reporter,
                prefetchImages: false
            )
        )

        let completion = try #require(completions.first)
        #expect(completion.state == .completed)
        #expect(completion.successfulItemCount == 0)
        #expect(completion.failedItemCount == 0)
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

    @Test @MainActor func testRefreshInfosReportsFailureForFailedChunkAndSkippedRemainderAfterSaveFailure()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...17).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        let fetcher = makeLibraryMetadataRefreshTestFetcher()
        let latestInfo = try await fetcher.latestInfo(
            entryType: .movie,
            tmdbID: 1,
            language: .english
        )
        #expect(latestInfo.0.name == "Fight Club")

        var applyCallCount = 0
        var completions: [LibraryRefreshCompletion] = []
        let reporter = LibraryRefreshReporter { event in
            if case .refreshComplete(let completion) = event {
                completions.append(completion)
            }
        }
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                applyCallCount += 1
                if applyCallCount == 2 {
                    throw TestApplyError.failed
                }
                let expectedUpdateCount = 8
                #expect(updates.count == expectedUpdateCount)
                return LibraryMetadataRefreshApplyResult(
                    writtenCount: updates.count,
                    skippedCount: 0
                )
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: fetcher,
            language: .english,
            options: .init(
                reporter: reporter,
                prefetchImages: false
            )
        )

        #expect(applyCallCount == 2)
        #expect(completions.count == 1)
        #expect(completions[0].state == .partialComplete)
        #expect(completions[0].successfulItemCount == 8)
        #expect(completions[0].failedItemCount == 9)
    }

    @Test @MainActor func testRefreshInfosDoesNotStartNextChunkBeforeCurrentChunkCompletes()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...9).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        let probe = MetadataFetchConcurrencyProbe()
        let httpClient = RecordingTMDbHTTPClient { request in
            try await probe.recordRequest(path: request.url.path)
            return HTTPResponse(data: libraryMetadataRefreshFixtureData(for: request.url.path))
        }
        let fetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTranslationResponseData: { path in
                try await probe.recordRequest(path: path)
                return libraryMetadataRefreshFixtureData(for: path)
            }
        )
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                #expect(updates.count <= 8)
                return LibraryMetadataRefreshApplyResult(
                    writtenCount: updates.count,
                    skippedCount: 0
                )
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: fetcher,
            language: .english,
            options: .init(
                reporter: .silent,
                prefetchImages: false
            )
        )

        #expect(!(await probe.startedNinthMovieBeforeFirstMovieReturned))
    }
}

fileprivate enum TestApplyError: Error {
    case failed
}

private actor MetadataFetchConcurrencyProbe {
    private var firstMovieReturned = false
    private var ninthMovieStartedBeforeFirstMovieReturned = false

    var startedNinthMovieBeforeFirstMovieReturned: Bool {
        ninthMovieStartedBeforeFirstMovieReturned
    }

    func recordRequest(path: String) async throws {
        if path == "/3/movie/9", !firstMovieReturned {
            ninthMovieStartedBeforeFirstMovieReturned = true
        }

        if path == "/3/movie/1" {
            try await Task.sleep(nanoseconds: 250_000_000)
            firstMovieReturned = true
        }
    }
}

fileprivate func makeLibraryMetadataRefreshTestFetcher() -> InfoFetcher {
    let httpClient = RecordingTMDbHTTPClient { request in
        HTTPResponse(data: libraryMetadataRefreshFixtureData(for: request.url.path))
    }

    return InfoFetcher(
        client: TMDbClient(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        ),
        fetchTranslationResponseData: { path in
            libraryMetadataRefreshFixtureData(for: path)
        }
    )
}

fileprivate func libraryMetadataRefreshFixtureData(for path: String) -> Data {
    switch path {
    case "/3/configuration":
        Data(
            #"""
            {
                "images": {
                    "base_url": "http://image.tmdb.org/t/p/",
                    "secure_base_url": "https://image.tmdb.org/t/p/",
                    "backdrop_sizes": ["w300", "w780", "w1280", "original"],
                    "logo_sizes": ["w45", "w92", "w154", "w185", "w300", "w500", "original"],
                    "poster_sizes": ["w92", "w154", "w185", "w342", "w500", "w780", "original"],
                    "profile_sizes": ["w45", "w185", "h632", "original"],
                    "still_sizes": ["w92", "w185", "w300", "original"]
                },
                "change_keys": []
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/images"):
        Data(
            #"""
            {
                "id": 550,
                "backdrops": [
                    {
                        "aspect_ratio": 1.77777777777778,
                        "file_path": "/fCayJrkfRaCRCTh8GqN30f8oyQF.jpg",
                        "height": 720,
                        "iso_639_1": null,
                        "vote_average": 1.21,
                        "vote_count": 435,
                        "width": 1280
                    }
                ],
                "logos": [
                    {
                        "aspect_ratio": 2.5,
                        "file_path": "/fasasakfRaCRCTh8GqN30f8oyQF.jpg",
                        "height": 400,
                        "iso_639_1": null,
                        "vote_average": 5.31,
                        "vote_count": 345,
                        "width": 100
                    }
                ],
                "posters": [
                    {
                        "aspect_ratio": 0.666666666666667,
                        "file_path": "/fpemzjF623QVTe98pCVlwwtFC5N.jpg",
                        "height": 1800,
                        "iso_639_1": "en",
                        "vote_average": 5.21,
                        "vote_count": 3,
                        "width": 1200
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/translations"):
        Data(
            #"""
            {
                "id": 550,
                "translations": [
                    {
                        "iso_3166_1": "US",
                        "iso_639_1": "en",
                        "name": "English",
                        "english_name": "English",
                        "data": {
                            "title": "Fight Club",
                            "overview": "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
                            "homepage": "https://www.foxmovies.com/movies/fight-club",
                            "tagline": "Mischief. Mayhem. Soap."
                        }
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/credits"):
        Data(
            #"""
            {
                "id": 550,
                "cast": [
                    {
                        "cast_id": 4,
                        "character": "The Narrator",
                        "credit_id": "52fe4250c3a36847f80149f3",
                        "gender": 2,
                        "id": 819,
                        "name": "Edward Norton",
                        "order": 0,
                        "profile_path": "/eIkFHNlfretLS1spAcIoihKUS62.jpg"
                    }
                ],
                "crew": [
                    {
                        "credit_id": "56380f0cc3a3681b5c0200be",
                        "department": "Writing",
                        "gender": 0,
                        "id": 7469,
                        "job": "Screenplay",
                        "name": "Jim Uhls",
                        "profile_path": null
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.starts(with: "/3/movie/"):
        Data(
            #"""
            {
                "adult": false,
                "backdrop_path": "/fCayJrkfRaCRCTh8GqN30f8oyQF.jpg",
                "belongs_to_collection": null,
                "budget": 63000000,
                "genres": [
                    {
                        "id": 18,
                        "name": "Drama"
                    }
                ],
                "homepage": null,
                "id": 550,
                "imdb_id": "tt0137523",
                "origin_country": ["US"],
                "original_language": "en",
                "original_title": "Fight Club",
                "overview": "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
                "popularity": 0.5,
                "poster_path": null,
                "production_companies": [
                    {
                        "id": 508,
                        "logo_path": "/7PzJdsLGlR7oW4J0J5Xcd0pHGRg.png",
                        "name": "Regency Enterprises",
                        "origin_country": "US"
                    }
                ],
                "production_countries": [
                    {
                        "iso_3166_1": "US",
                        "name": "United States of America"
                    }
                ],
                "release_date": "1999-10-12",
                "revenue": 100853753,
                "runtime": 139,
                "spoken_languages": [
                    {
                        "iso_639_1": "en",
                        "name": "English"
                    }
                ],
                "status": "Released",
                "tagline": "How much can you know about yourself if you've never been in a fight?",
                "title": "Fight Club",
                "video": false,
                "vote_average": 7.8,
                "vote_count": 3439
            }
            """#.utf8
        )
    default:
        Data()
    }
}
