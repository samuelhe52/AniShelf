//
//  TMDbImagePathTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import DataProvider
import Foundation
import Testing

struct TMDbImagePathTests {
    @Test func storagePathStripsExplicitTMDbImageSizes() {
        #expect(
            TMDbImagePath.storagePath(
                from: url("https://image.tmdb.org/t/p/w185/profiles/frieren.jpg")
            ) == "/profiles/frieren.jpg"
        )
        #expect(
            TMDbImagePath.storagePath(
                from: url("https://image.tmdb.org/t/p/w500/logos/title.png")
            ) == "/logos/title.png"
        )
        #expect(
            TMDbImagePath.storagePath(
                from: url("https://image.tmdb.org/t/p/w1280/backdrops/hero.jpg")
            ) == "/backdrops/hero.jpg"
        )
        #expect(
            TMDbImagePath.storagePath(
                from: url("https://image.tmdb.org/t/p/original/episodes/still.jpg")
            ) == "/episodes/still.jpg"
        )
    }

    @Test func storagePathNormalizesRelativeFilePaths() {
        #expect(TMDbImagePath.storagePath(from: "/posters/default.jpg") == "/posters/default.jpg")
        #expect(TMDbImagePath.storagePath(from: "posters/default.jpg") == "/posters/default.jpg")
        #expect(TMDbImagePath.storagePath(from: "  /posters/default.jpg  ") == "/posters/default.jpg")
        #expect(TMDbImagePath.storagePath(from: "  ") == nil)
    }

    @Test func storagePathRejectsUnexpectedAbsoluteURLs() {
        #expect(
            TMDbImagePath.storagePath(
                from: url("https://example.com/posters/custom.jpg")
            ) == nil
        )
        #expect(
            TMDbImagePath.storagePath(
                from: url("https://image.tmdb.org/t/p")
            ) == nil
        )
    }

    @Test func animeEntryInitPreservesBasePosterPathWhenCustomPosterIsEnabled() {
        let entry = AnimeEntry(
            name: "Custom Poster Entry",
            type: .movie,
            posterPath: "/posters/base.jpg",
            customPosterPath: "/posters/custom.jpg",
            tmdbID: 77,
            usingCustomPoster: true
        )

        #expect(entry.posterPath == "/posters/base.jpg")
        #expect(entry.customPosterPath == "/posters/custom.jpg")
        #expect(entry.selectedPosterPath == "/posters/custom.jpg")
    }

    @Test func animeEntryUpdateCopiesCustomPosterSelectionState() {
        let source = AnimeEntry(
            name: "Source",
            type: .movie,
            posterPath: "/posters/base.jpg",
            customPosterPath: "/posters/custom.jpg",
            tmdbID: 78,
            usingCustomPoster: true
        )
        let destination = AnimeEntry(
            name: "Destination",
            type: .movie,
            posterPath: "/posters/old.jpg",
            tmdbID: 79,
            usingCustomPoster: false
        )

        destination.update(from: source)

        #expect(destination.posterPath == "/posters/base.jpg")
        #expect(destination.customPosterPath == "/posters/custom.jpg")
        #expect(destination.usingCustomPoster)
        #expect(destination.selectedPosterPath == "/posters/custom.jpg")
    }

    private func url(_ value: String) -> URL {
        URL(string: value)!
    }
}
