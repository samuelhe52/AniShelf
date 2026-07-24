//
//  TMDbSearchServiceBatchTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct TMDbSearchServiceBatchTests {
    @Test func testBatchPromptsTrimWhitespaceDropEmptyLinesAndPreserveOrder() {
        let prompts = TMDbSearchService.batchPrompts(
            from: "\n  Frieren  \n\nSpirited Away\n  \nKiki's Delivery Service \n"
        )

        #expect(prompts == ["Frieren", "Spirited Away", "Kiki's Delivery Service"])
    }

    @Test func testParsedBatchPromptsRecognizeStructuredFormats() {
        let prompts = TMDbSearchService.parsedBatchPrompts(
            from: "movie:4935\nseries:24835\nseason:24835:1\nFrieren"
        )

        #expect(
            prompts == [
                .movieID(displayText: "movie:4935", tmdbID: 4935),
                .seriesID(displayText: "series:24835", tmdbID: 24835),
                .season(displayText: "season:24835:1", seriesTMDbID: 24835, seasonNumber: 1),
                .title(displayText: "Frieren")
            ]
        )
    }

    @Test func testParsedBatchPromptsTrimWhitespaceBeforeStructuredParsing() {
        let prompts = TMDbSearchService.parsedBatchPrompts(
            from: "\n  movie:4935  \n\tseries:24835\n  season:24835:2  \n"
        )

        #expect(
            prompts == [
                .movieID(displayText: "movie:4935", tmdbID: 4935),
                .seriesID(displayText: "series:24835", tmdbID: 24835),
                .season(displayText: "season:24835:2", seriesTMDbID: 24835, seasonNumber: 2)
            ]
        )
    }

    @Test func testParsedBatchPromptsFallbackMalformedStructuredTextToTitles() {
        let prompts = TMDbSearchService.parsedBatchPrompts(
            from: "movie:abc\nseries:\nseason:24835\nseason:24835:one\nmovie:4935:extra\nmovie: 4935"
        )

        #expect(
            prompts == [
                .title(displayText: "movie:abc"),
                .title(displayText: "series:"),
                .title(displayText: "season:24835"),
                .title(displayText: "season:24835:one"),
                .title(displayText: "movie:4935:extra"),
                .title(displayText: "movie: 4935")
            ]
        )
    }

    @MainActor
    @Test func testBatchSearchPreservesPromptOrderWhenAsyncCompletesOutOfOrder() async {
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "First": [makeEntryMetadata("First Movie", tmdbID: 101, type: .movie)],
                    "Second": [makeEntryMetadata("Second Movie", tmdbID: 201, type: .movie)],
                    "Third": [makeEntryMetadata("Third Movie", tmdbID: 301, type: .movie)]
                ],
                movieDelays: [
                    "First": 60_000_000,
                    "Second": 10_000_000,
                    "Third": 30_000_000
                ]
            )
        )

        await service.performBatchSearch(input: "First\nSecond\nThird", language: .english)

        #expect(service.batchResults.map(\.prompt) == ["First", "Second", "Third"])
        #expect(service.batchResults.map { $0.movie?.tmdbID } == [101, 201, 301])
    }

    @MainActor
    @Test func testBatchSearchKeepsTopSeriesAndTopMoviePerPrompt() async {
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [
                        makeEntryMetadata("Frieren Movie 1", tmdbID: 101, type: .movie),
                        makeEntryMetadata("Frieren Movie 2", tmdbID: 102, type: .movie)
                    ]
                ],
                seriesByPrompt: [
                    "Frieren": [
                        makeEntryMetadata("Frieren Series 1", tmdbID: 201, type: .series),
                        makeEntryMetadata("Frieren Series 2", tmdbID: 202, type: .series)
                    ]
                ]
            )
        )

        await service.performBatchSearch(input: "Frieren", language: .english)

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].series?.tmdbID == 201)
        #expect(service.batchResults[0].movie?.tmdbID == 101)
    }

    @MainActor
    @Test func testBatchSearchResolvesDirectMovieID() async {
        let movie = makeEntryMetadata("Direct Movie", tmdbID: 4935, type: .movie)
        let service = TMDbSearchService(
            client: makeClient(
                directMoviesByID: [
                    4935: movie
                ]
            )
        )

        await service.performBatchSearch(input: "movie:4935", language: .english)

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].prompt == "movie:4935")
        #expect(service.batchResults[0].movie?.tmdbID == 4935)
        #expect(service.batchResults[0].series == nil)
        #expect(service.batchRegisteredMovieCount == 1)
        #expect(service.isBatchSelected(info: movie))
    }

    @MainActor
    @Test func testBatchSearchResolvesDirectSeriesID() async {
        let series = makeEntryMetadata("Direct Series", tmdbID: 24835, type: .series)
        let service = TMDbSearchService(
            client: makeClient(
                directSeriesByID: [
                    24835: series
                ]
            )
        )

        await service.performBatchSearch(input: "series:24835", language: .english)

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].prompt == "series:24835")
        #expect(service.batchResults[0].series?.tmdbID == 24835)
        #expect(service.batchResults[0].movie == nil)
        #expect(service.batchRegisteredSeriesCount == 1)
        #expect(service.isBatchSelected(info: series))
    }

    @MainActor
    @Test func testBatchSearchResolvesDirectSeasonWithSeasonModePreselected() async {
        let series = makeEntryMetadata("CLANNAD", tmdbID: 24835, type: .series)
        let firstSeason = makeEntryMetadata(
            "Season 1",
            tmdbID: 248351,
            type: .season(seasonNumber: 1, parentSeriesID: 24835)
        )
        let secondSeason = makeEntryMetadata(
            "Season 2",
            tmdbID: 248352,
            type: .season(seasonNumber: 2, parentSeriesID: 24835)
        )
        let service = TMDbSearchService(
            client: makeClient(
                directSeriesByID: [
                    24835: series
                ],
                seasonsBySeriesID: [
                    24835: [firstSeason, secondSeason]
                ]
            )
        )

        await service.performBatchSearch(input: "season:24835:2", language: .english)

        let state = service.seriesSelectionState(for: series, context: .batch)

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].prompt == "season:24835:2")
        #expect(service.batchResults[0].series?.tmdbID == 24835)
        #expect(service.batchRegisteredSeriesCount == 0)
        #expect(service.batchRegisteredSeasonCount == 1)
        #expect(state.selectedMode == .season)
        #expect(state.seasonFetchStatus == .fetched)
        #expect(state.seasons.map(\.tmdbID) == [248351, 248352])
        #expect(state.selectedSeasonIDs == Set([248352]))
        #expect(service.isBatchSelected(info: secondSeason))
        #expect(!service.isBatchSelected(info: firstSeason))
        #expect(!service.isBatchSelected(info: series))
    }

    @MainActor
    @Test func testBatchSearchMixedTitleAndStructuredLinesPreserveInputOrder() async {
        let titleMovie = makeEntryMetadata("Frieren Movie", tmdbID: 101, type: .movie)
        let directMovie = makeEntryMetadata("Direct Movie", tmdbID: 4935, type: .movie)
        let directSeries = makeEntryMetadata("Direct Series", tmdbID: 24835, type: .series)
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [titleMovie]
                ],
                directMoviesByID: [
                    4935: directMovie
                ],
                directSeriesByID: [
                    24835: directSeries
                ]
            )
        )

        await service.performBatchSearch(
            input: "Frieren\nmovie:4935\nseries:24835",
            language: .english
        )

        #expect(service.batchResults.map(\.prompt) == ["Frieren", "movie:4935", "series:24835"])
        #expect(service.batchResults.map { $0.movie?.tmdbID } == [101, 4935, nil])
        #expect(service.batchResults.map { $0.series?.tmdbID } == [nil, nil, 24835])
    }

    @MainActor
    @Test func testBatchSearchMalformedStructuredTextUsesTitleSearch() async {
        let movie = makeEntryMetadata("Movie Colon Text", tmdbID: 1101, type: .movie)
        let recorder = SearchCallRecorder()
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "movie:abc": [movie]
                ],
                recorder: recorder
            )
        )

        await service.performBatchSearch(input: "movie:abc", language: .english)
        let counts = await recorder.snapshot()

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].movie?.tmdbID == 1101)
        #expect(counts.movieCalls == 1)
        #expect(counts.seriesCalls == 1)
        #expect(counts.movieIDCalls == 0)
        #expect(counts.seriesIDCalls == 0)
    }

    @MainActor
    @Test func testBatchSearchStructuredIDMissesBecomeLineLocalNoResultRows() async {
        let service = TMDbSearchService(
            client: makeClient()
        )

        await service.performBatchSearch(input: "movie:4935\nseries:24835", language: .english)

        #expect(service.batchStatus == .loaded)
        #expect(service.batchResults.map(\.prompt) == ["movie:4935", "series:24835"])
        #expect(service.batchResults.allSatisfy { $0.hasNoResults })
        #expect(service.batchRegisteredCount == 0)
    }

    @MainActor
    @Test func testBatchSearchStructuredSeasonMissingSeasonBecomesNoResultRow() async {
        let series = makeEntryMetadata("Direct Series", tmdbID: 24835, type: .series)
        let firstSeason = makeEntryMetadata(
            "Season 1",
            tmdbID: 248351,
            type: .season(seasonNumber: 1, parentSeriesID: 24835)
        )
        let service = TMDbSearchService(
            client: makeClient(
                directSeriesByID: [
                    24835: series
                ],
                seasonsBySeriesID: [
                    24835: [firstSeason]
                ]
            )
        )

        await service.performBatchSearch(input: "season:24835:2", language: .english)

        #expect(service.batchStatus == .loaded)
        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].prompt == "season:24835:2")
        #expect(service.batchResults[0].hasNoResults)
        #expect(service.batchRegisteredCount == 0)
    }

    @MainActor
    @Test func testBatchSearchDirectMovieFailureBecomesBatchError() async {
        let service = TMDbSearchService(
            client: makeClient(
                directMovieErrorsByID: [
                    4935: TMDbError.unauthorised("Invalid API key")
                ]
            )
        )

        await service.performBatchSearch(input: "movie:4935", language: .english)

        guard case .error(let error) = service.batchStatus else {
            Issue.record("Expected batchStatus to be .error")
            return
        }
        #expect((error as? TMDbError) == .unauthorised("Invalid API key"))
        #expect(service.batchResults.isEmpty)
        #expect(service.batchRegisteredCount == 0)
    }

    @MainActor
    @Test func testBatchSearchDirectSeriesFailureBecomesBatchError() async {
        let service = TMDbSearchService(
            client: makeClient(
                directSeriesErrorsByID: [
                    24835: TMDbError.network(URLError(.notConnectedToInternet))
                ]
            )
        )

        await service.performBatchSearch(input: "series:24835", language: .english)

        guard case .error(let error) = service.batchStatus else {
            Issue.record("Expected batchStatus to be .error")
            return
        }
        #expect(error is TMDbError)
        #expect(service.batchResults.isEmpty)
        #expect(service.batchRegisteredCount == 0)
    }

    @MainActor
    @Test func testBatchSearchStructuredSeasonFetchFailureBecomesBatchError() async {
        let series = makeEntryMetadata("Direct Series", tmdbID: 24835, type: .series)
        let service = TMDbSearchService(
            client: makeClient(
                directSeriesByID: [
                    24835: series
                ],
                seasonErrorsBySeriesID: [
                    24835: TMDbError.unknown
                ]
            )
        )

        await service.performBatchSearch(input: "season:24835:2", language: .english)

        guard case .error(let error) = service.batchStatus else {
            Issue.record("Expected batchStatus to be .error")
            return
        }
        #expect((error as? TMDbError) == .unknown)
        #expect(service.batchResults.isEmpty)
        #expect(service.batchRegisteredCount == 0)
    }

    @MainActor
    @Test func testBatchSearchStructuredLinesBypassTitleSearchClosures() async {
        let recorder = SearchCallRecorder()
        let movie = makeEntryMetadata("Direct Movie", tmdbID: 4935, type: .movie)
        let series = makeEntryMetadata("Direct Series", tmdbID: 24835, type: .series)
        let season = makeEntryMetadata(
            "Season 1",
            tmdbID: 248351,
            type: .season(seasonNumber: 1, parentSeriesID: 24835)
        )
        let service = TMDbSearchService(
            client: makeClient(
                directMoviesByID: [
                    4935: movie
                ],
                directSeriesByID: [
                    24835: series
                ],
                seasonsBySeriesID: [
                    24835: [season]
                ],
                recorder: recorder
            )
        )

        await service.performBatchSearch(
            input: "movie:4935\nseries:24835\nseason:24835:1",
            language: .english
        )
        let counts = await recorder.snapshot()

        #expect(counts.movieCalls == 0)
        #expect(counts.seriesCalls == 0)
        #expect(counts.movieIDCalls == 1)
        #expect(counts.seriesIDCalls == 2)
    }

    @MainActor
    @Test func testBatchSearchAutoSelectsNonDuplicateResultsInBatchStateOnly() async {
        let movie = makeEntryMetadata("Frieren Movie", tmdbID: 101, type: .movie)
        let series = makeEntryMetadata("Frieren Series", tmdbID: 201, type: .series)
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [movie]
                ],
                seriesByPrompt: [
                    "Frieren": [series]
                ]
            )
        )

        await service.performBatchSearch(input: "Frieren", language: .english)

        #expect(service.registeredCount == 0)
        #expect(service.batchRegisteredCount == 2)
        #expect(service.isBatchSelected(info: movie))
        #expect(service.isBatchSelected(info: series))
        #expect(!service.isRegistered(info: movie))
        #expect(!service.isRegistered(info: series))
    }

    @MainActor
    @Test func testBatchSearchLeavesDuplicatesVisibleButUnselectedInBatchState() async {
        let duplicateMovie = makeEntryMetadata("Ghost in the Shell", tmdbID: 301, type: .movie)
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Ghost in the Shell": [duplicateMovie]
                ]
            ),
            checkDuplicate: { $0 == 301 }
        )

        await service.performBatchSearch(input: "Ghost in the Shell", language: .english)

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].movie?.tmdbID == 301)
        #expect(service.batchRegisteredCount == 0)
        #expect(!service.isBatchSelected(info: duplicateMovie))
    }

    @MainActor
    @Test func testBatchSessionStaysIndependentFromRegularSelectionAndSubmission() async {
        let regularMovie = makeEntryMetadata("Regular Movie", tmdbID: 401, type: .movie)
        let batchSeries = makeEntryMetadata("Batch Series", tmdbID: 402, type: .series)
        var submittedResults: [SearchResult] = []
        let service = TMDbSearchService(
            client: makeClient(
                seriesByPrompt: [
                    "Shared": [batchSeries]
                ]
            ),
            processResults: { results, _ in submittedResults = Array(results) }
        )

        service.register(info: regularMovie)
        await service.performBatchSearch(input: "Shared", language: .english)
        service.submitBatch()

        #expect(service.registeredCount == 1)
        #expect(service.batchRegisteredCount == 1)
        #expect(service.isRegistered(info: regularMovie))
        #expect(service.isBatchSelected(info: batchSeries))
        #expect(submittedResults == [SearchResult(tmdbID: 402, type: .series)])
    }

    @MainActor
    @Test func testChangingBatchSeriesModeDoesNotClearMatchingRegularSelection() async {
        let sharedSeries = makeEntryMetadata("Shared Series", tmdbID: 501, type: .series)
        let firstSeason = makeEntryMetadata(
            "Season 1",
            tmdbID: 511,
            type: .season(seasonNumber: 1, parentSeriesID: 501)
        )
        let service = TMDbSearchService(
            client: makeClient(
                seriesByPrompt: [
                    "Shared": [sharedSeries]
                ],
                seasonsBySeriesID: [
                    501: [firstSeason]
                ]
            )
        )

        service.register(info: sharedSeries)
        await service.performBatchSearch(input: "Shared", language: .english)
        await service.setSeriesSelectionMode(
            .season,
            for: sharedSeries,
            language: .english,
            context: .batch
        )

        #expect(service.registeredCount == 1)
        #expect(service.batchRegisteredSeriesCount == 0)
        #expect(service.isRegistered(info: sharedSeries))
        #expect(!service.isBatchSelected(info: sharedSeries))
    }

    @MainActor
    @Test func testBatchSeasonSelectionStatePersistsInServiceModel() async {
        let sharedSeries = makeEntryMetadata("Frieren", tmdbID: 601, type: .series)
        let firstSeason = makeEntryMetadata(
            "Season 1",
            tmdbID: 611,
            type: .season(seasonNumber: 1, parentSeriesID: 601)
        )
        let secondSeason = makeEntryMetadata(
            "Season 2",
            tmdbID: 612,
            type: .season(seasonNumber: 2, parentSeriesID: 601)
        )
        let service = TMDbSearchService(
            client: makeClient(
                seriesByPrompt: [
                    "Frieren": [sharedSeries]
                ],
                seasonsBySeriesID: [
                    601: [firstSeason, secondSeason]
                ]
            )
        )

        await service.performBatchSearch(input: "Frieren", language: .english)
        await service.setSeriesSelectionMode(
            .season,
            for: sharedSeries,
            language: .english,
            context: .batch
        )
        service.setSeasonSelection(true, for: firstSeason, context: .batch)

        let state = service.seriesSelectionState(for: sharedSeries, context: .batch)

        #expect(state.selectedMode == .season)
        #expect(state.seasonFetchStatus == .fetched)
        #expect(state.seasons.map(\.tmdbID) == [611, 612])
        #expect(state.selectedSeasonIDs == Set([611]))
        #expect(service.batchRegisteredSeriesCount == 0)
        #expect(service.batchRegisteredSeasonCount == 1)
    }

    @MainActor
    @Test func testClearingBatchSessionUnregistersOnlyBatchOwnedSelections() async {
        let sharedMovie = makeEntryMetadata("Shared Movie", tmdbID: 701, type: .movie)
        let batchSeries = makeEntryMetadata("Batch Series", tmdbID: 702, type: .series)
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Shared": [sharedMovie]
                ],
                seriesByPrompt: [
                    "Shared": [batchSeries]
                ]
            )
        )

        service.register(info: sharedMovie)

        await service.performBatchSearch(input: "Shared", language: .english)

        #expect(service.registeredCount == 1)
        #expect(service.batchRegisteredCount == 2)

        service.clearBatchSession()

        #expect(service.registeredCount == 1)
        #expect(service.batchRegisteredCount == 0)
        #expect(service.isRegistered(info: sharedMovie))
        #expect(!service.isBatchSelected(info: sharedMovie))
        #expect(!service.isBatchSelected(info: batchSeries))
        #expect(service.batchResults.isEmpty)
        #expect(service.batchStatus == .idle)
    }

    @MainActor
    @Test func testSameNormalizedBatchInputReusesCachedResults() async {
        let recorder = SearchCallRecorder()
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [makeEntryMetadata("Frieren Movie", tmdbID: 801, type: .movie)],
                    "Spirited Away": [makeEntryMetadata("Spirited Away", tmdbID: 802, type: .movie)]
                ],
                recorder: recorder
            )
        )

        await service.performBatchSearch(input: "  Frieren  \n\nSpirited Away \n", language: .english)
        let firstCounts = await recorder.snapshot()

        await service.performBatchSearch(input: "Frieren\nSpirited Away", language: .english)
        let secondCounts = await recorder.snapshot()

        #expect(firstCounts == secondCounts)
        #expect(service.batchResults.map(\.prompt) == ["Frieren", "Spirited Away"])
    }

    @MainActor
    @Test func testSameNormalizedStructuredBatchInputReusesCachedResults() async {
        let recorder = SearchCallRecorder()
        let movie = makeEntryMetadata("Direct Movie", tmdbID: 4935, type: .movie)
        let series = makeEntryMetadata("Direct Series", tmdbID: 24835, type: .series)
        let service = TMDbSearchService(
            client: makeClient(
                directMoviesByID: [
                    4935: movie
                ],
                directSeriesByID: [
                    24835: series
                ],
                recorder: recorder
            )
        )

        await service.performBatchSearch(input: "  movie:4935  \n\nseries:24835 \n", language: .english)
        let firstCounts = await recorder.snapshot()

        await service.performBatchSearch(input: "movie:4935\nseries:24835", language: .english)
        let secondCounts = await recorder.snapshot()

        #expect(firstCounts == secondCounts)
        #expect(service.batchResults.map(\.prompt) == ["movie:4935", "series:24835"])
    }
}

