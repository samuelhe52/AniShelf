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
        let targets = Set(
            LibraryImageCacheService.imagePrefetchTargets(
                posterPath: "/poster.jpg",
                backdropPath: "/backdrop.jpg",
                logoPath: "/logo.png",
                longTermGalleryPosterCachingEnabled: false
            )
        )

        #expect(
            targets
                == Set([
                    TMDbImage(path: "/poster.jpg", variant: .posterThumbnail),
                    TMDbImage(path: "/backdrop.jpg", variant: .backdrop),
                    TMDbImage(path: "/logo.png", variant: .logo)
                ].compactMap(\.self))
        )
        #expect(targets.count == 3)
    }

    @Test @MainActor func testLibraryImageCacheIncludesLargeGalleryPosterWhenEnabled() throws {
        let targets = LibraryImageCacheService.imagePrefetchTargets(
            posterPath: "/poster.jpg",
            backdropPath: nil,
            logoPath: nil,
            longTermGalleryPosterCachingEnabled: true
        )

        #expect(targets.map(\.variant) == [.posterThumbnail, .posterFull])
    }

    @Test @MainActor func testLibraryImageCacheBuildsURLLevelPrefetchWorkItems() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))

        let targets = try [
            (posterURL, TMDbImageVariant.posterThumbnail),
            (posterURL, .posterFull),
            (posterURL, .posterThumbnail),
            (heroURL, .backdrop)
        ].map { try #require(TMDbImage(fallbackURL: $0, variant: $1)) }

        let workItems = LibraryImageCacheService.imagePrefetchWorkItems(from: targets)
            .sorted { $0.url.absoluteString < $1.url.absoluteString }

        #expect(
            workItems
                == [
                    .init(url: heroURL, variants: [.backdrop]),
                    .init(url: posterURL, variants: [.posterThumbnail, .posterFull])
                ]
        )
    }

    @Test @MainActor func testLibraryImageCacheCollectsRelatedDetailCacheKeys() throws {
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

        let images: [TMDbImage] = try [
            ("w500/poster.jpg", .posterThumbnail),
            ("original/poster.jpg", .posterFull),
            ("w1280/backdrop.jpg", .backdrop),
            ("w500/logo.png", .logo),
            ("w185/character.jpg", .profile),
            ("w185/staff.jpg", .profile),
            ("w500/season.jpg", .posterThumbnail),
            ("w300/episode.jpg", .still)
        ].map { path, variant in
            try #require(
                TMDbImage(fallbackURL: URL(string: "https://image.tmdb.org/t/p/\(path)"), variant: variant)
            )
        }
        let unprocessedKeys = Set(images.map(\.url)).map {
            LibraryImageCacheService.CachedImageKey(url: $0, processorIdentifier: "")
        }

        #expect(
            LibraryImageCacheService.relatedCacheKeys(for: entry)
                == Set(images.map(LibraryImageCacheService.CachedImageKey.init(image:)))
                .union(unprocessedKeys)
        )
    }

    @Test @MainActor func testLibraryImageCacheCollectsPreviouslySelectedPosterCacheKeys() throws {
        let entry = AnimeEntry(
            name: "Custom Poster Cache Test",
            type: .movie,
            posterPath: "/default.jpg",
            customPosterPath: "/custom.jpg",
            tmdbID: 5,
            usingCustomPoster: true
        )

        #expect(
            Set(LibraryImageCacheService.relatedCacheKeys(for: entry).map(\.url))
                == Set([
                    URL(string: "https://image.tmdb.org/t/p/original/default.jpg")!,
                    URL(string: "https://image.tmdb.org/t/p/w500/default.jpg")!,
                    URL(string: "https://image.tmdb.org/t/p/original/custom.jpg")!,
                    URL(string: "https://image.tmdb.org/t/p/w500/custom.jpg")!
                ])
        )
    }

}
