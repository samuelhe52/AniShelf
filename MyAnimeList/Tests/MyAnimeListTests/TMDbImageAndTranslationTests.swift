//
//  TMDbImageAndTranslationTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Kingfisher
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

        let svgDetail = AnimeEntryDetail(
            language: "en-US",
            title: "SVG Logo Entry",
            logoImagePath: "/logo.svg"
        )
        #expect(svgDetail.logoImageURL?.absoluteString == "https://image.tmdb.org/t/p/original/logo.svg")
    }

    @Test func fetchDTOImageURLsResolveFromPathsBeforeLegacyURLs() throws {
        let legacyURL = try #require(URL(string: "https://example.com/legacy.jpg"))

        let detail = AnimeEntryDetailDTO(
            language: "en-US",
            title: "Path Detail",
            logoImageURL: legacyURL,
            logoImagePath: "/logos/title.png"
        )
        let character = AnimeEntryCharacterDTO(
            id: 1,
            characterName: "Character",
            actorName: "Actor",
            profileURL: legacyURL,
            profilePath: "/profiles/character.jpg"
        )
        let staff = AnimeEntryStaffDTO(
            id: 2,
            name: "Staff",
            role: "Director",
            profileURL: legacyURL,
            profilePath: "/profiles/staff.jpg"
        )
        let season = AnimeEntrySeasonSummaryDTO(
            id: 3,
            seasonNumber: 1,
            title: "Season 1",
            posterURL: legacyURL,
            posterPath: "/seasons/one.jpg"
        )
        let episode = AnimeEntryEpisodeSummaryDTO(
            id: 4,
            episodeNumber: 1,
            title: "Episode 1",
            imageURL: legacyURL,
            imagePath: "/episodes/still.jpg"
        )

        #expect(
            detail.resolvedLogoImageURL?.absoluteString
                == "https://image.tmdb.org/t/p/w500/logos/title.png"
        )
        #expect(
            AnimeEntryDetailDTO(
                language: "en-US",
                title: "SVG Path Detail",
                logoImagePath: "/logos/title.svg"
            ).resolvedLogoImageURL?.absoluteString
                == "https://image.tmdb.org/t/p/original/logos/title.svg"
        )
        #expect(
            character.resolvedProfileURL?.absoluteString
                == "https://image.tmdb.org/t/p/w185/profiles/character.jpg"
        )
        #expect(
            staff.resolvedProfileURL?.absoluteString
                == "https://image.tmdb.org/t/p/w185/profiles/staff.jpg"
        )
        #expect(
            season.resolvedPosterURL?.absoluteString
                == "https://image.tmdb.org/t/p/w342/seasons/one.jpg"
        )
        #expect(
            episode.resolvedImageURL?.absoluteString
                == "https://image.tmdb.org/t/p/original/episodes/still.jpg"
        )
    }

    @Test func fetchDTOImageURLsFallBackToLegacyURLsWhenPathIsMissing() throws {
        let legacyURL = try #require(URL(string: "https://example.com/legacy.jpg"))

        #expect(
            AnimeEntryCharacterDTO(
                id: 1,
                characterName: "Character",
                actorName: "Actor",
                profileURL: legacyURL
            ).resolvedProfileURL == legacyURL
        )
        #expect(
            AnimeEntrySeasonSummaryDTO(
                id: 2,
                seasonNumber: 1,
                title: "Season",
                posterURL: legacyURL
            ).resolvedPosterURL == legacyURL
        )
        #expect(
            AnimeEntryEpisodeSummaryDTO(
                id: 3,
                episodeNumber: 1,
                title: "Episode",
                imageURL: legacyURL
            ).resolvedImageURL == legacyURL
        )
    }

    @Test func lazySeasonEpisodeMappingUsesResolvedStillURL() {
        let card = SeriesSeasonEpisodeGroupView.episodeCard(
            from: AnimeEntryEpisodeSummaryDTO(
                id: 1,
                episodeNumber: 1,
                title: "The Still Path",
                imagePath: "/episodes/still.jpg"
            )
        )

        #expect(card.imageURL?.absoluteString == "https://image.tmdb.org/t/p/original/episodes/still.jpg")
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

    @Test func testSVGImageProcessorRasterizesInlineSVG() throws {
        let processor = SVGImageProcessor(
            targetSize: CGSize(width: 24, height: 24),
            scale: 2
        )
        let svgData = Data(
            #"""
            <svg width="12" height="12" viewBox="0 0 12 12" xmlns="http://www.w3.org/2000/svg">
              <rect width="12" height="12" fill="red"/>
            </svg>
            """#.utf8)

        let image = try #require(
            processor.process(
                item: .data(svgData),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            )
        )

        #expect(image.size == CGSize(width: 24, height: 24))
        #expect(image.scale == 2)
    }

    @Test func testSVGImageProcessorPreservesAspectRatioWithinTargetSize() throws {
        let processor = SVGImageProcessor(
            targetSize: CGSize(width: 24, height: 24),
            scale: 2
        )
        let wideSVGData = Data(
            #"""
            <svg width="120" height="40" viewBox="0 0 120 40" xmlns="http://www.w3.org/2000/svg">
              <rect width="120" height="40" fill="red"/>
            </svg>
            """#.utf8)
        let tallSVGData = Data(
            #"""
            <svg width="40" height="120" viewBox="0 0 40 120" xmlns="http://www.w3.org/2000/svg">
              <rect width="40" height="120" fill="blue"/>
            </svg>
            """#.utf8)

        let wideImage = try #require(
            processor.process(
                item: .data(wideSVGData),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            )
        )
        let tallImage = try #require(
            processor.process(
                item: .data(tallSVGData),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            )
        )

        #expect(wideImage.size == CGSize(width: 24, height: 8))
        #expect(tallImage.size == CGSize(width: 8, height: 24))
        #expect(wideImage.scale == 2)
        #expect(tallImage.scale == 2)
    }

    @Test func testSVGImageProcessorIdentifiersIncludeSizeAndScale() {
        let scaleTwo = SVGImageProcessor(targetSize: CGSize(width: 500, height: 500), scale: 2)
        let scaleThree = SVGImageProcessor(targetSize: CGSize(width: 500, height: 500), scale: 3)
        let intrinsic = SVGImageProcessor(scale: 3)

        #expect(scaleTwo.identifier != scaleThree.identifier)
        #expect(scaleThree.identifier != intrinsic.identifier)
    }

    @Test func testSVGImageProcessorRejectsInvalidData() {
        let processor = SVGImageProcessor(targetSize: CGSize(width: 24, height: 24), scale: 2)

        #expect(
            processor.process(
                item: .data(Data("not svg".utf8)),
                options: KingfisherParsedOptionsInfo([.processor(processor)])
            ) == nil
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

    @Test func displayPosterURLResolvesContextSizedRenditions() throws {
        let entry = AnimeEntry(
            name: "Display Poster Entry",
            type: .series,
            posterPath: "/poster.jpg",
            tmdbID: 12_801
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == false)
        #expect(
            snapshot.displayPosterURL(for: .list)?.absoluteString
                == "https://image.tmdb.org/t/p/w342/poster.jpg"
        )
        #expect(
            snapshot.displayPosterURL(for: .grid)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/poster.jpg"
        )
        #expect(
            snapshot.displayPosterURL(for: .gallery)?.absoluteString
                == "https://image.tmdb.org/t/p/original/poster.jpg"
        )
    }

    @Test func displayPosterURLHonorsCustomPosterSelection() throws {
        let entry = AnimeEntry(
            name: "Custom Poster Entry",
            type: .series,
            posterPath: "/default.jpg",
            customPosterPath: "/custom.jpg",
            tmdbID: 12_802,
            usingCustomPoster: true
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == false)
        #expect(
            snapshot.displayPosterURL(for: .grid)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/custom.jpg"
        )
    }

    @Test func displayPosterURLReportsMissingWhenNoSelectedPoster() throws {
        let entry = AnimeEntry(
            name: "No Poster Entry",
            type: .series,
            tmdbID: 12_803
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == true)
        #expect(snapshot.displayPosterURL(for: .gallery) == nil)
    }
}


fileprivate struct OptionalTranslationData: Codable, Equatable, Hashable, Sendable {
    let name: String?
    let overview: String?
}
