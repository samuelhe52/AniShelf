//
//  EntryDetailViewModelTests+SeasonEpisodes.swift
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

extension EntryDetailViewModelTests {
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

}
