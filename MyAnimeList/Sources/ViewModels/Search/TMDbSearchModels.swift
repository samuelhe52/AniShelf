//
//  TMDbSearchModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import DataProvider
import Foundation

struct SearchResult: Hashable, Sendable {
    var tmdbID: Int
    var type: AnimeType

    var libraryIdentity: LibraryEntryIdentity {
        LibraryEntryIdentity(entryType: type, tmdbID: tmdbID)
    }
}

extension EntryMetadata {
    var libraryIdentity: LibraryEntryIdentity {
        LibraryEntryIdentity(entryType: type, tmdbID: tmdbID)
    }
}

struct TMDbBatchPromptResult: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let prompt: String
    let series: EntryMetadata?
    let movie: EntryMetadata?
    var hasNoResults: Bool { series == nil && movie == nil }
    var allInfos: [EntryMetadata] { [series, movie].compactMap { $0 } }
}

enum TMDbBatchPrompt: Equatable, Sendable {
    case title(displayText: String)
    case movieID(displayText: String, tmdbID: Int)
    case seriesID(displayText: String, tmdbID: Int)
    case season(displayText: String, seriesTMDbID: Int, seasonNumber: Int)

    var displayText: String {
        switch self {
        case .title(let displayText),
            .movieID(let displayText, _),
            .seriesID(let displayText, _),
            .season(let displayText, _, _):
            displayText
        }
    }

    init(displayText: String) {
        self = Self.parse(displayText: displayText)
    }

    private static func parse(displayText: String) -> Self {
        let parts = displayText.split(separator: ":", omittingEmptySubsequences: false)

        if parts.count == 2,
            parts[0] == "movie",
            let tmdbID = parseInteger(parts[1])
        {
            return .movieID(displayText: displayText, tmdbID: tmdbID)
        }

        if parts.count == 2,
            parts[0] == "series",
            let tmdbID = parseInteger(parts[1])
        {
            return .seriesID(displayText: displayText, tmdbID: tmdbID)
        }

        if parts.count == 3,
            parts[0] == "season",
            let seriesTMDbID = parseInteger(parts[1]),
            let seasonNumber = parseInteger(parts[2])
        {
            return .season(
                displayText: displayText,
                seriesTMDbID: seriesTMDbID,
                seasonNumber: seasonNumber
            )
        }

        return .title(displayText: displayText)
    }

    private static func parseInteger(_ component: Substring) -> Int? {
        let text = String(component)
        guard !text.isEmpty else { return nil }

        let digitCharacters: Substring
        if text.hasPrefix("-") {
            digitCharacters = text.dropFirst()
        } else {
            digitCharacters = Substring(text)
        }

        guard !digitCharacters.isEmpty,
            digitCharacters.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 })
        else {
            return nil
        }

        return Int(text)
    }
}

enum TMDbSelectionContext: Sendable {
    case regular
    case batch
}

enum TMDbSeriesSelectionMode: CaseIterable, Equatable, Sendable {
    case series
    case season
}

enum TMDbSeasonFetchStatus: Equatable, Sendable {
    case notStarted
    case fetching
    case fetched
}

struct TMDbSeriesSelectionState: Equatable, Sendable {
    var selectedMode: TMDbSeriesSelectionMode = .series
    var seasons: [EntryMetadata] = []
    var seasonFetchStatus: TMDbSeasonFetchStatus = .notStarted
    var selectedSeasonIDs: Set<Int> = []
}
