//
//  EntryOpenInLinksTests.swift
//  MyAnimeListTests
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/20.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

@MainActor
struct EntryOpenInLinksTests {
    @Test func testInfuseSeasonLinkTargetsParentSeriesSeason() {
        let url = EntryOpenInLinks.infuseURL(
            type: .season(seasonNumber: 2, parentSeriesID: 209867),
            tmdbID: 420001
        )

        #expect(url?.absoluteString == "infuse://series/209867-2")
    }

    @Test func testKazumiSearchEncodesPunctuationForFormStyleDecoding() {
        let url = EntryOpenInLinks.kazumiURL(query: "BLOOD+ & Re:Zero")

        #expect(url?.absoluteString == "kazumi://search?query=BLOOD%2B%20%26%20Re:Zero")
    }

    @Test func testBilibiliSearchUsesPlatformDestinationAndEncodesQuery() {
        let url = EntryOpenInLinks.bilibiliURL(query: " 葬送 +&# ")
        #if os(macOS)
            let base = "https://search.bilibili.com/all"
        #else
            let base = "bilibili://search/"
        #endif
        #expect(url?.absoluteString == "\(base)?keyword=%E8%91%AC%E9%80%81%20%2B%26%23")
        #expect(EntryOpenInLinks.bilibiliURL(query: " \n ") == nil)
    }

    @Test func testKazumiSearchUsesEncodedChineseSeriesTitle() {
        let series = AnimeEntry(
            name: "Frieren: Beyond Journey's End",
            nameTranslations: ["en-US": "Frieren", "ja-JP": "葬送のフリーレン", "zh-CN": "葬送的芙莉莲"],
            type: .series,
            tmdbID: 209867
        )
        let season = AnimeEntry(
            name: "Season 2",
            nameTranslations: ["zh-CN": "第 2 季"],
            type: .season(seasonNumber: 2, parentSeriesID: 209867),
            tmdbID: 420001
        )
        season.parentSeriesEntry = series

        let links = EntryOpenInLinks(entry: season, homepageURL: nil)

        #expect(
            links.kazumiURL?.absoluteString
                == "kazumi://search?query=%E8%91%AC%E9%80%81%E7%9A%84%E8%8A%99%E8%8E%89%E8%8E%B2"
        )
        #expect(links.url(for: .bilibili) == EntryOpenInLinks.bilibiliURL(query: "葬送的芙莉莲"))
    }

    @Test func testSwipeDestinationRawValuesStayStableAndDeviceLocal() {
        #expect(EntryOpenInSwipeDestination.allCases.map(\.rawValue) == ["ask", "infuse", "kazumi", "bilibili"])
        #expect(EntryOpenInSwipeDestination(rawValue: "kazumi") == .app(.kazumi))
        #expect(EntryOpenInSwipeDestination(rawValue: "bilibili") == .app(.bilibili))
        #expect(EntryOpenInSwipeDestination(rawValue: "removedFutureApp") == nil)

        #expect(!String.allPreferenceKeys.contains(.libraryOpenInSwipeDestination))
        #expect(!String.cloudSyncedPreferenceKeys.contains(.libraryOpenInSwipeDestination))
    }
}
