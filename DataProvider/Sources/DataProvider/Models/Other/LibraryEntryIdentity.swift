//
//  LibraryEntryIdentity.swift
//  DataProvider
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/19.
//

import Foundation

/// Stable identity for one library entry.
///
/// The identity is derived from AniShelf's entry type plus TMDb identifiers so
/// every device can address the same movie, series, or season entry without
/// depending on local SwiftData identifiers.
public struct LibraryEntryIdentity: Codable, Hashable, Sendable {
    public let rawID: String

    /// Creates the stable identity for a library entry.
    ///
    /// - Parameters:
    ///   - entryType: Entry kind and, for seasons, the parent series context.
    ///   - tmdbID: TMDb identifier for the concrete entry.
    public init(entryType: AnimeType, tmdbID: Int) {
        switch entryType {
        case .movie:
            rawID = "movie:\(tmdbID)"
        case .series:
            rawID = "series:\(tmdbID)"
        case .season(let seasonNumber, let parentSeriesID):
            rawID = "season:\(parentSeriesID):\(seasonNumber):\(tmdbID)"
        }
    }

    /// Extracts the concrete entry TMDb identifier from the stable identity.
    public var tmdbID: Int? {
        guard let suffix = rawID.split(separator: ":").last else {
            return nil
        }
        return Int(suffix)
    }
}

extension AnimeEntry {
    /// Stable identity for this local entry.
    public var libraryIdentity: LibraryEntryIdentity {
        LibraryEntryIdentity(entryType: type, tmdbID: tmdbID)
    }
}
