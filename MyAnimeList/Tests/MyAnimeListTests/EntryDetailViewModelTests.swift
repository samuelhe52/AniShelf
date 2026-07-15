//
//  EntryDetailViewModelTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
import SwiftData
import TMDb
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
                logoImagePath: "/logo.png",
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

        await viewModel.load(for: entry, language: .english)

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
                logoImagePath: "/logo-ja.png",
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

        await japaneseViewModel.load(for: japaneseEntry, language: .japanese)

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
                logoImagePath: "/logo-zh.png",
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

        await chineseViewModel.load(for: chineseEntry, language: .chinese)

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
                logoImagePath: "/logo-en.png",
                staff: fillerStaff + prioritizedStaff
            )
        )

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.staffCards.count == 36)
        #expect(viewModel.staffCards.prefix(9).map(\.id) == [101, 105, 102, 103, 104, 106, 107, 100, 108])
        #expect(viewModel.staffCards.suffix(27).map(\.id) == Array(0..<27))
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
                logoImagePath: "/logo-en.png",
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

        await viewModel.load(for: entry, language: .english)

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
                logoImagePath: "/logo-en.png",
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

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.staffCards.count == 1)
        #expect(viewModel.staffCards[0].secondaryText == "Sound Director / Music")
    }

    @Test @MainActor func testEntryDetailCapsDisplayedAggregateStaffRowsAtThirtySix() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 35,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Series",
                logoImagePath: "/logo-en.png",
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

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.staffCards.count == 26)
        #expect(viewModel.staffCards.prefix(13).allSatisfy { $0.secondaryText == "Director" })
        #expect(viewModel.staffCards.suffix(13).allSatisfy { $0.secondaryText == "Music" })
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
                logoImagePath: "/logo-en.png",
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

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.staffCards.count == 1)
        #expect(viewModel.staffCards[0].id == 20)
        #expect(viewModel.staffCards[0].secondaryText == "Director / Storyboard Artist")
    }

    @Test @MainActor func testEntryDetailUsesCachedSameLanguageDetailWhenLogoIsPresent() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let httpClient = RecordingTMDbHTTPClient { _ in
            HTTPResponse(statusCode: 500, data: Data())
        }
        let fetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTranslationResponseData: { _ in Data() }
        )
        let viewModel = EntryDetailViewModel(repository: repository, infoFetcher: fetcher)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 37,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Cached Detail",
                logoImagePath: "/logo.png"
            )
        )

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.displayTitle == "Cached Detail")
        #expect(viewModel.loadError == nil)
        #expect(await httpClient.requests.isEmpty)
    }

    @Test @MainActor func testEntryDetailRefetchesCachedSameLanguageDetailWhenLogoIsMissing() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let httpClient = RecordingTMDbHTTPClient { _ in
            HTTPResponse(statusCode: 500, data: Data())
        }
        let fetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTranslationResponseData: { _ in Data() }
        )
        let viewModel = EntryDetailViewModel(repository: repository, infoFetcher: fetcher)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 38,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Cached Detail"
            )
        )

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.displayTitle == "Cached Detail")
        #expect(viewModel.loadError != nil)
        #expect(!(await httpClient.requests).isEmpty)
    }

    @Test @MainActor func testEntryDetailRetriesSameRequestAfterFailure() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = FailingEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 39)

        await viewModel.load(for: entry, language: .english)
        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(viewModel.loadError != nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEntryDetailRestoresPersistedDetailAndRetriesAfterSaveFailure()
        async throws
    {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 40,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Persisted Detail",
                overview: "Persisted overview",
                characters: [
                    AnimeEntryCharacter(
                        id: 1,
                        characterName: "Persisted Character",
                        actorName: "Persisted Actor"
                    )
                ],
                staff: [
                    AnimeEntryStaff(
                        id: 2,
                        name: "Persisted Staff",
                        role: "Director",
                        jobs: [
                            AnimeEntryStaffJob(
                                creditID: "persisted-director",
                                job: "Director",
                                episodeCount: 12
                            )
                        ]
                    )
                ],
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 3,
                        seasonNumber: 1,
                        title: "Persisted Season"
                    )
                ],
                episodes: [
                    AnimeEntryEpisodeSummary(
                        id: 4,
                        episodeNumber: 1,
                        title: "Persisted Episode"
                    )
                ]
            )
        )
        try dataProvider.dataHandler.newEntry(entry)
        entry.notes = "Unsaved user note"

        let loader = RetryingPersistedEntryDetailLoader()
        var saveAttemptCount = 0
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            },
            detailPersistenceSaver: {
                saveAttemptCount += 1
                if saveAttemptCount == 1 {
                    throw EntryDetailPersistenceError()
                }
                try dataProvider.dataHandler.modelContext.save()
            }
        )

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 1)
        #expect(saveAttemptCount == 1)
        #expect(viewModel.loadError == "The detail could not be saved.")
        #expect(viewModel.displayTitle == "Persisted Detail")
        #expect(entry.detail?.title == "Persisted Detail")
        #expect(entry.detail?.overview == "Persisted overview")
        #expect(entry.detail?.orderedCharacters.map(\.characterName) == ["Persisted Character"])
        #expect(entry.detail?.orderedStaff.map(\.name) == ["Persisted Staff"])
        #expect(entry.detail?.orderedStaff.first?.orderedJobs.map(\.creditID) == ["persisted-director"])
        #expect(entry.detail?.seasons.map(\.title) == ["Persisted Season"])
        #expect(entry.detail?.orderedEpisodes.map(\.title) == ["Persisted Episode"])
        #expect(entry.notes == "Unsaved user note")
        #expect(!viewModel.isLoading)

        let verificationContext = ModelContext(dataProvider.sharedModelContainer)
        let persistedEntries = try verificationContext.fetch(
            FetchDescriptor<AnimeEntry>(
                predicate: #Predicate { $0.tmdbID == 40 }
            )
        )
        let persistedEntry = try #require(persistedEntries.first)
        #expect(persistedEntry.detail?.title == "Persisted Detail")
        #expect(persistedEntry.detail?.overview == "Persisted overview")
        #expect(
            persistedEntry.detail?.orderedCharacters.map(\.characterName)
                == ["Persisted Character"]
        )
        #expect(persistedEntry.detail?.orderedStaff.map(\.name) == ["Persisted Staff"])
        #expect(
            persistedEntry.detail?.orderedStaff.first?.orderedJobs.map(\.creditID)
                == ["persisted-director"]
        )
        #expect(persistedEntry.detail?.seasons.map(\.title) == ["Persisted Season"])
        #expect(persistedEntry.detail?.orderedEpisodes.map(\.title) == ["Persisted Episode"])

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(saveAttemptCount == 2)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.displayTitle == "Retried Detail")
        #expect(entry.detail?.title == "Retried Detail")
        #expect(entry.detail?.overview == "Retried overview")
        #expect(entry.detail?.orderedCharacters.map(\.characterName) == ["Retried Character"])
        #expect(entry.notes == "Unsaved user note")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEntryDetailRemovesNewDetailAfterSaveFailureAndRetries() async throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let entry = AnimeEntry(name: "Movie", type: .movie, tmdbID: 41)
        try dataProvider.dataHandler.newEntry(entry)

        let loader = RetryingPersistedEntryDetailLoader()
        var saveAttemptCount = 0
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            },
            detailPersistenceSaver: {
                saveAttemptCount += 1
                if saveAttemptCount == 1 {
                    throw EntryDetailPersistenceError()
                }
                try dataProvider.dataHandler.modelContext.save()
            }
        )

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 1)
        #expect(viewModel.loadError == "The detail could not be saved.")
        #expect(entry.detail == nil)
        #expect(!viewModel.isLoading)

        let verificationContext = ModelContext(dataProvider.sharedModelContainer)
        let persistedEntries = try verificationContext.fetch(
            FetchDescriptor<AnimeEntry>(
                predicate: #Predicate { $0.tmdbID == 41 }
            )
        )
        #expect(try #require(persistedEntries.first).detail == nil)

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(saveAttemptCount == 2)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.displayTitle == "Retried Detail")
        #expect(entry.detail?.title == "Retried Detail")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEntryDetailCancellationDoesNotSurfaceErrorAndAllowsRetry() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = CancellableEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 40)

        let cancelledLoad = Task {
            await viewModel.load(for: entry, language: .english)
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.displayTitle != "Cancelled Detail")

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(viewModel.displayTitle == "Retried Detail")
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testOlderLanguageRequestCannotOverwriteNewerDetail() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = DelayedLanguageEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 41)

        let olderLoad = Task {
            await viewModel.load(for: entry, language: .japanese)
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        await viewModel.load(for: entry, language: .english)
        await olderLoad.value

        #expect(viewModel.displayTitle == "English Detail")
        #expect(entry.detail?.language == Language.english.rawValue)
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testCancelledBeforeStartDetailLoadDoesNotMutateCurrentState() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = ImmediateLanguageEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 42)

        await viewModel.load(for: entry, language: .english)

        let cancelledLoad = Task { @MainActor in
            await viewModel.load(for: entry, language: .japanese)
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(await loader.requestCount == 1)
        #expect(viewModel.displayTitle == "English Detail")
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
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

    @Test @MainActor func testEpisodePreviewShowsTargetStaffRolesInConfiguredOrder() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                overview: "Episode overview",
                crew: [
                    makeCrewMember(id: 1, name: "Director Person", job: "Director"),
                    makeCrewMember(id: 2, name: "Writer Person", job: "Writer"),
                    makeCrewMember(id: 3, name: "Storyboard Person", job: "Storyboard Artist"),
                    makeCrewMember(id: 4, name: "Animation Person", job: "Animation Director"),
                    makeCrewMember(id: 5, name: "Supervising Person", job: "Supervising Animation Director")
                ]
            )
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(viewModel.overviewText == "Episode overview")
        #expect(
            viewModel.staffRows.map(\.role) == [
                "Director",
                "Writer",
                "Storyboard Artist",
                "Animation Director",
                "Supervising Animation Director"
            ])
        #expect(
            viewModel.staffRows.map(\.names) == [
                "Director Person",
                "Writer Person",
                "Storyboard Person",
                "Animation Person",
                "Supervising Person"
            ])
    }

    @Test @MainActor func testEpisodePreviewOmitsMissingAndNoisyStaffRoles() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                crew: [
                    makeCrewMember(id: 1, name: "Director Person", job: "Director"),
                    makeCrewMember(id: 2, name: "Key Animator", job: "Key Animation"),
                    makeCrewMember(id: 3, name: "Compositor", job: "Compositing Artist")
                ]
            )
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(viewModel.staffRows.map(\.role) == ["Director"])
        #expect(viewModel.staffRows.map(\.names) == ["Director Person"])
    }

    @Test @MainActor func testEpisodePreviewCollapsesMultipleCrewNamesPerRole() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                crew: [
                    makeCrewMember(id: 1, name: "Writer One", job: "Writer"),
                    makeCrewMember(id: 2, name: "Writer Two", job: "Writer"),
                    makeCrewMember(id: 3, name: "Writer Three", job: "Writer"),
                    makeCrewMember(id: 4, name: "Writer Four", job: "Writer")
                ]
            )
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(
            viewModel.staffRows == [
                EpisodePreviewStaffRow(
                    role: "Writer",
                    names: "Writer One, Writer Two, Writer Three +1"
                )
            ])
    }

    @Test @MainActor func testEpisodePreviewUsesLocalizedRoleNames() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                crew: [makeCrewMember(id: 1, name: "Yasuko Kobayashi", job: "Writer")]
            )
        }

        await viewModel.load(
            card: makeEpisodePreviewCard(),
            context: .init(seriesTMDbID: 1429, seasonNumber: 1, language: .japanese)
        )

        #expect(
            viewModel.staffRows == [
                EpisodePreviewStaffRow(role: "脚本", names: "Yasuko Kobayashi")
            ])
    }

    @Test @MainActor func testEpisodePreviewFallsBackToOverviewOnlyWhenFetchFailsOrCrewIsEmpty() async {
        let emptyCrewViewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(overview: nil, crew: [])
        }

        await emptyCrewViewModel.load(
            card: makeEpisodePreviewCard(),
            context: makeEpisodePreviewContext()
        )

        #expect(
            emptyCrewViewModel.overviewText == String(localized: EntryDetailL10n.noOverviewAvailable)
        )
        #expect(emptyCrewViewModel.staffRows.isEmpty)

        struct EpisodePreviewError: Error {}
        let failingViewModel = EpisodePreviewViewModel { _, _ in
            throw EpisodePreviewError()
        }

        await failingViewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(
            failingViewModel.overviewText == String(localized: EntryDetailL10n.noOverviewAvailable)
        )
        #expect(failingViewModel.staffRows.isEmpty)
    }

    @Test @MainActor func testEpisodePreviewRetriesSameRequestAfterFailure() async {
        let loader = RetryingEpisodePreviewLoader(failureMode: .error)
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())
        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(await loader.requestCount == 2)
        #expect(viewModel.overviewText == "Retried preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEpisodePreviewCancellationIsSilentAndRetryable() async {
        let loader = RetryingEpisodePreviewLoader(failureMode: .cancellation)
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        let cancelledLoad = Task { @MainActor in
            await viewModel.load(
                card: makeEpisodePreviewCard(),
                context: makeEpisodePreviewContext()
            )
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(!viewModel.isLoading)

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(await loader.requestCount == 2)
        #expect(viewModel.overviewText == "Retried preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEpisodePreviewURLCancellationIsSilentAndRetryable() async {
        let loader = RetryingEpisodePreviewLoader(failureMode: .urlCancellation)
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(!viewModel.isLoading)

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(await loader.requestCount == 2)
        #expect(viewModel.overviewText == "Retried preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testOlderEpisodePreviewCannotOverwriteNewerLanguage() async {
        let loader = DelayedLanguageEpisodePreviewLoader()
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        let olderLoad = Task { @MainActor in
            await viewModel.load(
                card: makeEpisodePreviewCard(),
                context: makeEpisodePreviewContext(language: .japanese)
            )
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        await viewModel.load(
            card: makeEpisodePreviewCard(),
            context: makeEpisodePreviewContext(language: .english)
        )
        await olderLoad.value

        #expect(viewModel.overviewText == "English preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testSeasonEpisodeLoaderRestartsAfterCancellation() async {
        let loader = RetryingSeasonEpisodeLoader()
        let viewModel = SeriesSeasonEpisodeLoader { seriesID, seasonNumber, language in
            try await loader.load(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                language: language
            )
        }

        let cancelledLoad = Task { @MainActor in
            await viewModel.load(
                requestKey: "1429-1-en-US",
                seriesTMDbID: 1429,
                seasonNumber: 1,
                language: .english
            )
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(!viewModel.isLoading)
        #expect(!viewModel.loadFailed)

        await viewModel.load(
            requestKey: "1429-1-en-US",
            seriesTMDbID: 1429,
            seasonNumber: 1,
            language: .english
        )

        #expect(await loader.requestCount == 2)
        #expect(viewModel.episodes.map(\.title) == ["1. Retried episode"])
        #expect(viewModel.loadedRequestKey == "1429-1-en-US")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testOlderSeasonEpisodeLoadCannotOverwriteNewerLanguage() async {
        let loader = DelayedLanguageSeasonEpisodeLoader()
        let viewModel = SeriesSeasonEpisodeLoader { seriesID, seasonNumber, language in
            try await loader.load(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                language: language
            )
        }

        let olderLoad = Task { @MainActor in
            await viewModel.load(
                requestKey: "1429-1-ja-JP",
                seriesTMDbID: 1429,
                seasonNumber: 1,
                language: .japanese
            )
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        await viewModel.load(
            requestKey: "1429-1-en-US",
            seriesTMDbID: 1429,
            seasonNumber: 1,
            language: .english
        )
        await olderLoad.value

        #expect(viewModel.episodes.map(\.title) == ["1. English episode"])
        #expect(viewModel.loadedRequestKey == "1429-1-en-US")
        #expect(!viewModel.isLoading)
        #expect(!viewModel.loadFailed)
    }

    @Test @MainActor func testSeasonEpisodeURLCancellationIsSilentAndRetryable() async {
        let loader = URLCancelledSeasonEpisodeLoader()
        let viewModel = SeriesSeasonEpisodeLoader { seriesID, seasonNumber, language in
            try await loader.load(
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                language: language
            )
        }

        await viewModel.load(
            requestKey: "1429-1-en-US",
            seriesTMDbID: 1429,
            seasonNumber: 1,
            language: .english
        )

        #expect(!viewModel.isLoading)
        #expect(!viewModel.loadFailed)

        await viewModel.load(
            requestKey: "1429-1-en-US",
            seriesTMDbID: 1429,
            seasonNumber: 1,
            language: .english
        )

        #expect(await loader.requestCount == 2)
        #expect(viewModel.episodes.map(\.title) == ["1. Retried episode"])
        #expect(!viewModel.isLoading)
        #expect(!viewModel.loadFailed)
    }

    @Test func testEpisodePresentationMarksWatchedEpisodesFromContiguousProgress() {
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                3,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                4,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
    }

    @Test func testEpisodePresentationIgnoresNonTrackableProgress() {
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 0,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 0,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 0,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
    }

    @Test func testEpisodePresentationStopsAtWatchedThroughEpisode() {
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                4,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 4,
                    episodeCount: 4,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                5,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 4,
                    episodeCount: 4,
                    updatedAt: .distantPast
                )
            )
        )
    }

    @Test func testEpisodePresentationOnlyMarksWatchedEpisodesWhileWatching() {
        let summary = AnimeEntryEpisodeProgressSummary(
            seasonNumber: 1,
            watchedThroughEpisode: 4,
            episodeCount: 12,
            updatedAt: .distantPast
        )

        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .planToWatch,
                summary: summary
            )
        )
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watching,
                summary: summary
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watched,
                summary: summary
            )
        )
    }
}

