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
        case deckFan
        case deckPile
        case flipWall
        case coverFusion
        case timeline
        case depthDrift
        case editorialCover

        public enum Control: Hashable, Sendable {
            case interval
            case rows
            case flowingBackground
            case deckDepth
            case pileDepth
            case flipDelay
            case timelineHold
            case timelineDateSource
            case timelineDatePrecision
            case driftRate
        }

        public var controls: [Control] { configuration.controls }

        fileprivate var configuration: (controls: [Control], details: [Detail]) {
            let allDetails = Detail.allCases
            let detailsWithoutOverview = allDetails.filter { $0 != .overview }
            return switch self {
            case .coverWall: ([.rows], [])
            case .posterFocus, .coverFusion, .editorialCover: ([.interval, .flowingBackground], allDetails)
            case .backdrop: ([.interval], detailsWithoutOverview)
            case .deckFan: ([.interval, .flowingBackground, .deckDepth], detailsWithoutOverview)
            case .deckPile: ([.interval, .flowingBackground, .pileDepth], detailsWithoutOverview)
            case .flipWall: ([.rows, .flipDelay], [])
            case .timeline:
                (
                    [.flowingBackground, .timelineDateSource, .timelineDatePrecision, .timelineHold],
                    detailsWithoutOverview.filter { $0 != .year }
                )
            case .depthDrift: ([.flowingBackground, .driftRate], [])
            }
        }

        /// The layout rendered when the source has this many posters.
        public func layout(forPosterCount count: Int) -> Self {
            self == .coverWall && count < 4 ? .posterFocus : self
        }

        /// Cover Wall stores Poster Focus's details for its small-library fallback.
        public var detailSelectionLayout: Self {
            self == .coverWall ? .posterFocus : self
        }
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
            if layout == .backdrop { return [.year] }
            let available = available(for: layout.detailSelectionLayout)
            return [Self.season, .year, .genres].filter(available.contains)
        }

        public static func available(for layout: Layout) -> [Detail] {
            layout.configuration.details
        }

        /// One stable order, so equal selections encode to equal manifests.
        public static func normalized(_ details: some Sequence<Detail>) -> [Detail] {
            let selected = Set(details)
            return allCases.filter(selected.contains)
        }
    }

    public enum TimelineDateSource: String, Codable, CaseIterable, Sendable {
        case airDate
        /// The watch start, or the end for an entry with only an end date.
        case watchDates

        public func date(for entry: Entry) -> Date? {
            date(airDate: entry.airDate, watchStartDate: entry.watchStartDate, watchEndDate: entry.watchEndDate)
        }

        public func date(airDate: Date?, watchStartDate: Date?, watchEndDate: Date?) -> Date? {
            switch self {
            case .airDate: airDate
            case .watchDates: watchStartDate ?? watchEndDate
            }
        }
    }

    public enum TimelineDatePrecision: String, Codable, CaseIterable, Sendable {
        case year
        case yearAndMonth
        case fullDate
    }

    public struct Settings: Codable, Equatable, Sendable {
        public static let defaultCoverWallRows = 4
        public static let coverWallRowRange = 2...8
        /// The flow speeds the settings offer, as multiples of the normal speed.
        public static let washSpeeds: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]
        public static let defaultFlipDelay: TimeInterval = 3
        public static let flipDelayRange: ClosedRange<TimeInterval> = 1...120
        public static let defaultDriftRate: Double = 4
        public static let driftRateRange: ClosedRange<Double> = 1...30
        public static let defaultDeckDepth = 5
        public static let defaultPileDepth = 7
        public static let deckDepthRange = 2...12
        public static let defaultTimelineHold: TimeInterval = 7
        public static let timelineHoldRange: ClosedRange<TimeInterval> = 2...120

        public let layout: Layout
        public let details: [Detail]
        public let interval: TimeInterval
        public let coverWallRows: Int
        /// Whether the colour wash drifts. Off, it holds still and only blends between colours.
        public let washFlows: Bool
        /// How fast a flowing wash drifts, as a multiple of its normal speed.
        public let washSpeed: Double
        /// Seconds between flips in Flip Wall.
        public let flipDelay: TimeInterval
        /// Posters started per ten seconds in Depth Drift.
        public let driftRate: Double
        public let deckDepth: Int
        public let pileDepth: Int
        /// Seconds each poster rests at the centre after the pan in Timeline.
        public let timelineHold: TimeInterval
        public let timelineDateSource: TimelineDateSource
        public let timelineDatePrecision: TimelineDatePrecision

        public init(
            layout: Layout, details: [Detail]? = nil, interval: TimeInterval,
            coverWallRows: Int = Self.defaultCoverWallRows, washFlows: Bool = true, washSpeed: Double = 1,
            flipDelay: TimeInterval = Self.defaultFlipDelay, driftRate: Double = Self.defaultDriftRate,
            deckDepth: Int = Self.defaultDeckDepth, pileDepth: Int = Self.defaultPileDepth,
            timelineHold: TimeInterval = Self.defaultTimelineHold, timelineDateSource: TimelineDateSource = .airDate,
            timelineDatePrecision: TimelineDatePrecision = .fullDate
        ) {
            self.washFlows = washFlows
            self.washSpeed = Self.washSpeeds.min { abs($0 - washSpeed) < abs($1 - washSpeed) } ?? 1
            self.layout = layout
            self.details = Detail.normalized(details ?? Detail.defaults(for: layout))
            // Between a second and an hour; 12 s if the value is not a number.
            self.interval = interval.isFinite ? min(max(interval, 1), 3_600) : 12
            self.coverWallRows = Self.coverWallRowRange.clamp(coverWallRows)
            self.flipDelay = Self.flipDelayRange.clamp(flipDelay.isFinite ? flipDelay : Self.defaultFlipDelay)
            self.driftRate = Self.driftRateRange.clamp(driftRate.isFinite ? driftRate : Self.defaultDriftRate)
            self.deckDepth = Self.deckDepthRange.clamp(deckDepth)
            self.pileDepth = Self.deckDepthRange.clamp(pileDepth)
            self.timelineHold =
                Self.timelineHoldRange.clamp(timelineHold.isFinite ? timelineHold : Self.defaultTimelineHold)
            self.timelineDateSource = timelineDateSource
            self.timelineDatePrecision = timelineDatePrecision
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
                washSpeed: try values.decode(Double.self, forKey: .washSpeed),
                flipDelay: try values.decode(TimeInterval.self, forKey: .flipDelay),
                driftRate: try values.decode(Double.self, forKey: .driftRate),
                deckDepth: try values.decode(Int.self, forKey: .deckDepth),
                pileDepth: try values.decode(Int.self, forKey: .pileDepth),
                timelineHold: try values.decode(TimeInterval.self, forKey: .timelineHold),
                timelineDateSource: try values.decode(TimelineDateSource.self, forKey: .timelineDateSource),
                timelineDatePrecision: try values.decode(TimelineDatePrecision.self, forKey: .timelineDatePrecision)
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
        /// Dates used for Timeline ordering. Air dates are TMDb calendar dates in UTC.
        public let airDate: Date?
        public let watchStartDate: Date?
        public let watchEndDate: Date?
        public let dateLocaleIdentifier: String?
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
            watchStartDate: Date? = nil,
            watchEndDate: Date? = nil,
            dateLocaleIdentifier: String? = nil,
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
            self.airDate = airDate.map(Self.wholeSeconds)
            self.watchStartDate = watchStartDate.map(Self.wholeSeconds)
            self.watchEndDate = watchEndDate.map(Self.wholeSeconds)
            self.dateLocaleIdentifier = dateLocaleIdentifier
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

        private static func wholeSeconds(_ date: Date) -> Date {
            Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
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

extension ClosedRange {
    fileprivate func clamp(_ value: Bound) -> Bound { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
