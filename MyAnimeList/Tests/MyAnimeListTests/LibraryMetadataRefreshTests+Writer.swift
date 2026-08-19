//
//  LibraryMetadataRefreshTests+Writer.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension LibraryMetadataRefreshTests {
    @Test @MainActor func testBackgroundMetadataRefreshWriterRepairsParentLinksUsingUncappedPreferredParent()
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
        for index in 0..<20 {
            let duplicateParent = AnimeEntry(
                name: "Hidden Parent \(index)",
                type: .series,
                tmdbID: 300,
                dateSaved: referenceDate(year: 2026, month: 5, day: 1)
            )
            duplicateParent.setDisplayState(false)
            try store.repository.newEntry(duplicateParent)
        }
        let preferredParent = AnimeEntry(
            name: "Preferred Parent",
            type: .series,
            tmdbID: 300,
            dateSaved: referenceDate(year: 2026, month: 5, day: 2)
        )
        try store.repository.newEntry(preferredParent)
        let collidingMovie = AnimeEntry(
            name: "Colliding Movie",
            type: .movie,
            tmdbID: 300,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        try store.repository.newEntry(collidingMovie)
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
        #expect(refreshedChild.name == "Season 1 Refreshed")
        #expect(refreshedChild.parentSeriesEntry?.id == preferredParent.id)
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

}
