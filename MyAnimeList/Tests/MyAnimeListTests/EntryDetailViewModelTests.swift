//
//  EntryDetailViewModelTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct EntryDetailViewModelTests {
    @Test func testEntryDetailLargeSeriesExpansionPolicy() {
        #expect(
            EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: 200,
                seasonCount: 1,
                seasonCardCount: 1
            )
        )
        #expect(
            !EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: 199,
                seasonCount: 20,
                seasonCardCount: 20
            )
        )
        #expect(
            EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: nil,
                seasonCount: 9,
                seasonCardCount: 0
            )
        )
        #expect(
            !EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: nil,
                seasonCount: nil,
                seasonCardCount: 8
            )
        )
    }

    @Test @MainActor func testEntryDetailPlacesSpecialsSeasonAfterNumberedSeasons() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 20,
            detail: AnimeEntryDetail(
                language: "en",
                title: "Series",
                logoImageURL: URL(string: "https://example.com/logo.png"),
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 100,
                        seasonNumber: 0,
                        title: "Specials"
                    ),
                    AnimeEntrySeasonSummary(
                        id: 101,
                        seasonNumber: 2,
                        title: "Season 2"
                    ),
                    AnimeEntrySeasonSummary(
                        id: 102,
                        seasonNumber: 1,
                        title: "Season 1"
                    )
                ]
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.seasonCards.map(\.seasonNumber) == [1, 2, 0])
    }

    @Test @MainActor func testEntryDetailLocalizesStaffRoleFallbacks() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))

        let japaneseViewModel = EntryDetailViewModel(repository: repository)
        let japaneseEntry = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 30,
            detail: AnimeEntryDetail(
                language: Language.japanese.rawValue,
                title: "Movie",
                logoImageURL: URL(string: "https://example.com/logo-ja.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 1,
                        name: "Staff One",
                        role: "Key Animation / Director"
                    ),
                    AnimeEntryStaff(
                        id: 2,
                        name: "Staff Two",
                        role: "Unknown Role"
                    ),
                    AnimeEntryStaff(
                        id: 5,
                        name: "Staff Five",
                        role: "Storyboard Artist / Settings"
                    )
                ]
            )
        )

        await japaneseViewModel.load(for: japaneseEntry, language: .japanese, dataHandler: nil)

        #expect(
            japaneseViewModel.staffCards.map(\.secondaryText)
                == ["原画 / 監督", "絵コンテ / 設定", "Unknown Role"]
        )

        let chineseViewModel = EntryDetailViewModel(repository: repository)
        let chineseEntry = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 31,
            detail: AnimeEntryDetail(
                language: Language.chinese.rawValue,
                title: "Movie",
                logoImageURL: URL(string: "https://example.com/logo-zh.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 3,
                        name: "Staff Three",
                        role: "Theme Song Performance / Producer"
                    ),
                    AnimeEntryStaff(
                        id: 4,
                        name: "Staff Four",
                        role: "Visual Effects"
                    ),
                    AnimeEntryStaff(
                        id: 6,
                        name: "Staff Six",
                        role: "Production Design / Graphic Designer"
                    )
                ]
            )
        )

        await chineseViewModel.load(for: chineseEntry, language: .chinese, dataHandler: nil)

        #expect(
            chineseViewModel.staffCards.map(\.secondaryText)
                == ["制作设计 / 平面设计", "视觉效果", "主题曲演唱 / 制片人"]
        )
    }

    @Test @MainActor func testEntryDetailPrioritizesImportantStaffRolesWithoutPersistingSort() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)

        let fillerStaff = (0..<40).map {
            AnimeEntryStaff(
                id: $0,
                name: "Filler \($0)",
                role: "Other Role \($0)",
                displayOrder: $0
            )
        }
        let prioritizedStaff = [
            AnimeEntryStaff(
                id: 100,
                name: "Music",
                role: "Music",
                displayOrder: 40
            ),
            AnimeEntryStaff(
                id: 101,
                name: "Director",
                role: "Director",
                displayOrder: 41
            ),
            AnimeEntryStaff(
                id: 102,
                name: "Writer",
                role: "Series Composition",
                displayOrder: 42
            ),
            AnimeEntryStaff(
                id: 103,
                name: "Designer",
                role: "Character Designer",
                displayOrder: 43
            ),
            AnimeEntryStaff(
                id: 104,
                name: "Animator",
                role: "Animation Director",
                displayOrder: 44
            ),
            AnimeEntryStaff(
                id: 105,
                name: "Original",
                role: "Original Story",
                displayOrder: 45
            ),
            AnimeEntryStaff(
                id: 106,
                name: "Art",
                role: "Art Direction",
                displayOrder: 46
            ),
            AnimeEntryStaff(
                id: 107,
                name: "Effects",
                role: "Visual Effects",
                displayOrder: 47
            ),
            AnimeEntryStaff(
                id: 108,
                name: "Producer",
                role: "Producer",
                displayOrder: 48
            )
        ]
        let entry = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 32,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Movie",
                logoImageURL: URL(string: "https://example.com/logo-en.png"),
                staff: fillerStaff + prioritizedStaff
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.staffCards.count == 24)
        #expect(viewModel.staffCards.prefix(9).map(\.id) == [101, 105, 102, 103, 104, 106, 107, 100, 108])
        #expect(viewModel.staffCards.suffix(15).map(\.id) == Array(0..<15))
        #expect(entry.detail?.orderedStaff.map(\.id) == Array(0..<40) + Array(100...108))
    }

    @Test @MainActor func testEntryDetailBucketsAggregateStaffAcrossMultipleRows() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 33,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Series",
                logoImageURL: URL(string: "https://example.com/logo-en.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 10,
                        name: "Creator",
                        role: "Compatibility Role",
                        department: "Directing",
                        jobs: [
                            AnimeEntryStaffJob(
                                creditID: "director",
                                job: "Director",
                                episodeCount: 12,
                                displayOrder: 0
                            ),
                            AnimeEntryStaffJob(
                                creditID: "music",
                                job: "Music",
                                episodeCount: 8,
                                displayOrder: 1
                            ),
                            AnimeEntryStaffJob(
                                creditID: "research",
                                job: "Researcher",
                                episodeCount: 4,
                                displayOrder: 2
                            )
                        ],
                        displayOrder: 2
                    )
                ]
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.staffCards.count == 3)
        #expect(Set(viewModel.staffCards.map(\.id)).count == 3)
        #expect(viewModel.staffCards.map(\.primaryText) == ["Creator", "Creator", "Creator"])
        #expect(viewModel.staffCards.map(\.secondaryText) == ["Director", "Music", "Researcher"])
    }

    @Test @MainActor func testEntryDetailOrdersJobsWithinAggregateBucketAndTruncatesToTwo() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 34,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Series",
                logoImageURL: URL(string: "https://example.com/logo-en.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 11,
                        name: "Composer",
                        role: "Compatibility Role",
                        department: "Sound",
                        jobs: [
                            AnimeEntryStaffJob(
                                creditID: "musician",
                                job: "Musician",
                                episodeCount: 5,
                                displayOrder: 0
                            ),
                            AnimeEntryStaffJob(
                                creditID: "music",
                                job: "Music",
                                episodeCount: 7,
                                displayOrder: 1
                            ),
                            AnimeEntryStaffJob(
                                creditID: "sound-director",
                                job: "Sound Director",
                                episodeCount: 12,
                                displayOrder: 2
                            )
                        ]
                    )
                ]
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.staffCards.count == 1)
        #expect(viewModel.staffCards[0].secondaryText == "Sound Director / Music")
    }

    @Test @MainActor func testEntryDetailCapsDisplayedAggregateStaffRowsAtTwentyFour() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 35,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Series",
                logoImageURL: URL(string: "https://example.com/logo-en.png"),
                staff: (0..<13).map { index in
                    AnimeEntryStaff(
                        id: 100 + index,
                        name: "Creator \(index)",
                        role: "Compatibility Role",
                        department: "Directing",
                        jobs: [
                            AnimeEntryStaffJob(
                                creditID: "director-\(index)",
                                job: "Director",
                                episodeCount: 12,
                                displayOrder: 0
                            ),
                            AnimeEntryStaffJob(
                                creditID: "music-\(index)",
                                job: "Music",
                                episodeCount: 12,
                                displayOrder: 1
                            )
                        ],
                        displayOrder: index
                    )
                }
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.staffCards.count == 24)
        #expect(viewModel.staffCards.prefix(13).allSatisfy { $0.secondaryText == "Director" })
        #expect(viewModel.staffCards.suffix(11).allSatisfy { $0.secondaryText == "Music" })
    }

    @Test @MainActor func testEntryDetailRendersLegacyFlattenedStaffWithoutJobs() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 36,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Movie",
                logoImageURL: URL(string: "https://example.com/logo-en.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 20,
                        name: "Legacy Staff",
                        role: "Director / Storyboard Artist",
                        department: "Directing"
                    )
                ]
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.staffCards.count == 1)
        #expect(viewModel.staffCards[0].id == 20)
        #expect(viewModel.staffCards[0].secondaryText == "Director / Storyboard Artist")
    }

    @Test func testReplaceDetailRewritesFlattenedAggregateStaffIntoPersistedJobs() throws {
        let entry = AnimeEntry.template()
        entry.detail = AnimeEntryDetail(
            language: "en-US",
            title: "Old",
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Creator",
                    role: "Director / Music",
                    department: "Directing",
                    displayOrder: 0
                )
            ]
        )

        let refreshedDTO = AnimeEntryDetailDTO(
            language: "en-US",
            title: "New",
            staff: [
                AnimeEntryStaffDTO(
                    id: 10,
                    name: "Creator",
                    role: "Directing",
                    department: "Directing",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "director",
                            job: "Director",
                            episodeCount: 12
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "music",
                            job: "Music",
                            episodeCount: 8
                        )
                    ]
                )
            ]
        )

        let detail = entry.replaceDetail(from: refreshedDTO)
        let staff = try #require(detail.orderedStaff.first)

        #expect(detail.title == "New")
        #expect(detail.orderedStaff.count == 1)
        #expect(staff.role == "Directing")
        #expect(staff.orderedJobs.map(\.creditID) == ["director", "music"])
        #expect(staff.orderedJobs.map(\.job) == ["Director", "Music"])
    }
}
