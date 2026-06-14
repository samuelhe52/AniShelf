//
//  TMDbImageAndTranslationTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct TMDbImageAndTranslationTests {
    let fetcher = InfoFetcher()

    @Test func testTMDbImageFiltersUseSupportedLanguagesOnly() {
        #expect(TMDbImageFilters.supportedImageLanguageCodes == ["ja", "en", "zh"])
        #expect(TMDbImageFilters.movie.languages == ["ja", "en", "zh"])
        #expect(TMDbImageFilters.tvSeries.languages == ["ja", "en", "zh"])
        #expect(TMDbImageFilters.tvSeason.languages == ["ja", "en", "zh"])
    }

    @Test func testTMDbImageRequestsIncludeSupportedLanguagesAndNull() async throws {
        let httpClient = RecordingTMDbHTTPClient()
        let client = TMDbClient(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        )

        _ = try await client.movies.images(forMovie: 11, filter: TMDbImageFilters.movie)
        _ = try await client.tvSeries.images(forTVSeries: 22, filter: TMDbImageFilters.tvSeries)
        _ = try await client.tvSeasons.images(
            forSeason: 1,
            inTVSeries: 33,
            filter: TMDbImageFilters.tvSeason
        )

        let requests = await httpClient.requests
        #expect(
            requests.map(\.url.path)
                == ["/3/movie/11/images", "/3/tv/22/images", "/3/tv/33/season/1/images"]
        )
        #expect(
            requests.map { $0.url.queryValue(named: "include_image_language") }
                == ["ja,en,zh,null", "ja,en,zh,null", "ja,en,zh,null"]
        )
    }

    @Test func testPosterSelectionHandlesFilteredMixedLanguages() throws {
        let japanesePoster = URL(string: "/poster-ja.jpg")!
        let englishPoster = URL(string: "/poster-en.jpg")!
        let chinesePoster = URL(string: "/poster-zh.jpg")!
        let noLanguagePoster = URL(string: "/poster-none.jpg")!

        let selectedOriginalLanguagePoster = TMDbImageSelection.preferredPosterPath(
            from: [
                .init(languageCode: "en", filePath: englishPoster),
                .init(languageCode: nil, filePath: noLanguagePoster),
                .init(languageCode: "zh", filePath: chinesePoster),
                .init(languageCode: "ja", filePath: japanesePoster)
            ],
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )
        let selectedMetadataLanguagePoster = TMDbImageSelection.preferredPosterPath(
            from: [
                .init(languageCode: "en", filePath: englishPoster),
                .init(languageCode: nil, filePath: noLanguagePoster),
                .init(languageCode: "zh", filePath: chinesePoster)
            ],
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )
        let selectedNoLanguagePoster = TMDbImageSelection.preferredPosterPath(
            from: [
                .init(languageCode: "en", filePath: englishPoster),
                .init(languageCode: nil, filePath: noLanguagePoster)
            ],
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )

        #expect(selectedOriginalLanguagePoster == japanesePoster)
        #expect(selectedMetadataLanguagePoster == chinesePoster)
        #expect(selectedNoLanguagePoster == noLanguagePoster)
    }

    @Test func testFilteredResponseRestoresJapaneseOrNoLanguagePosterCandidates() throws {
        let englishPoster = makeImageMetadata(filePath: "/poster-en.jpg", width: 500, languageCode: "en")
        let japanesePoster = makeImageMetadata(filePath: "/poster-ja.jpg", width: 600, languageCode: "ja")
        let noLanguagePoster = makeImageMetadata(filePath: "/poster-none.jpg", width: 700, languageCode: nil)

        let unfilteredEquivalentPoster = TMDbImageSelection.preferredPosterPath(
            from: [englishPoster],
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )
        let filteredPoster = TMDbImageSelection.preferredPosterPath(
            from: [englishPoster, japanesePoster, noLanguagePoster],
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )

        #expect(unfilteredEquivalentPoster == nil)
        #expect(filteredPoster == japanesePoster.filePath)
        #expect(filteredPoster != nil)
    }

    @Test func testBackdropPrefersNoLanguageForSeries() throws {
        let localizedBackdrop = URL(string: "/localized-backdrop.jpg")!
        let noLanguageBackdrop = URL(string: "/no-language-backdrop.jpg")!
        let nilLanguageBackdrop = URL(string: "/nil-language-backdrop.jpg")!
        let fallbackBackdrop = URL(string: "/fallback-backdrop.jpg")!
        let imagesConfiguration = makeImagesConfiguration()

        let selectedPath = try #require(
            TMDbImageSelection.preferredBackdropPath(from: [
                .init(languageCode: "ja", filePath: localizedBackdrop),
                .init(languageCode: "xx", filePath: noLanguageBackdrop),
                .init(languageCode: nil, filePath: nilLanguageBackdrop),
                .init(languageCode: "en", filePath: fallbackBackdrop)
            ])
        )

        #expect(
            imagesConfiguration.backdropURL(for: selectedPath, idealWidth: 1_280)
                == imagesConfiguration.backdropURL(for: noLanguageBackdrop, idealWidth: 1_280)
        )
    }

    @Test func persistedEntryImageURLsUseExpectedRenditions() throws {
        let detail = AnimeEntryDetail(
            language: "en-US",
            title: "Image URL Entry",
            logoImagePath: "/logo.png"
        )
        let entry = AnimeEntry(
            name: "Image URL Entry",
            type: .series,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            tmdbID: 12_800,
            detail: detail
        )
        detail.entry = entry

        #expect(entry.posterURL?.absoluteString == "https://image.tmdb.org/t/p/original/poster.jpg")
        #expect(entry.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(entry.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(detail.heroImageURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(detail.logoImageURL?.absoluteString == "https://image.tmdb.org/t/p/w500/logo.png")
    }

    @Test func testPosterSelectionAllowsOnlyOriginalNoLanguageAndMetadataLanguage() throws {
        let englishPoster = URL(string: "https://example.com/poster-en.jpg")!
        let noLanguagePoster = URL(string: "https://example.com/poster-none.jpg")!
        let chinesePoster = URL(string: "https://example.com/poster-zh.jpg")!

        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [
                    .init(languageCode: "en", filePath: englishPoster),
                    .init(languageCode: nil, filePath: noLanguagePoster),
                    .init(languageCode: "zh", filePath: chinesePoster)
                ],
                originalLanguageCode: "zh",
                metadataLanguageCode: "en"
            ) == chinesePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [
                    .init(languageCode: "en", filePath: englishPoster),
                    .init(languageCode: nil, filePath: noLanguagePoster),
                    .init(languageCode: "zh", filePath: chinesePoster)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chinesePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [
                    .init(languageCode: "en", filePath: englishPoster),
                    .init(languageCode: "zh", filePath: chinesePoster)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chinesePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(from: [
                .init(languageCode: "en", filePath: englishPoster),
                .init(languageCode: nil, filePath: noLanguagePoster)
            ]) == noLanguagePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [.init(languageCode: "en", filePath: englishPoster)],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == nil
        )
    }

    @Test func testPosterPickerFallsBackToAllPostersWhenNoLanguageMatches() {
        let englishPoster = ImageURLWithMetadata(
            metadata: ImageMetadata(
                filePath: URL(string: "/poster-en.jpg")!,
                width: 500,
                height: 750,
                aspectRatio: 2.0 / 3.0,
                voteAverage: nil,
                voteCount: nil,
                languageCode: "en"
            ),
            url: URL(string: "https://example.com/poster-en.jpg")!
        )
        let koreanPoster = ImageURLWithMetadata(
            metadata: ImageMetadata(
                filePath: URL(string: "/poster-ko.jpg")!,
                width: 900,
                height: 1_350,
                aspectRatio: 2.0 / 3.0,
                voteAverage: nil,
                voteCount: nil,
                languageCode: "ko"
            ),
            url: URL(string: "https://example.com/poster-ko.jpg")!
        )

        let posters = [englishPoster, koreanPoster].filteredAndSorted(
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )

        #expect(posters.map(\.url) == [koreanPoster.url, englishPoster.url])
    }

    @Test func testLogoSelectionUsesNoLanguageAsFinalFallback() throws {
        let englishLogo = URL(string: "https://example.com/logo-en.png")!
        let noLanguageLogo = URL(string: "https://example.com/logo-none.png")!
        let chineseLogo = URL(string: "https://example.com/logo-zh.png")!
        let ignoredJPGLogo = URL(string: "https://example.com/logo-zh.jpg")!

        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "zh", filePath: ignoredJPGLogo),
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: nil, filePath: noLanguageLogo),
                    .init(languageCode: "zh", filePath: chineseLogo)
                ],
                originalLanguageCode: "zh",
                metadataLanguageCode: "en"
            ) == chineseLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: nil, filePath: noLanguageLogo),
                    .init(languageCode: "zh", filePath: chineseLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chineseLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: "zh", filePath: chineseLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chineseLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: nil, filePath: noLanguageLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "ko"
            ) == noLanguageLogo
        )
    }

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