fileprivate struct EntryDetailLoaderError: Error {}

fileprivate struct EntryDetailPersistenceError: LocalizedError {
    var errorDescription: String? { "The detail could not be saved." }
}

private actor FailingEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        throw EntryDetailLoaderError()
    }
}

private actor RetryingPersistedEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: requestCount == 1 ? "Failed Detail" : "Retried Detail",
            overview: requestCount == 1 ? "Failed overview" : "Retried overview",
            logoImagePath: requestCount == 1 ? "/failed-logo.png" : "/retried-logo.png",
            characters: [
                AnimeEntryCharacterDTO(
                    id: requestCount + 1,
                    characterName: requestCount == 1 ? "Failed Character" : "Retried Character",
                    actorName: "Actor"
                )
            ]
        )
    }
}

private actor CancellableEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        if requestCount == 1 {
            try? await Task.sleep(for: .seconds(30))
            return AnimeEntryDetailDTO(
                language: language.rawValue,
                title: "Cancelled Detail",
                logoImagePath: "/cancelled-logo.png"
            )
        }
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: "Retried Detail",
            logoImagePath: "/retried-logo.png"
        )
    }
}

private actor DelayedLanguageEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        if language == .japanese {
            try await Task.sleep(for: .milliseconds(200))
        }
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: language == .japanese ? "Japanese Detail" : "English Detail",
            logoImagePath: "/\(language.rawValue)-logo.png"
        )
    }
}

