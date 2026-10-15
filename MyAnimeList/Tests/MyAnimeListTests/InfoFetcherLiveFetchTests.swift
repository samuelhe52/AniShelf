//
//  InfoFetcherLiveFetchTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct InfoFetcherLiveFetchTests {
    let fetcher = InfoFetcher()
    let language: MyAnimeList.Language = .japanese

    @Test func testFetchInfo() async throws {
        let result = try await fetcher.searchTVSeries(name: "Frieren", language: language).first
        try #require(result != nil, "No search results for 'Frieren'")
        let info = try await fetcher.tvSeriesInfo(
            tmdbID: result!.id, language: language, posterLanguage: .originalLanguage)
        let entry = AnimeEntry(fromInfo: info)
        #expect(!entry.name.isEmpty)
    }

    @Test func testImageFetch() async throws {
        let result = try await fetcher.searchTVSeries(name: "CLANNAD", language: language).first
        try #require(result != nil, "No search results for 'CLANNAD'")
        let images = try await fetcher.tmdbClient.tvSeries.images(
            forTVSeries: result!.id,
            filter: TMDbImageFilters.tvSeries
        )
        let jaPosters = images.posters.filter { $0.languageCode == "ja" }
        #expect(!jaPosters.isEmpty, "Expected at least one Japanese poster")
    }
}
