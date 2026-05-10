//
//  TMDbSearchServiceBatchTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
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

    @Test func testBatchPromptChunkingSplitsIntoBatchesOfEight() {
        let prompts = (1...17).map { "Prompt \($0)" }

        let chunks = TMDbSearchService.chunkedBatchPrompts(prompts)

        #expect(chunks.count == 3)
        #expect(chunks.map(\.count) == [8, 8, 1])
        #expect(chunks[0].first == "Prompt 1")
        #expect(chunks[2].first == "Prompt 17")
    }

    @MainActor
    @Test func testBatchSearchPreservesPromptOrderWhenAsyncCompletesOutOfOrder() async {
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "First": [makeInfo("First Movie", tmdbID: 101, type: .movie)],
                    "Second": [makeInfo("Second Movie", tmdbID: 201, type: .movie)],
                    "Third": [makeInfo("Third Movie", tmdbID: 301, type: .movie)]
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
                        makeInfo("Frieren Movie 1", tmdbID: 101, type: .movie),
                        makeInfo("Frieren Movie 2", tmdbID: 102, type: .movie)
                    ]
                ],
                seriesByPrompt: [
                    "Frieren": [
                        makeInfo("Frieren Series 1", tmdbID: 201, type: .series),
                        makeInfo("Frieren Series 2", tmdbID: 202, type: .series)
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
    @Test func testBatchSearchAutoSelectsNonDuplicateResultsInBatchStateOnly() async {
        let movie = makeInfo("Frieren Movie", tmdbID: 101, type: .movie)
        let series = makeInfo("Frieren Series", tmdbID: 201, type: .series)
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
        let duplicateMovie = makeInfo("Ghost in the Shell", tmdbID: 301, type: .movie)
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
        let regularMovie = makeInfo("Regular Movie", tmdbID: 401, type: .movie)
        let batchSeries = makeInfo("Batch Series", tmdbID: 402, type: .series)
        var submittedResults: [SearchResult] = []
        let service = TMDbSearchService(
            client: makeClient(
                seriesByPrompt: [
                    "Shared": [batchSeries]
                ]
            ),
            processResults: { submittedResults = Array($0) }
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
        let sharedSeries = makeInfo("Shared Series", tmdbID: 501, type: .series)
        let firstSeason = makeInfo(
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
        let sharedSeries = makeInfo("Frieren", tmdbID: 601, type: .series)
        let firstSeason = makeInfo(
            "Season 1",
            tmdbID: 611,
            type: .season(seasonNumber: 1, parentSeriesID: 601)
        )
        let secondSeason = makeInfo(
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
        let sharedMovie = makeInfo("Shared Movie", tmdbID: 701, type: .movie)
        let batchSeries = makeInfo("Batch Series", tmdbID: 702, type: .series)
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
                    "Frieren": [makeInfo("Frieren Movie", tmdbID: 801, type: .movie)],
                    "Spirited Away": [makeInfo("Spirited Away", tmdbID: 802, type: .movie)]
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
}

private actor SearchCallRecorder {
    private(set) var movieCalls = 0
    private(set) var seriesCalls = 0

    func recordMovie() {
        movieCalls += 1
    }

    func recordSeries() {
        seriesCalls += 1
    }

    func snapshot() -> (Int, Int) {
        (movieCalls, seriesCalls)
    }
}

fileprivate func makeClient(
    moviesByPrompt: [String: [BasicInfo]] = [:],
    seriesByPrompt: [String: [BasicInfo]] = [:],
    seasonsBySeriesID: [Int: [BasicInfo]] = [:],
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
        fetchSeasons: { seriesInfo, _ in
            seasonsBySeriesID[seriesInfo.tmdbID, default: []]
        }
    )
}

fileprivate func makeInfo(_ name: String, tmdbID: Int, type: AnimeType) -> BasicInfo {
    BasicInfo(
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