private actor ImmediateLanguageEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: language == .japanese ? "Japanese Detail" : "English Detail",
            logoImagePath: "/\(language.rawValue)-logo.png"
        )
    }
}

private actor RetryingEpisodePreviewLoader {
    enum FailureMode {
        case error
        case cancellation
        case urlCancellation
    }

    private let failureMode: FailureMode
    private(set) var requestCount = 0

    init(failureMode: FailureMode) {
        self.failureMode = failureMode
    }

    func load(context: EpisodePreviewContext, episodeNumber: Int) async throws -> TVEpisode {
        requestCount += 1
        if requestCount == 1 {
            switch failureMode {
            case .error:
                throw EntryDetailLoaderError()
            case .cancellation:
                try await Task.sleep(for: .seconds(30))
            case .urlCancellation:
                throw URLError(.cancelled)
            }
        }
        return makeEpisodePreviewDetail(overview: "Retried preview", crew: [])
    }
}

private actor DelayedLanguageEpisodePreviewLoader {
    private(set) var requestCount = 0

    func load(context: EpisodePreviewContext, episodeNumber: Int) async throws -> TVEpisode {
        requestCount += 1
        if context.language == .japanese {
            try await Task.sleep(for: .milliseconds(200))
        }
        let overview = context.language == .japanese ? "Japanese preview" : "English preview"
        return makeEpisodePreviewDetail(overview: overview, crew: [])
    }
}

