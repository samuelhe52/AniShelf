//
//  TMDbImageAndTranslationTests+ImageSelection.swift
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

    @Test func testLogoSelectionSupportsSVGWithPNGSameLanguageTieBreak() throws {
        let englishPNGLogo = URL(string: "https://example.com/logo-en.png")!
        let chineseSVGLogo = URL(string: "https://example.com/logo-zh.svg")!
        let chinesePNGLogo = URL(string: "https://example.com/logo-zh.png")!
        let japaneseSVGLogo = URL(string: "https://example.com/logo-ja.svg")!

        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishPNGLogo),
                    .init(languageCode: "zh", filePath: chineseSVGLogo)
                ],
                originalLanguageCode: "zh",
                metadataLanguageCode: "en"
            ) == chineseSVGLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "zh", filePath: chineseSVGLogo),
                    .init(languageCode: "zh", filePath: chinesePNGLogo)
                ],
                originalLanguageCode: "zh",
                metadataLanguageCode: "en"
            ) == chinesePNGLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishPNGLogo),
                    .init(languageCode: "ja", filePath: japaneseSVGLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "en"
            ) == japaneseSVGLogo
        )
    }

    @Test func testLiveLogoURLsUseOriginalForSVGAndRequestedSizeForPNG() async throws {
        let client = TMDbClient(
            apiKey: "test-key",
            httpClient: RecordingTMDbHTTPClient { request in
                if request.url.path == "/3/configuration" {
                    return HTTPResponse(
                        data: Data(
                            #"""
                            {
                              "images": {
                                "base_url": "http://image.tmdb.org/t/p/",
                                "secure_base_url": "https://image.tmdb.org/t/p/",
                                "backdrop_sizes": ["w1280", "original"],
                                "logo_sizes": ["w500", "original"],
                                "poster_sizes": ["w780", "original"],
                                "profile_sizes": ["w185", "original"],
                                "still_sizes": ["w300", "original"]
                              },
                              "change_keys": []
                            }
                            """#.utf8))
                }

                return HTTPResponse(
                    data: Data(
                        #"""
                        {
                          "id": 1,
                          "posters": [],
                          "backdrops": [],
                          "logos": [
                            {
                              "file_path": "/logo.png",
                              "width": 500,
                              "height": 200,
                              "aspect_ratio": 2.5,
                              "vote_average": 0,
                              "vote_count": 0,
                              "iso_639_1": "en"
                            },
                            {
                              "file_path": "/logo.svg",
                              "width": 500,
                              "height": 200,
                              "aspect_ratio": 2.5,
                              "vote_average": 0,
                              "vote_count": 0,
                              "iso_639_1": "en"
                            },
                            {
                              "file_path": "/logo.jpg",
                              "width": 500,
                              "height": 200,
                              "aspect_ratio": 2.5,
                              "vote_average": 0,
                              "vote_count": 0,
                              "iso_639_1": "en"
                            }
                          ]
                        }
                        """#.utf8))
            },
            configuration: .default
        )

        let urls = try await client.logoURLs(forMovie: 11, idealWidth: 500)
            .map(\.url.absoluteString)
            .sorted()

        #expect(
            urls == [
                "https://image.tmdb.org/t/p/original/logo.svg",
                "https://image.tmdb.org/t/p/w500/logo.png"
            ]
        )
    }

}
