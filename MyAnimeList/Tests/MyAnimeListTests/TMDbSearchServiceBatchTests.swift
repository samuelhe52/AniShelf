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
    @Test func testBatchSearchAutoRegistersNonDuplicateResults() async {
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [makeInfo("Frieren Movie", tmdbID: 101, type: .movie)]
                ],
                seriesByPrompt: [
                    "Frieren": [makeInfo("Frieren Series", tmdbID: 201, type: .series)]
                ]
            )
        )

        await service.performBatchSearch(input: "Frieren", language: .english)

        #expect(service.registeredCount == 2)
        #expect(service.isRegistered(info: makeInfo("Frieren Movie", tmdbID: 101, type: .movie)))
        #expect(service.isRegistered(info: makeInfo("Frieren Series", tmdbID: 201, type: .series)))
    }

    @MainActor
    @Test func testBatchSearchLeavesDuplicatesVisibleButUnregistered() async {
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
        #expect(service.registeredCount == 0)
        #expect(!service.isRegistered(info: duplicateMovie))
    }

    @MainActor
    @Test func testClearingBatchSessionUnregistersOnlyBatchOwnedSelections() async {
        let sharedMovie = makeInfo("Shared Movie", tmdbID: 401, type: .movie)
        let batchSeries = makeInfo("Batch Series", tmdbID: 402, type: .series)
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

        #expect(service.registeredCount == 2)

        service.clearBatchSession()

        #expect(service.registeredCount == 1)
        #expect(service.isRegistered(info: sharedMovie))
        #expect(!service.isRegistered(info: batchSeries))
        #expect(service.batchResults.isEmpty)
        #expect(service.batchStatus == .idle)
    }

    @MainActor
    @Test func testSameNormalizedBatchInputReusesCachedResults() async {
        let recorder = SearchCallRecorder()
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [makeInfo("Frieren Movie", tmdbID: 501, type: .movie)],
                    "Spirited Away": [makeInfo("Spirited Away", tmdbID: 502, type: .movie)]
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
        fetchSeasons: { _, _ in [] }
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