private actor SearchCallRecorder {
    private(set) var movieCalls = 0
    private(set) var seriesCalls = 0
    private(set) var movieIDCalls = 0
    private(set) var seriesIDCalls = 0

    func recordMovie() {
        movieCalls += 1
    }

    func recordSeries() {
        seriesCalls += 1
    }

    func recordMovieID() {
        movieIDCalls += 1
    }

    func recordSeriesID() {
        seriesIDCalls += 1
    }

    func snapshot() -> SearchCallCounts {
        SearchCallCounts(
            movieCalls: movieCalls,
            seriesCalls: seriesCalls,
            movieIDCalls: movieIDCalls,
            seriesIDCalls: seriesIDCalls
        )
    }
}

fileprivate struct SearchCallCounts: Equatable {
    let movieCalls: Int
    let seriesCalls: Int
    let movieIDCalls: Int
    let seriesIDCalls: Int
}

fileprivate func makeClient(
    moviesByPrompt: [String: [EntryMetadata]] = [:],
    seriesByPrompt: [String: [EntryMetadata]] = [:],
    directMoviesByID: [Int: EntryMetadata?] = [:],
    directSeriesByID: [Int: EntryMetadata?] = [:],
    seasonsBySeriesID: [Int: [EntryMetadata]] = [:],
    directMovieErrorsByID: [Int: any Error] = [:],
    directSeriesErrorsByID: [Int: any Error] = [:],
    seasonErrorsBySeriesID: [Int: any Error] = [:],
    movieDelays: [String: UInt64] = [:],
    seriesDelays: [String: UInt64] = [:],
    recorder: SearchCallRecorder? = nil
) -> TMDbSearchClient {
    TMDbSearchClient(
        searchMovies: { query, _ in
            if let recorder {
                await recorder.recordMovie()
            }
            if let delay = movieDelays[query] {
                try? await Task.sleep(nanoseconds: delay)
            }
            return moviesByPrompt[query, default: []]
        },
        searchTVSeries: { query, _ in
            if let recorder {
                await recorder.recordSeries()
            }
            if let delay = seriesDelays[query] {
                try? await Task.sleep(nanoseconds: delay)
            }
            return seriesByPrompt[query, default: []]
        },
        fetchMovieByID: { tmdbID, _ in
            if let recorder {
                await recorder.recordMovieID()
            }
            if let error = directMovieErrorsByID[tmdbID] {
                throw error
            }
            return directMoviesByID[tmdbID] ?? nil
        },
        fetchTVSeriesByID: { tmdbID, _ in
            if let recorder {
                await recorder.recordSeriesID()
            }
            if let error = directSeriesErrorsByID[tmdbID] {
                throw error
            }
            return directSeriesByID[tmdbID] ?? nil
        },
        fetchSeasons: { seriesInfo, _ in
            if let error = seasonErrorsBySeriesID[seriesInfo.tmdbID] {
                throw error
            }
            return seasonsBySeriesID[seriesInfo.tmdbID, default: []]
        }
    )
}

fileprivate func makeEntryMetadata(_ name: String, tmdbID: Int, type: AnimeType) -> EntryMetadata {
    EntryMetadata(
        name: name,
        nameTranslations: [:],
        overview: nil,
        overviewTranslations: [:],
        posterURL: nil,
        tmdbID: tmdbID,
        onAirDate: nil,
        type: type
    )
}
