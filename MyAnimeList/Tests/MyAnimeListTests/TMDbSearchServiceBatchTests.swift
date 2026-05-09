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
    @Test func testBatchSearchShapesResultsAndAutoSelectsInPromptOrder() async {
        var submittedResults: [SearchResult] = []
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: [
                    "Frieren": [makeInfo("Frieren Movie", tmdbID: 101, type: .movie)],
                    "Spirited Away": [makeInfo("Spirited Away", tmdbID: 201, type: .movie)],
                ],
                seriesByPrompt: [
                    "Frieren": [makeInfo("Frieren", tmdbID: 100, type: .series)]
                ]
            ),
            processResults: { submittedResults = Array($0) }
        )

        await service.performBatchSearch(
            input: "Frieren\nSpirited Away\nMissing Title",
            language: .english
        )

        #expect(service.batchResults.map(\.prompt) == ["Frieren", "Spirited Away", "Missing Title"])
        #expect(service.batchResults[0].series?.tmdbID == 100)
        #expect(service.batchResults[0].movie?.tmdbID == 101)
        #expect(service.batchResults[1].series == nil)
        #expect(service.batchResults[1].movie?.tmdbID == 201)
        #expect(service.batchResults[2].hasNoResults)
        #expect(service.registeredCount == 3)

        service.submit()

        #expect(
            submittedResults == [
                SearchResult(tmdbID: 100, type: .series),
                SearchResult(tmdbID: 101, type: .movie),
                SearchResult(tmdbID: 201, type: .movie),
            ]
        )
    }

    @MainActor
    @Test func testBatchSearchShowsDuplicatesWithoutAutoRegistering() async {
        var submittedResults: [SearchResult] = []
        let duplicateMovie = makeInfo("Ghost in the Shell", tmdbID: 301, type: .movie)
        let service = TMDbSearchService(
            client: makeClient(
                moviesByPrompt: ["Ghost in the Shell": [duplicateMovie]]
            ),
            checkDuplicate: { $0 == 301 },
            processResults: { submittedResults = Array($0) }
        )

        await service.performBatchSearch(
            input: "Ghost in the Shell",
            language: .english
        )

        #expect(service.batchResults.count == 1)
        #expect(service.batchResults[0].movie?.tmdbID == 301)
        #expect(service.registeredCount == 0)
        #expect(!service.isRegistered(info: duplicateMovie))

        service.submit()

        #expect(submittedResults.isEmpty)
    }
}

private func makeClient(
    moviesByPrompt: [String: [BasicInfo]] = [:],
    seriesByPrompt: [String: [BasicInfo]] = [:]
) -> TMDbSearchClient {
    TMDbSearchClient(
        searchMovies: { query, _ in moviesByPrompt[query, default: []] },
        searchTVSeries: { query, _ in seriesByPrompt[query, default: []] },
        fetchSeasons: { _, _ in [] }
    )
}

private func makeInfo(_ name: String, tmdbID: Int, type: AnimeType) -> BasicInfo {
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
