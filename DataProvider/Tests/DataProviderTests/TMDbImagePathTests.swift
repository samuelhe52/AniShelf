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

    private func url(_ value: String) -> URL {
        URL(string: value)!
    }
}
