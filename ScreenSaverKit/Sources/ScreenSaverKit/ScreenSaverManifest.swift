//
//  ScreenSaverManifest.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation

public struct ScreenSaverManifest: Codable, Equatable, Sendable {
    // The schema version also keeps version 1 readers, which did not check rendererVersion, on the update notice.
    public static let currentSchemaVersion = 2
    public static let currentRendererVersion = 3

    public enum Layout: String, Codable, CaseIterable, Sendable {
        case coverWall
        case posterFocus
        case backdrop
    }

    /// Text a slide layout can show. Each layout draws the ones it is given in its own fixed order.
    public enum Detail: String, Codable, CaseIterable, Sendable {
        case title
        case season
        case year
        case genres
        case status

        public static func defaults(for layout: Layout) -> [Detail] {
            switch layout {
            // Cover Wall shows no text; with fewer than 4 posters it falls back to Poster Focus.
            case .coverWall, .posterFocus: [.title, .season, .year, .genres]
            case .backdrop: [.title, .year]
            }
        }

        /// One stable order, so equal selections encode to equal manifests.
        public static func normalized(_ details: some Sequence<Detail>) -> [Detail] {
            let selected = Set(details)
            return allCases.filter(selected.contains)
        }
    }

    public struct Settings: Codable, Equatable, Sendable {
        public static let defaultCoverWallRows = 4
        public static let coverWallRowRange = 2...8

        public let layout: Layout
        public let details: [Detail]
        public let interval: TimeInterval
        public let coverWallRows: Int

        public init(
            layout: Layout, details: [Detail]? = nil, interval: TimeInterval,
            coverWallRows: Int = Self.defaultCoverWallRows
        ) {
            self.layout = layout
            self.details = Detail.normalized(details ?? Detail.defaults(for: layout))
            self.interval = interval
            self.coverWallRows = min(
                max(coverWallRows, Self.coverWallRowRange.lowerBound), Self.coverWallRowRange.upperBound)
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                layout: try values.decode(Layout.self, forKey: .layout),
                // Unknown future details are dropped rather than failing the whole snapshot.
                details: try values.decodeIfPresent([String].self, forKey: .details)?.compactMap(Detail.init),
                interval: try values.decode(TimeInterval.self, forKey: .interval),
                coverWallRows: try values.decodeIfPresent(Int.self, forKey: .coverWallRows) ?? Self.defaultCoverWallRows
            )
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public struct PixelSize: Codable, Equatable, Sendable {
            public let width: Int
            public let height: Int

            public init(width: Int, height: Int) {
                self.width = width
                self.height = height
            }
        }

        public let id: String
        public let title: String?
        public let season: String?
        public let year: String?
        public let genres: [String]?
        public let status: String?
        public let poster: String
        public let posterPixelSize: PixelSize
        public let backdrop: String?
        public let logo: String?

        public init(
            id: String,
            title: String? = nil,
            season: String? = nil,
            year: String? = nil,
            genres: [String]? = nil,
            status: String? = nil,
            poster: String,
            posterPixelSize: PixelSize,
            backdrop: String? = nil,
            logo: String? = nil
        ) {
            self.id = id
            self.title = title
            self.season = season
            self.year = year
            self.genres = genres
            self.status = status
            self.poster = poster
            self.posterPixelSize = posterPixelSize
            self.backdrop = backdrop
            self.logo = logo
        }
    }

    public let schemaVersion: Int
    public let rendererVersion: Int?
    public let generation: UUID
    public let createdAt: Date
    public let settings: Settings
    public let entries: [Entry]

    public init(generation: UUID = UUID(), createdAt: Date = .now, settings: Settings, entries: [Entry]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.rendererVersion = Self.currentRendererVersion
        self.generation = generation
        // The snapshot wire format uses UTC ISO 8601 dates with second precision.
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
        self.settings = settings
        self.entries = entries
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
