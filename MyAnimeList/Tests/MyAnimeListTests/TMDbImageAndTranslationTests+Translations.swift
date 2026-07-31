//
//  TMDbImageAndTranslationTests+Translations.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import Kingfisher
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension TMDbImageAndTranslationTests {
    @Test func testMovieTranslationsMapTitleIntoNameDictionary() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 1,
                translations: [
                    Translation(
                        countryCode: "JP",
                        languageCode: "ja",
                        name: "Japanese",
                        englishName: "Japanese",
                        data: MovieTranslationData(title: "劇場版", overview: "映画の概要")
                    )
                ]
            )
        )

        #expect(result.name == ["ja-JP": "劇場版"])
        #expect(result.overview == ["ja-JP": "映画の概要"])
    }

    @Test func testTVSeriesTranslationsMapNameAndOverview() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 2,
                translations: [
                    Translation(
                        countryCode: "US",
                        languageCode: "en",
                        name: "English",
                        englishName: "English",
                        data: TVSeriesTranslationData(name: "Frieren", overview: "A journey continues")
                    )
                ]
            )
        )

        #expect(result.name == ["en-US": "Frieren"])
        #expect(result.overview == ["en-US": "A journey continues"])
    }

    @Test func testTVSeasonTranslationsMapNameAndOverview() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 3,
                translations: [
                    Translation(
                        countryCode: "TW",
                        languageCode: "zh",
                        name: "Traditional Chinese",
                        englishName: "Traditional Chinese",
                        data: TVSeasonTranslationData(name: "第一季", overview: "旅程開始")
                    )
                ]
            )
        )

        #expect(result.name == ["zh-TW": "第一季"])
        #expect(result.overview == ["zh-TW": "旅程開始"])
    }

    @Test func testTranslationDictionariesOmitMissingFields() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 4,
                translations: [
                    Translation(
                        countryCode: "JP",
                        languageCode: "ja",
                        name: "Japanese",
                        englishName: "Japanese",
                        data: OptionalTranslationData(name: nil, overview: "概要")
                    ),
                    Translation(
                        countryCode: "US",
                        languageCode: "en",
                        name: "English",
                        englishName: "English",
                        data: OptionalTranslationData(name: "Localized Title", overview: nil)
                    )
                ]
            ),
            name: { $0.name },
            overview: { $0.overview }
        )

        #expect(result.name == ["en-US": "Localized Title"])
        #expect(result.overview == ["ja-JP": "概要"])
    }

    @Test func testLenientTVSeriesTranslationDecoderAcceptsNullNameAndOverview() throws {
        let data = Data(
            #"""
            {
              "id": 35610,
              "translations": [
                {
                  "iso_3166_1": "JP",
                  "iso_639_1": "ja",
                  "name": "日本語",
                  "english_name": "Japanese",
                  "data": {
                    "name": "犬夜叉",
                    "overview": "戦国時代を巡る物語"
                  }
                },
                {
                  "iso_3166_1": "TW",
                  "iso_639_1": "zh",
                  "name": "普通话",
                  "english_name": "Mandarin",
                  "data": {
                    "name": null,
                    "overview": null,
                    "homepage": "",
                    "tagline": ""
                  }
                }
              ]
            }
            """#.utf8
        )

        let result = try fetcher.decodeLenientTranslationDictionaries(
            from: data,
            dataType: OptionalTranslationData.self,
            name: \.name,
            overview: \.overview
        )

        #expect(result.name == ["ja-JP": "犬夜叉"])
        #expect(result.overview == ["ja-JP": "戦国時代を巡る物語"])
    }

    @Test func testTVSeriesTranslationsFallbackReusesInjectedHTTPClient() async throws {
        let translationResponse = Data(
            #"""
            {
              "id": 35610,
              "translations": [
                {
                  "iso_3166_1": "JP",
                  "iso_639_1": "ja",
                  "name": "日本語",
                  "english_name": "Japanese",
                  "data": {
                    "name": "犬夜叉",
                    "overview": "戦国時代を巡る物語"
                  }
                },
                {
                  "iso_3166_1": "TW",
                  "iso_639_1": "zh",
                  "name": "普通话",
                  "english_name": "Mandarin",
                  "data": {
                    "name": null,
                    "overview": null,
                    "homepage": "",
                    "tagline": ""
                  }
                }
              ]
            }
            """#.utf8
        )
        let httpClient = RecordingTMDbHTTPClient { request in
            #expect(request.url.path == "/3/tv/35610/translations")
            return HTTPResponse(data: translationResponse)
        }
        let fetcher = InfoFetcher(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        )

        let result = try await fetcher.tvSeriesTranslations(tmdbID: 35_610)
        let requests = await httpClient.requests

        #expect(result.name == ["ja-JP": "犬夜叉"])
        #expect(result.overview == ["ja-JP": "戦国時代を巡る物語"])
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url.path == "/3/tv/35610/translations" })
        #expect(requests.allSatisfy { $0.url.queryValue(named: "api_key") == "test-key" })
    }

}

fileprivate struct OptionalTranslationData: Codable, Equatable, Hashable, Sendable {
    let name: String?
    let overview: String?
}
