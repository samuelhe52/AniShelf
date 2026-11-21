//
//  ScreenSaverDraft.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import Foundation

/// Layouts still being designed. They are not part of the manifest: only the Screen Saver Demo
/// plays them, over a real snapshot, so AniShelf and the installed saver never see them. A layout
/// moves into `ScreenSaverManifest.Layout` once its design is settled.
public enum ScreenSaverDraftLayout: String, CaseIterable, Sendable {
    /// Cards dealt off a fanned hand, title underneath.
    case deckFan
    /// A leaning pile seen head-on; the top card is tossed toward the viewer.
    case deckPile
    /// A still grid where single tiles flip to show another poster.
    case flipWall
    /// Poster Focus style: a full-height poster whose inner edge melts into a blur of itself.
    case coverFusion
    /// Posters along a line in chronological order, the one at the centre named.
    case timeline
    /// Posters floating upward at different depths; no text.
    case depthDrift
    /// A magazine cover: the title huge and ghosted, the poster over it, facts typeset beside.
    case editorialCover

    var isStage: Bool {
        switch self {
        case .deckFan, .deckPile, .flipWall, .timeline, .depthDrift: true
        case .coverFusion, .editorialCover: false
        }
    }
}

/// Playback overrides for the Screen Saver Demo. Every field is optional; an empty draft plays the
/// snapshot exactly as the saver would.
public struct ScreenSaverDraft: Equatable, Sendable {
    public enum TimelineDateSource: CaseIterable, Sendable {
        case airDate
        /// The watch start, or the end for an entry with only an end date. The caption shows the
        /// range, so its shape tells the two sources apart without a label.
        case watchDates

        /// The date the line sorts by.
        public func date(for entry: ScreenSaverManifest.Entry) -> Date? {
            switch self {
            case .airDate: entry.airDate
            case .watchDates: entry.watchStartDate ?? entry.watchEndDate
            }
        }

        var timeZone: TimeZone { self == .airDate ? .gmt : .current }
    }

    public enum TimelineDatePrecision: CaseIterable, Sendable {
        case year
        case yearAndMonth
        case fullDate

        func formatStyle(calendar: Calendar) -> Date.FormatStyle {
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            switch self {
            case .year: return style.year()
            case .yearAndMonth: return style.year().month(.abbreviated)
            case .fullDate: return style.year().month(.abbreviated).day()
            }
        }

        func intervalStyle(calendar: Calendar) -> Date.IntervalFormatStyle {
            let style = Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            switch self {
            case .year: return style.year()
            case .yearAndMonth: return style.year().month(.abbreviated)
            case .fullDate: return style.year().month(.abbreviated).day()
            }
        }
    }

    /// Plays a draft layout instead of `settings.layout`.
    public var layout: ScreenSaverDraftLayout?
    /// Replaces the snapshot's settings: details, interval, and rows apply to draft layouts too.
    public var settings: ScreenSaverManifest.Settings?
    /// Plays only this many entries, to try small libraries.
    public var entryLimit: Int?
    /// Fixes the shuffle so configurations can be compared on the same entries.
    public var seed: UInt64?
    /// Speeds every animation and pause up, to inspect motion quickly. 1 is real time.
    public var timeScale: Double = 1

    /// Flip Wall: seconds between two flips.
    public var flipDelay: TimeInterval = 3
    /// Depth Drift: posters started per 10 seconds.
    public var driftRate: Double = 4
    /// Deck: cards visible in the stack, the front one included.
    public var deckDepth: Int = 5
    /// Deck · Pile: cards visible in the pile, the front one included.
    public var pileDepth: Int = 7
    /// Timeline: seconds each poster rests at the centre after the pan.
    public var timelineHold: TimeInterval = 7
    public var timelineDateSource: TimelineDateSource = .airDate
    public var timelineDatePrecision: TimelineDatePrecision = .fullDate

    public init(
        layout: ScreenSaverDraftLayout? = nil, settings: ScreenSaverManifest.Settings? = nil, entryLimit: Int? = nil,
        seed: UInt64? = nil
    ) {
        self.layout = layout
        self.settings = settings
        self.entryLimit = entryLimit
        self.seed = seed
    }

    static let flipDelayRange: ClosedRange<TimeInterval> = 1...120
    static let driftRateRange: ClosedRange<Double> = 1...30
    static let deckDepthRange = 2...12
    static let timelineHoldRange: ClosedRange<TimeInterval> = 2...120
}

extension ClosedRange {
    func clamp(_ value: Bound) -> Bound { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
