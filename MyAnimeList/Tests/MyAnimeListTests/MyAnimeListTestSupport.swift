//
//  MyAnimeListTestSupport.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import SwiftData
import Testing

import struct TMDb.ImagesConfiguration

@testable import DataProvider
@testable import MyAnimeList

func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}

@MainActor
func withRestoredLibrarySortingPreferences(_ body: () throws -> Void) throws {
    let defaults = UserDefaults.standard
    let keys = [
        String.libraryGroupStrategy,
        String.librarySortStrategy,
        String.librarySortReversed
    ]
    let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })

    defer {
        for key in keys {
            if let value = originalValues[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    try body()
}

func makeLibraryEntry(
    name: String,
    tmdbID: Int,
    watchStatus: AnimeEntry.WatchStatus = .planToWatch,
    daySaved: Int,
    score: Int? = nil,
    favorite: Bool = false
) -> AnimeEntry {
    let entry = AnimeEntry(
        name: name,
        type: .movie,
        tmdbID: tmdbID,
        dateSaved: referenceDate(year: 2026, month: 1, day: daySaved),
        score: score
    )
    entry.watchStatus = watchStatus
    entry.favorite = favorite
    return entry
}

func makeImagesConfiguration() -> ImagesConfiguration {
    ImagesConfiguration(
        baseURL: URL(string: "https://example.com/images/")!,
        secureBaseURL: URL(string: "https://example.com/images/")!,
        backdropSizes: ["w1280"],
        logoSizes: ["w500"],
        posterSizes: ["w780"],
        profileSizes: ["w185"],
        stillSizes: ["w300"]
    )
}

func temporaryStoreURL(name: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AniShelfTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory.appendingPathComponent("store.sqlite")
}

@MainActor
func makeWhatsNewController(
    defaults: UserDefaults,
    currentVersion: String,
    entries: [String: WhatsNewEntry]
) -> WhatsNewController {
    WhatsNewController(
        defaults: defaults,
        currentVersion: currentVersion,
        entryProvider: { entries[$0] }
    )
}

func makeWhatsNewEntry(version: String) -> WhatsNewEntry {
    WhatsNewEntry(
        version: version,
        title: "Version \(version)",
        summary: "Release summary",
        highlights: ["A highlight"],
        primaryAction: .init(
            id: "refresh",
            title: "Refresh Metadata",
            systemImage: "arrow.clockwise",
            kind: .refreshMetadata
        )
    )
}
