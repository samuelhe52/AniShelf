//
//  UserEntryInfo.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/7/15.
//

import Foundation

/// Stores user-specific information about an entry.
public struct UserEntryInfo: Equatable, Codable {
    public struct EpisodeProgressSnapshot: Equatable, Codable {
        public var seasonNumber: Int
        public var watchedThroughEpisode: Int
        public var updatedAt: Date

        public init(
            seasonNumber: Int,
            watchedThroughEpisode: Int,
            updatedAt: Date = .now
        ) {
            self.seasonNumber = seasonNumber
            self.watchedThroughEpisode = max(0, watchedThroughEpisode)
            self.updatedAt = updatedAt
        }
    }

    /// User's watch status for this entry.
    public var watchStatus: AnimeEntry.WatchStatus

    /// Date started watching.
    public var dateStarted: Date?

    /// Date marked finished.
    public var dateFinished: Date?

    /// Whether date controls are shown for this entry.
    public var isDateTrackingEnabled: Bool

    /// User's optional score for this entry.
    public var score: Int?

    /// Whether the entry is marked as favorite.
    public var favorite: Bool

    /// Notes for this entry.
    public var notes: String

    /// Whether the entry is using a custom poster image.
    public var usingCustomPoster: Bool

    /// Episode progress grouped by season/special partition.
    public var episodeProgresses: [EpisodeProgressSnapshot]

    private init(
        watchStatus: AnimeEntry.WatchStatus,
        dateStarted: Date? = nil,
        dateFinished: Date? = nil,
        isDateTrackingEnabled: Bool = true,
        score: Int? = nil,
        favorite: Bool,
        notes: String,
        usingCustomPoster: Bool,
        episodeProgresses: [EpisodeProgressSnapshot] = []
    ) {
        self.watchStatus = watchStatus
        self.dateStarted = dateStarted
        self.dateFinished = dateFinished
        self.isDateTrackingEnabled = isDateTrackingEnabled
        self.score = normalizedEntryScore(score)
        self.favorite = favorite
        self.notes = notes
        self.usingCustomPoster = usingCustomPoster
        self.episodeProgresses = Self.normalizedEpisodeProgresses(episodeProgresses)
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
        self.episodeProgresses = Self.normalizedEpisodeProgresses(
            entry.orderedEpisodeProgresses.map {
                EpisodeProgressSnapshot(
                    seasonNumber: $0.seasonNumber,
                    watchedThroughEpisode: $0.watchedThroughEpisode,
                    updatedAt: $0.updatedAt
                )
            }
        )
    }

    /// Whether this user info is "empty", i.e. has no meaningful user data.
    public var isEmpty: Bool {
        watchStatus == .planToWatch && dateStarted == nil && dateFinished == nil
            && isDateTrackingEnabled
            && score == nil && favorite == false && notes.isEmpty && usingCustomPoster == false
            && episodeProgresses.isEmpty
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
        case episodeProgresses
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
            usingCustomPoster: try container.decode(Bool.self, forKey: .usingCustomPoster),
            episodeProgresses: try container.decodeIfPresent(
                [EpisodeProgressSnapshot].self,
                forKey: .episodeProgresses
            ) ?? []
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
        try container.encode(episodeProgresses, forKey: .episodeProgresses)
    }

    fileprivate static func normalizedEpisodeProgresses(
        _ episodeProgresses: [EpisodeProgressSnapshot]
    ) -> [EpisodeProgressSnapshot] {
        Dictionary(
            grouping: episodeProgresses.filter {
                $0.seasonNumber > 0 && $0.watchedThroughEpisode > 0
            },
            by: \.seasonNumber
        )
        .values
        .compactMap { progresses in
            progresses.max { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.watchedThroughEpisode < rhs.watchedThroughEpisode
                }
                return lhs.updatedAt < rhs.updatedAt
            }
        }
        .sorted { lhs, rhs in
            let lhsKey = lhs.seasonNumber == 0 ? Int.max : lhs.seasonNumber
            let rhsKey = rhs.seasonNumber == 0 ? Int.max : rhs.seasonNumber
            if lhsKey == rhsKey {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhsKey < rhsKey
        }
    }

