//
//  UserEntryInfo.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/7/15.
//

import Foundation

/// Stores user-specific information about an entry.
public struct UserEntryInfo: Equatable, Codable {
    /// User's watch status for this entry.
    public var watchStatus: AnimeEntry.WatchStatus

    /// Date started watching.
    public var dateStarted: Date?

    /// Date marked finished.
    public var dateFinished: Date?

    /// Whether status changes should automatically manage tracking dates for this entry.
    public var isDateTrackingEnabled: Bool

    /// User's optional score for this entry.
    public var score: Int?

    /// Whether the entry is marked as favorite.
    public var favorite: Bool

    /// Notes for this entry.
    public var notes: String

    /// Whether the entry is using a custom poster image.
    public var usingCustomPoster: Bool

    private init(
        watchStatus: AnimeEntry.WatchStatus,
        dateStarted: Date? = nil,
        dateFinished: Date? = nil,
        isDateTrackingEnabled: Bool = true,
        score: Int? = nil,
        favorite: Bool,
        notes: String,
        usingCustomPoster: Bool
    ) {
        self.watchStatus = watchStatus
        self.dateStarted = dateStarted
        self.dateFinished = dateFinished
        self.isDateTrackingEnabled = isDateTrackingEnabled
        self.score = normalizedEntryScore(score)
        self.favorite = favorite
        self.notes = notes
        self.usingCustomPoster = usingCustomPoster
    }

    public init(from entry: AnimeEntry) {
        self.watchStatus = entry.watchStatus
        self.dateStarted = entry.dateStarted
        self.dateFinished = entry.dateFinished
        self.isDateTrackingEnabled = entry.isDateTrackingEnabled
        self.score = normalizedEntryScore(entry.score)
        self.favorite = entry.favorite
        self.notes = entry.notes
        self.usingCustomPoster = entry.usingCustomPoster
    }

    /// Whether this user info is "empty", i.e. has no meaningful user data.
    public var isEmpty: Bool {
        watchStatus == .planToWatch && dateStarted == nil && dateFinished == nil
            && isDateTrackingEnabled
            && score == nil && favorite == false && notes.isEmpty && usingCustomPoster == false
    }

    private enum CodingKeys: String, CodingKey {
        case watchStatus
        case dateStarted
        case dateFinished
        case isDateTrackingEnabled
        case score
        case favorite
        case notes
        case usingCustomPoster
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            watchStatus: try container.decode(AnimeEntry.WatchStatus.self, forKey: .watchStatus),
            dateStarted: try container.decodeIfPresent(Date.self, forKey: .dateStarted),
            dateFinished: try container.decodeIfPresent(Date.self, forKey: .dateFinished),
            isDateTrackingEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDateTrackingEnabled) ?? true,
            score: normalizedEntryScore(try container.decodeIfPresent(Int.self, forKey: .score)),
            favorite: try container.decode(Bool.self, forKey: .favorite),
            notes: try container.decode(String.self, forKey: .notes),
            usingCustomPoster: try container.decode(Bool.self, forKey: .usingCustomPoster)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watchStatus, forKey: .watchStatus)
        try container.encodeIfPresent(dateStarted, forKey: .dateStarted)
        try container.encodeIfPresent(dateFinished, forKey: .dateFinished)
        try container.encode(isDateTrackingEnabled, forKey: .isDateTrackingEnabled)
        try container.encodeIfPresent(normalizedEntryScore(score), forKey: .score)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(notes, forKey: .notes)
        try container.encode(usingCustomPoster, forKey: .usingCustomPoster)
    }
}

extension AnimeEntry.WatchStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .planToWatch: return "Planned"
        case .watching: return "Watching"
        case .watched: return "Watched"
        case .dropped: return "Dropped"
        }
    }
}

extension UserEntryInfo: CustomStringConvertible {
    public var description: String {
        """
        Status: \(watchStatus)
        Started: \(dateStarted?.description ?? "N/A")
        Finished: \(dateFinished?.description ?? "N/A")
        Track Dates: \(isDateTrackingEnabled)
        Score: \(score.map(String.init) ?? "No score")
        Favorite: \(favorite)
        Notes: \(notes)
        Custom Poster: \(usingCustomPoster)
        """
    }
}

extension AnimeEntry {
    public static let validScoreRange = 1...5

    public func setDateTrackingEnabled(_ isEnabled: Bool, now: Date = .now) {
        isDateTrackingEnabled = isEnabled
        guard isEnabled else { return }
        normalizeTrackingDates(now: now)
    }

    public func setWatchStatus(_ status: WatchStatus, now: Date = .now) {
        watchStatus = status
        guard isDateTrackingEnabled else { return }
        normalizeTrackingDates(now: now)
    }

    public func setScore(_ score: Int?) {
        self.score = normalizedEntryScore(score)
    }

    public func normalizeTrackingDates(now: Date = .now) {
        guard watchStatus != .dropped else { return }
        let normalizedDates = watchStatus.normalizedDates(
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            now: now
        )
        dateStarted = normalizedDates.dateStarted
        dateFinished = normalizedDates.dateFinished
    }

    public func updateUserInfo(from userInfo: UserEntryInfo) {
        watchStatus = userInfo.watchStatus
        dateStarted = userInfo.dateStarted
        dateFinished = userInfo.dateFinished
        isDateTrackingEnabled = userInfo.isDateTrackingEnabled
        score = normalizedEntryScore(userInfo.score)
        favorite = userInfo.favorite
        notes = userInfo.notes
        usingCustomPoster = userInfo.usingCustomPoster
        guard isDateTrackingEnabled else { return }
        normalizeTrackingDates()
    }
}

extension AnimeEntry.WatchStatus {
    public func normalizedDates(
        dateStarted: Date?,
        dateFinished: Date?,
        now: Date = .now
    ) -> (dateStarted: Date?, dateFinished: Date?) {
        switch self {
        case .planToWatch:
            return (nil, nil)
        case .watching:
            return (dateStarted ?? now, nil)
        case .watched:
            let finished = dateFinished ?? dateStarted ?? now
            let started = min(dateStarted ?? finished, finished)
            return (started, finished)
        case .dropped:
            switch (dateStarted, dateFinished) {
            case (nil, nil):
                return (nil, nil)
            case (.some(let started), nil):
                return (started, nil)
            case (nil, .some(let finished)):
                return (finished, finished)
            case (.some(let started), .some(let finished)):
                return (started, max(started, finished))
            }
        }
    }
}

fileprivate func normalizedEntryScore(_ score: Int?) -> Int? {
    guard let score else { return nil }
    return AnimeEntry.validScoreRange.contains(score) ? score : nil
}
