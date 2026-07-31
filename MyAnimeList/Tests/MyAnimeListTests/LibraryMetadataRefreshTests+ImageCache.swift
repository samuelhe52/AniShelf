//
//  LibraryMetadataRefreshTests+ImageCache.swift
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

extension LibraryMetadataRefreshTests {
    @Test @MainActor func testLibraryImageCacheBuildsDefaultPrefetchTargetsWithoutLargeGalleryPoster()
        throws
    {
        let backdropURL = try #require(URL(string: "https://example.com/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))

        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterPath: "/poster.jpg",
                backdropURL: backdropURL,
                logoImageURL: logoURL,
                longTermGalleryPosterCachingEnabled: false
            )
        )

        let listPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg"))
        let gridPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))

        #expect(
            targets
                == Set([
                    .init(url: listPosterURL, targetSize: CGSize(width: 240, height: 360)),
                    .init(url: gridPosterURL, targetSize: CGSize(width: 360, height: 540)),
                    .init(url: backdropURL, targetSize: CGSize(width: 1_200, height: 675)),
                    .init(url: logoURL, targetSize: CGSize(width: 500, height: 500))
                ])
        )
    }

    @Test @MainActor func testLibraryImageCacheIncludesLargeGalleryPosterWhenEnabled() throws {
        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterPath: "/poster.jpg",
                backdropURL: nil,
                logoImageURL: nil,
                longTermGalleryPosterCachingEnabled: true
            )
        )

        let galleryPosterURL = try #require(
            URL(string: "https://image.tmdb.org/t/p/original/poster.jpg")
        )

        #expect(
            targets.contains(
                .init(url: galleryPosterURL, targetSize: CGSize(width: 1_000, height: 1_500))
            )
        )
    }

    @Test @MainActor func testLibraryImageCacheBuildsURLLevelPrefetchWorkItems() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))

        let targets = [
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 240, height: 360)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 360, height: 540)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: posterURL,
                targetSize: CGSize(width: 240, height: 360)
            ),
            LibraryImageCacheService.ImagePrefetchTarget(
                url: heroURL,
                targetSize: CGSize(width: 1_200, height: 675)
            )
        ]

        let workItems = LibraryImageCacheService.imagePrefetchWorkItems(from: targets)
            .sorted { $0.url.absoluteString < $1.url.absoluteString }

        #expect(workItems.count == 2)
        #expect(
            workItems
                == [
                    .init(
                        url: heroURL,
                        targetSizes: [CGSize(width: 1_200, height: 675)]
                    ),
                    .init(
                        url: posterURL,
                        targetSizes: [
                            CGSize(width: 240, height: 360),
                            CGSize(width: 360, height: 540)
                        ]
                    )
                ]
        )
    }

    @Test @MainActor func testLibraryImageCacheCollectsRelatedDetailURLs() throws {
        let posterURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/poster.jpg"))
        let listPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg"))
        let gridPosterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://image.tmdb.org/t/p/w1280/backdrop.jpg"))
        let logoURL = try #require(URL(string: "https://image.tmdb.org/t/p/w500/logo.png"))
        let characterURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/character.jpg"))
        let staffURL = try #require(URL(string: "https://image.tmdb.org/t/p/w185/staff.jpg"))
        let seasonURL = try #require(URL(string: "https://image.tmdb.org/t/p/w342/season.jpg"))
        let episodeURL = try #require(URL(string: "https://image.tmdb.org/t/p/original/episode.jpg"))

        let entry = AnimeEntry(
            name: "Cache Test",
            type: .series,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            tmdbID: 4
        )
        entry.detail = AnimeEntryDetail(
            language: "en",
            title: "Cache Test",
            logoImagePath: "/logo.png",
            characters: [
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Character",
                    actorName: "Actor",
                    profilePath: "/character.jpg"
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Director",
                    role: "Director",
                    profilePath: "/staff.jpg"
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 2,
                    seasonNumber: 1,
                    title: "Season",
                    posterPath: "/season.jpg"
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 3,
                    episodeNumber: 1,
                    title: "Episode",
                    imagePath: "/episode.jpg"
                )
            ]
        )

        let urls = LibraryImageCacheService.relatedImageURLs(for: entry)

        #expect(
            urls
                == Set([
                    posterURL,
                    listPosterURL,
                    gridPosterURL,
                    backdropURL,
                    logoURL,
                    characterURL,
                    staffURL,
                    seasonURL,
                    episodeURL
                ])
        )
    }

}
