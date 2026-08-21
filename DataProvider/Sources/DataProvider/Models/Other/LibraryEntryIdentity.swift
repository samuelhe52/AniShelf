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
    public let entryType: AnimeType

    /// Parent-series TMDb identifier for a season identity.
    public var parentSeriesID: Int? { entryType.parentSeriesID }

    /// Creates the stable identity for a library entry.
    ///
    /// - Parameters:
    ///   - entryType: Entry kind and, for seasons, the parent series context.
    ///   - tmdbID: TMDb identifier for the concrete entry.
    public init(entryType: AnimeType, tmdbID: Int) {
        self.entryType = entryType
        switch entryType {
        case .movie:
            rawID = "movie:\(tmdbID)"
        case .series:
            rawID = "series:\(tmdbID)"
        case .season(let seasonNumber, let parentSeriesID):
            rawID = "season:\(parentSeriesID):\(seasonNumber):\(tmdbID)"
        }
    }

    /// Reconstructs a stable identity from its persisted raw representation.
    public init?(rawID: String) {
        let components = rawID.split(separator: ":", omittingEmptySubsequences: false)
        guard let kind = components.first else { return nil }

        switch kind {
        case "movie", "series":
            guard components.count == 2, let tmdbID = Int(components[1]) else { return nil }
            self.init(entryType: kind == "movie" ? .movie : .series, tmdbID: tmdbID)
        case "season":
            guard components.count == 4,
                let parentSeriesID = Int(components[1]),
                let seasonNumber = Int(components[2]),
                let tmdbID = Int(components[3])
            else { return nil }
            self.init(
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

    /// Extracts the concrete entry TMDb identifier from the stable identity.
    public var tmdbID: Int? {
        guard let suffix = rawID.split(separator: ":").last else {
            return nil
        }
        return Int(suffix)
    }

    private enum CodingKeys: String, CodingKey {
        case rawID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decode(String.self, forKey: .rawID)
        guard let identity = Self(rawID: rawID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawID,
                in: container,
                debugDescription: "Invalid library entry identity."
            )
        }
        self = identity
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawID, forKey: .rawID)
    }
}

extension AnimeEntry {
    /// Stable identity for this local entry.
    public var libraryIdentity: LibraryEntryIdentity {
        LibraryEntryIdentity(entryType: type, tmdbID: tmdbID)
    }
}
