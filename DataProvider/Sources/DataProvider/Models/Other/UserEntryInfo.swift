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

    /// Whether the entry is marked as favorite.
    public var favorite: Bool

    /// Notes for this entry.
    public var notes: String

    /// Whether the entry is using a custom poster image.
    public var usingCustomPoster: Bool

    private init(
        watchStatus: AnimeEntry.WatchStatus, dateStarted: Date? = nil, dateFinished: Date? = nil,
        favorite: Bool, notes: String, usingCustomPoster: Bool
    ) {
        self.watchStatus = watchStatus
        self.dateStarted = dateStarted
        self.dateFinished = dateFinished
        self.favorite = favorite
        self.notes = notes
        self.usingCustomPoster = usingCustomPoster
    }

    public init(from entry: AnimeEntry) {
        self.watchStatus = entry.watchStatus
        self.dateStarted = entry.dateStarted
        self.dateFinished = entry.dateFinished
        self.favorite = entry.favorite
        self.notes = entry.notes
        self.usingCustomPoster = entry.usingCustomPoster
    }

    /// Whether this user info is "empty", i.e. has no meaningful user data.
    public var isEmpty: Bool {
        watchStatus == .planToWatch && dateStarted == nil && dateFinished == nil
            && favorite == false && notes.isEmpty && usingCustomPoster == false
    }
}

extension AnimeEntry.WatchStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .planToWatch: return "Plan to Watch"
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
        Favorite: \(favorite)
        Notes: \(notes)
        Custom Poster: \(usingCustomPoster)
        """
    }
}

extension AnimeEntry {
    public func setWatchStatus(_ status: WatchStatus, now: Date = .now) {
        watchStatus = status
        normalizeTrackingDates(now: now)
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
        favorite = userInfo.favorite
        notes = userInfo.notes
        usingCustomPoster = userInfo.usingCustomPoster
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
