//
//  ScrollState.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/4.
//

import Combine
import DataProvider
import Foundation

@Observable @MainActor
class ScrollState {
    var scrolledID: LibraryEntryIdentity? {
        didSet {
            writer.updateValue(scrolledID?.rawID)
        }
    }

    @ObservationIgnored private let writer: DebouncedStringUserDefaultsWriter

    init() {
        let persistedScrollPosition = UserDefaults.standard.string(forKey: .persistedScrolledID)
            .flatMap(Self.identity(from:))
        self.scrolledID = persistedScrollPosition
        self.writer = DebouncedStringUserDefaultsWriter(forKey: .persistedScrolledID)
    }

    private static func identity(from rawID: String) -> LibraryEntryIdentity? {
        let components = rawID.split(separator: ":")
        guard let kind = components.first else { return nil }

        switch kind {
        case "movie", "series":
            guard components.count == 2, let tmdbID = Int(components[1]) else { return nil }
            let type: AnimeType = kind == "movie" ? .movie : .series
            return LibraryEntryIdentity(entryType: type, tmdbID: tmdbID)
        case "season":
            guard components.count == 4,
                let parentSeriesID = Int(components[1]),
                let seasonNumber = Int(components[2]),
                let tmdbID = Int(components[3])
            else { return nil }
            return LibraryEntryIdentity(
                entryType: .season(
                    seasonNumber: seasonNumber,
                    parentSeriesID: parentSeriesID
                ),
                tmdbID: tmdbID
            )
        default:
            return nil
        }
    }
}
