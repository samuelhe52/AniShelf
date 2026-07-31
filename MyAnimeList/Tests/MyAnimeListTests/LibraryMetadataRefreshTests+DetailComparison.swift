//
//  LibraryMetadataRefreshTests+DetailComparison.swift
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

}
