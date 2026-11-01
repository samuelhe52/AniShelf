//
//  EntryScore.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/18.
//

import Foundation

/// A user score from 1 to 5 in steps of 0.5, stored as half-star units.
///
/// Persistence keeps the whole stars in `score` and the half in `scoreHasHalf`.
public struct EntryScore: Hashable, Comparable, Sendable {
    /// Half-star units for 1 through 5.
    public static let validHalvesRange = 2...10
    /// Every valid score, lowest first.
    public static let all = validHalvesRange.compactMap(EntryScore.init(halves:))
    public static let lowest = EntryScore(uncheckedHalves: validHalvesRange.lowerBound)

    public let halves: Int

    public init?(halves: Int) {
        guard Self.validHalvesRange.contains(halves) else { return nil }
        self.halves = halves
    }

    /// Builds a score from its stored fields.
    ///
    /// Returns nil for a missing or out-of-range whole score. A half on 5 is dropped.
    public init?(whole: Int?, hasHalf: Bool = false) {
        guard let whole, AnimeEntry.validScoreRange.contains(whole) else { return nil }
        let halves = whole * 2 + (hasHalf ? 1 : 0)
        self.halves = min(halves, Self.validHalvesRange.upperBound)
    }

    private init(uncheckedHalves halves: Int) {
        self.halves = halves
    }

    /// The whole stars, stored as `score`.
    public var wholeStars: Int { halves / 2 }

    /// Whether the score has a half star, stored as `scoreHasHalf`.
    public var hasHalf: Bool { !halves.isMultiple(of: 2) }

    public var value: Double { Double(halves) / 2 }

    /// The score moved by `steps` half stars, or nil past either end.
    public func stepped(by steps: Int) -> EntryScore? {
        EntryScore(halves: halves + steps)
    }

    /// Display text such as "4" or "4.5", in the current locale.
    public var formatted: String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Locale-independent text such as "4" or "4.5", for exported files.
    public var exportString: String {
        hasHalf ? "\(wholeStars).5" : "\(wholeStars)"
    }

    public static func < (lhs: EntryScore, rhs: EntryScore) -> Bool {
        lhs.halves < rhs.halves
    }
}