    public func isSemanticallyEquivalent(to other: UserEntryInfo) -> Bool {
        watchStatus == other.watchStatus
            && dateStarted == other.dateStarted
            && dateFinished == other.dateFinished
            && isDateTrackingEnabled == other.isDateTrackingEnabled
            && score == other.score
            && favorite == other.favorite
            && notes == other.notes
            && usingCustomPoster == other.usingCustomPoster
            && semanticEpisodeProgresses == other.semanticEpisodeProgresses
    }

    private var semanticEpisodeProgresses: [EpisodeProgressValue] {
        episodeProgresses.map(EpisodeProgressValue.init)
    }

    private struct EpisodeProgressValue: Equatable {
        let seasonNumber: Int
        let watchedThroughEpisode: Int

        init(_ snapshot: EpisodeProgressSnapshot) {
            seasonNumber = snapshot.seasonNumber
            watchedThroughEpisode = snapshot.watchedThroughEpisode
        }
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
        Episode Progress: \(Self.episodeProgressDescription(episodeProgresses))
        """
    }

    private static func episodeProgressDescription(
        _ episodeProgresses: [EpisodeProgressSnapshot]
    ) -> String {
        guard !episodeProgresses.isEmpty else { return "None" }
        return
            episodeProgresses
            .map { progress in
                let prefix = progress.seasonNumber == 0 ? "SP" : "S\(progress.seasonNumber)"
                return "\(prefix): \(progress.watchedThroughEpisode)"
            }
            .joined(separator: ", ")
    }
}

extension AnimeEntry {
    public static let validScoreRange = 1...5

    /// Advances the library-domain sync clock without touching tracking state.
    public func markLibraryModified(at date: Date = .now) {
        libraryUpdatedAt = date
    }

    /// Advances the tracking-domain sync clock without mutating user fields.
    public func markTrackingModified(at date: Date = .now) {
        trackingUpdatedAt = date
    }

    /// Seeds the library-domain sync clock for a newly saved entry.
    public func markCreatedForLibrary(at date: Date = .now) {
        libraryUpdatedAt = date
    }

    /// User-facing display toggle that also advances `libraryUpdatedAt`.
    public func updateDisplayState(_ isOnDisplay: Bool, at date: Date = .now) {
        onDisplay = isOnDisplay
        markLibraryModified(at: date)
    }

    /// Low-level setter that does not advance `trackingUpdatedAt`.
    ///
    /// Use `updateDateTrackingEnabled(_:at:)` for user actions that should
    /// participate in sync conflict resolution.
    public func setDateTrackingEnabled(_ isEnabled: Bool) {
        isDateTrackingEnabled = isEnabled
    }

    @discardableResult
    public func updateDateTrackingEnabled(_ isEnabled: Bool, at date: Date = .now) -> Bool {
        guard isDateTrackingEnabled != isEnabled else { return false }
        setDateTrackingEnabled(isEnabled)
        markTrackingModified(at: date)
        return true
    }

    /// Low-level setter that does not advance `trackingUpdatedAt`.
    ///
    /// Use `updateWatchStatus(_:at:)` for user actions that should participate
    /// in sync conflict resolution.
    public func setWatchStatus(_ status: WatchStatus) {
        watchStatus = status
    }

    @discardableResult
    public func updateWatchStatus(_ status: WatchStatus, at date: Date = .now) -> Bool {
        guard watchStatus != status else { return false }
        setWatchStatus(status)
        markTrackingModified(at: date)
        return true
    }

    /// Low-level setter that does not advance `trackingUpdatedAt`.
    ///
    /// Use `updateScore(_:at:)` for user actions that should participate in
    /// sync conflict resolution.
    public func setScore(_ score: Int?) {
        self.score = normalizedEntryScore(score)
    }

    @discardableResult
    public func updateScore(_ score: Int?, at date: Date = .now) -> Bool {
        let normalizedScore = normalizedEntryScore(score)
        guard self.score != normalizedScore else { return false }
        self.score = normalizedScore
        markTrackingModified(at: date)
        return true
    }

    @discardableResult
    public func updateFavorite(_ isFavorite: Bool, at date: Date = .now) -> Bool {
        guard favorite != isFavorite else { return false }
        favorite = isFavorite
        markTrackingModified(at: date)
        return true
    }

    public func toggleFavorite(at date: Date = .now) {
        updateFavorite(!favorite, at: date)
    }

    @discardableResult
    public func updateNotes(_ notes: String, at date: Date = .now) -> Bool {
        guard self.notes != notes else { return false }
        self.notes = notes
        markTrackingModified(at: date)
        return true
    }

    @discardableResult
    public func updateDateStarted(_ dateStarted: Date?, at date: Date = .now) -> Bool {
        guard self.dateStarted != dateStarted else { return false }
        self.dateStarted = dateStarted
        markTrackingModified(at: date)
        return true
    }

    @discardableResult
    public func updateDateFinished(_ dateFinished: Date?, at date: Date = .now) -> Bool {
        guard self.dateFinished != dateFinished else { return false }
        self.dateFinished = dateFinished
        markTrackingModified(at: date)
        return true
    }

    @discardableResult
    public func updateCustomPosterURL(_ posterURL: URL?, at date: Date = .now) -> Bool {
        guard usingCustomPoster != true || self.posterURL != posterURL else { return false }
        usingCustomPoster = true
        self.posterURL = posterURL
        markTrackingModified(at: date)
        return true
    }

    /// Rebuilds the full user-owned payload without advancing top-level clocks.
    ///
    /// This is for replay-style flows such as restoring previous edits,
    /// importing a `UserEntryInfo` snapshot, or other callers that already own
    /// their clock semantics. For user actions, prefer
    /// `updateUserInfoFromUserAction(_:at:)`.
    public func updateUserInfo(from userInfo: UserEntryInfo) {
        watchStatus = userInfo.watchStatus
        dateStarted = userInfo.dateStarted
        dateFinished = userInfo.dateFinished
        isDateTrackingEnabled = userInfo.isDateTrackingEnabled
        score = normalizedEntryScore(userInfo.score)
        favorite = userInfo.favorite
        notes = userInfo.notes
        usingCustomPoster = userInfo.usingCustomPoster
        episodeProgresses.forEach { modelContext?.delete($0) }
        episodeProgresses.removeAll()
        for progress in filteredEpisodeProgresses(from: userInfo) {
            applyEpisodeProgressSnapshot(
                seasonNumber: progress.seasonNumber,
                watchedThroughEpisode: progress.watchedThroughEpisode,
                updatedAt: progress.updatedAt
            )
        }
    }

    /// Rebuilds the full user-owned payload and advances `trackingUpdatedAt`.
    public func updateUserInfoFromUserAction(_ userInfo: UserEntryInfo, at date: Date = .now) {
        updateUserInfo(from: userInfo)
        markTrackingModified(at: date)
    }

    private func filteredEpisodeProgresses(from userInfo: UserEntryInfo) -> [UserEntryInfo.EpisodeProgressSnapshot] {
        switch type {
        case .movie:
            return []
        case .series:
            return userInfo.episodeProgresses.filter { $0.seasonNumber > 0 }
        case .season(let seasonNumber, _):
            guard seasonNumber > 0 else { return [] }
            return userInfo.episodeProgresses.filter { $0.seasonNumber == seasonNumber }
        }
    }
}

fileprivate func normalizedEntryScore(_ score: Int?) -> Int? {
    guard let score else { return nil }
    return AnimeEntry.validScoreRange.contains(score) ? score : nil
}
