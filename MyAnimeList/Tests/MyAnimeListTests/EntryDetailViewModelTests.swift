//
//  EntryDetailViewModelTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
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
                logoImagePath: "/logo-en.png",
                staff: fillerStaff + prioritizedStaff
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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

        await viewModel.load(for: entry, language: .english, dataHandler: nil)
        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(await loader.requestCount == 2)
        #expect(viewModel.loadError != nil)
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
            await viewModel.load(for: entry, language: .english, dataHandler: nil)
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.displayTitle != "Cancelled Detail")

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

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
            await viewModel.load(for: entry, language: .japanese, dataHandler: nil)
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        await viewModel.load(for: entry, language: .english, dataHandler: nil)
        await olderLoad.value

        #expect(viewModel.displayTitle == "English Detail")
        #expect(entry.detail?.language == Language.english.rawValue)
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

private actor FailingEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        throw EntryDetailLoaderError()
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