private actor RetryingSeasonEpisodeLoader {
    private(set) var requestCount = 0

    func load(seriesID: Int, seasonNumber: Int, language: MyAnimeList.Language) async throws
        -> [AnimeEntryEpisodeSummaryDTO]
    {
        requestCount += 1
        if requestCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return [
            AnimeEntryEpisodeSummaryDTO(
                id: 1,
                episodeNumber: 1,
                title: "Retried episode"
            )
        ]
    }
}

private actor DelayedLanguageSeasonEpisodeLoader {
    private(set) var requestCount = 0

    func load(seriesID: Int, seasonNumber: Int, language: MyAnimeList.Language) async throws
        -> [AnimeEntryEpisodeSummaryDTO]
    {
        requestCount += 1
        if language == .japanese {
            try await Task.sleep(for: .milliseconds(200))
        }
        let title = language == .japanese ? "Japanese episode" : "English episode"
        return [AnimeEntryEpisodeSummaryDTO(id: 1, episodeNumber: 1, title: title)]
    }
}

private actor URLCancelledSeasonEpisodeLoader {
    private(set) var requestCount = 0

    func load(seriesID: Int, seasonNumber: Int, language: MyAnimeList.Language) async throws
        -> [AnimeEntryEpisodeSummaryDTO]
    {
        requestCount += 1
        if requestCount == 1 {
            throw URLError(.cancelled)
        }
        return [AnimeEntryEpisodeSummaryDTO(id: 1, episodeNumber: 1, title: "Retried episode")]
    }
}

fileprivate func makeEpisodePreviewContext(
    language: MyAnimeList.Language = .english
) -> EpisodePreviewContext {
    .init(seriesTMDbID: 1429, seasonNumber: 1, language: language)
}

fileprivate func makeEpisodePreviewCard() -> EntryDetailEpisodeCard {
    .init(
        id: 65_480,
        episodeNumber: 1,
        title: "1. Preview",
        subtitle: "Apr 7, 2013",
        imageURL: nil
    )
}

fileprivate func makeEpisodePreviewDetail(
    overview: String? = "Episode overview",
    crew: [CrewMember]
) -> TVEpisode {
    TVEpisode(
        id: 65_480,
        name: "Preview",
        episodeNumber: 1,
        seasonNumber: 1,
        overview: overview,
        crew: crew
    )
}

fileprivate func makeCrewMember(id: Int, name: String, job: String) -> CrewMember {
    CrewMember(
        id: id,
        creditID: "\(job)-\(id)",
        name: name,
        job: job,
        department: "Directing"
    )
}
