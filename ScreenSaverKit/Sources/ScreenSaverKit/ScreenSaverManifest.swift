//
//  ScreenSaverManifest.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation

public struct ScreenSaverManifest: Codable, Equatable, Sendable {
    /// Readers accept only this version and ask for an update on a newer one. Changes to how the
    /// saver draws need no bump: the build ID below already catches those.
    public static let currentSchemaVersion = 3
    /// Info.plist key holding the saver's build ID: a hash of its source files, stamped by a build
    /// phase of the saver target. Any change to the saver's code gives a new ID.
    public static let buildInfoKey = "AniShelfScreenSaverBuild"

    public enum Layout: String, Codable, CaseIterable, Sendable {
        case coverWall
        case posterFocus
        case backdrop
    }

    /// Optional text a slide layout can show next to the title, which is always shown.
    /// Each layout draws the ones it is given in its own fixed order.
    public enum Detail: String, Codable, CaseIterable, Sendable {
        case season
        case year
        case genres
        /// The series' airing status, such as Returning Series or Ended.
        case status
        case score
        case watchStatus
        /// The user's own star score, such as "★ 4.5"; separate from TMDb's score.
        case userScore
        case overview

        public static func defaults(for layout: Layout) -> [Detail] {
            switch layout {
            // Cover Wall shows no text; with fewer than 4 posters it falls back to Poster Focus.
            case .coverWall, .posterFocus: [.season, .year, .genres]
            case .backdrop: [.year]
            }
        }

        public static func available(for layout: Layout) -> [Detail] {
            switch layout {
            case .coverWall, .posterFocus: allCases
            // A paragraph over a full-screen still is not readable from a distance.
            case .backdrop: allCases.filter { $0 != .overview }
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
        /// The flow speeds the settings offer, as multiples of the normal speed.
        public static let washSpeeds: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

        public let layout: Layout
        public let details: [Detail]
        public let interval: TimeInterval
        public let coverWallRows: Int
        /// Whether the colour wash behind Poster Focus drifts. Off, it holds still and only blends
        /// from one poster's colours to the next.
        public let washFlows: Bool
        /// How fast a flowing wash drifts, as a multiple of its normal speed.
        public let washSpeed: Double

        public init(
            layout: Layout, details: [Detail]? = nil, interval: TimeInterval,
            coverWallRows: Int = Self.defaultCoverWallRows, washFlows: Bool = true, washSpeed: Double = 1
        ) {
            self.washFlows = washFlows
            self.washSpeed = Self.washSpeeds.min { abs($0 - washSpeed) < abs($1 - washSpeed) } ?? 1
            self.layout = layout
            self.details = Detail.normalized(details ?? Detail.defaults(for: layout))
            self.interval = interval
            self.coverWallRows = min(
                max(coverWallRows, Self.coverWallRowRange.lowerBound), Self.coverWallRowRange.upperBound)
        }

        /// Every key is required: a snapshot from another build is refused by its build ID before
        /// it is decoded. Values still pass through `init`, which clamps and orders them.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                layout: try values.decode(Layout.self, forKey: .layout),
                details: try values.decode([Detail].self, forKey: .details),
                interval: try values.decode(TimeInterval.self, forKey: .interval),
                coverWallRows: try values.decode(Int.self, forKey: .coverWallRows),
                washFlows: try values.decode(Bool.self, forKey: .washFlows),
                washSpeed: try values.decode(Double.self, forKey: .washSpeed)
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
        /// Calendar date for Timeline ordering; the label follows the library's information language.
        public let airDate: Date?
        public let airDateLabel: String?
        public let genres: [String]?
        public let status: String?
        public let score: String?
        public let watchStatus: String?
        public let userScore: String?
        public let overview: String?
        public let poster: String
        public let posterPixelSize: PixelSize
        public let backdrop: String?
        public let logo: String?

        public init(
            id: String,
            title: String? = nil,
            season: String? = nil,
            year: String? = nil,
            airDate: Date? = nil,
            airDateLabel: String? = nil,
            genres: [String]? = nil,
            status: String? = nil,
            score: String? = nil,
            watchStatus: String? = nil,
            userScore: String? = nil,
            overview: String? = nil,
            poster: String,
            posterPixelSize: PixelSize,
            backdrop: String? = nil,
            logo: String? = nil
        ) {
            self.id = id
            self.title = title
            self.season = season
            self.year = year
            // Keep equality stable after the snapshot's whole-second ISO 8601 round trip.
            self.airDate = airDate.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970)) }
            self.airDateLabel = airDateLabel
            self.genres = genres
            self.status = status
            self.score = score
            self.watchStatus = watchStatus
            self.userScore = userScore
            self.overview = overview
            self.poster = poster
            self.posterPixelSize = posterPixelSize
            self.backdrop = backdrop
            self.logo = logo
        }
    }

    public let schemaVersion: Int
    public let generation: UUID
    public let createdAt: Date
    public let settings: Settings
    public let entries: [Entry]
    /// Build ID of the saver embedded in the AniShelf that wrote this snapshot. An installed saver
    /// with another ID is out of date and asks to be reinstalled.
    public let saverBuild: String?

    public init(
        generation: UUID = UUID(), createdAt: Date = .now, settings: Settings, entries: [Entry],
        saverBuild: String? = nil
    ) {
        self.saverBuild = saverBuild
        self.schemaVersion = Self.currentSchemaVersion
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
