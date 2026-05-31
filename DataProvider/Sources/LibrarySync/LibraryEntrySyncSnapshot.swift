//
//  LibraryEntrySyncSnapshot.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import DataProvider
import Foundation

public struct LibraryEntrySyncIdentity: Codable, Hashable, Sendable {
    public let rawID: String

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
}

public struct LibraryEntrySyncSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case identity
        case tmdbID
        case parentSeriesID
        case seasonNumber
        case entryType
        case onDisplay
        case dateSaved
        case watchStatus
        case dateStarted
        case dateFinished
        case isDateTrackingEnabled
        case score
        case favorite
        case notes
        case usingCustomPoster
        case customPosterURL
        case episodeProgresses
        case libraryUpdatedAt
        case trackingUpdatedAt
        case deletedAt
    }

    public struct EpisodeProgress: Codable, Equatable, Sendable {
        public var seasonNumber: Int
        public var watchedThroughEpisode: Int
        public var updatedAt: Date

        public init(seasonNumber: Int, watchedThroughEpisode: Int, updatedAt: Date) {
            self.seasonNumber = seasonNumber
            self.watchedThroughEpisode = max(0, watchedThroughEpisode)
            self.updatedAt = updatedAt
        }
    }

    public enum MergeError: Error, Equatable {
        case identityMismatch(local: LibraryEntrySyncIdentity, remote: LibraryEntrySyncIdentity)
    }

    public var schemaVersion: Int
    public var identity: LibraryEntrySyncIdentity
    public var tmdbID: Int
    public var parentSeriesID: Int?
    public var seasonNumber: Int?
    public var entryType: AnimeType
    public var onDisplay: Bool
    public var dateSaved: Date
    public var watchStatus: AnimeEntry.WatchStatus
    public var dateStarted: Date?
    public var dateFinished: Date?
    public var isDateTrackingEnabled: Bool
    public var score: Int?
    public var favorite: Bool
    public var notes: String
    public var usingCustomPoster: Bool
    public var customPosterURL: URL?
    public var episodeProgresses: [EpisodeProgress]
    public var libraryUpdatedAt: Date?
    public var trackingUpdatedAt: Date?
    public var deletedAt: Date?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        identity: LibraryEntrySyncIdentity,
        tmdbID: Int,
        parentSeriesID: Int?,
        seasonNumber: Int?,
        entryType: AnimeType,
        onDisplay: Bool,
        dateSaved: Date,
        watchStatus: AnimeEntry.WatchStatus,
        dateStarted: Date?,
        dateFinished: Date?,
        isDateTrackingEnabled: Bool,
        score: Int?,
        favorite: Bool,
        notes: String,
        usingCustomPoster: Bool,
        customPosterURL: URL?,
        episodeProgresses: [EpisodeProgress],
        libraryUpdatedAt: Date?,
        trackingUpdatedAt: Date?,
        deletedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.tmdbID = tmdbID
        self.parentSeriesID = parentSeriesID
        self.seasonNumber = seasonNumber
        self.entryType = entryType
        self.onDisplay = onDisplay
        self.dateSaved = dateSaved
        self.watchStatus = watchStatus
        self.dateStarted = dateStarted
        self.dateFinished = dateFinished
        self.isDateTrackingEnabled = isDateTrackingEnabled
        self.score = normalizedSyncScore(score)
        self.favorite = favorite
        self.notes = notes
        self.usingCustomPoster = usingCustomPoster
        self.customPosterURL = usingCustomPoster ? customPosterURL : nil
        self.episodeProgresses = Self.normalizedEpisodeProgresses(episodeProgresses)
        self.libraryUpdatedAt = libraryUpdatedAt
        self.trackingUpdatedAt = trackingUpdatedAt
        self.deletedAt = deletedAt
    }

    public init(entry: AnimeEntry) {
        self.init(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            onDisplay: entry.onDisplay,
            dateSaved: entry.dateSaved,
            watchStatus: entry.watchStatus,
            dateStarted: entry.dateStarted,
            dateFinished: entry.dateFinished,
            isDateTrackingEnabled: entry.isDateTrackingEnabled,
            score: entry.score,
            favorite: entry.favorite,
            notes: entry.notes,
            usingCustomPoster: entry.usingCustomPoster,
            customPosterURL: entry.usingCustomPoster ? entry.posterURL : nil,
            episodeProgresses: entry.orderedEpisodeProgresses.map {
                EpisodeProgress(
                    seasonNumber: $0.seasonNumber,
                    watchedThroughEpisode: $0.watchedThroughEpisode,
                    updatedAt: $0.updatedAt
                )
            },
            libraryUpdatedAt: entry.libraryUpdatedAt,
            trackingUpdatedAt: entry.trackingUpdatedAt
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion,
            identity: try container.decode(LibraryEntrySyncIdentity.self, forKey: .identity),
            tmdbID: try container.decode(Int.self, forKey: .tmdbID),
            parentSeriesID: try container.decodeIfPresent(Int.self, forKey: .parentSeriesID),
            seasonNumber: try container.decodeIfPresent(Int.self, forKey: .seasonNumber),
            entryType: try container.decode(AnimeType.self, forKey: .entryType),
            onDisplay: try container.decode(Bool.self, forKey: .onDisplay),
            dateSaved: try container.decode(Date.self, forKey: .dateSaved),
            watchStatus: try container.decode(AnimeEntry.WatchStatus.self, forKey: .watchStatus),
            dateStarted: try container.decodeIfPresent(Date.self, forKey: .dateStarted),
            dateFinished: try container.decodeIfPresent(Date.self, forKey: .dateFinished),
            isDateTrackingEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDateTrackingEnabled)
                ?? true,
            score: try container.decodeIfPresent(Int.self, forKey: .score),
            favorite: try container.decode(Bool.self, forKey: .favorite),
            notes: try container.decode(String.self, forKey: .notes),
            usingCustomPoster: try container.decode(Bool.self, forKey: .usingCustomPoster),
            customPosterURL: try container.decodeIfPresent(URL.self, forKey: .customPosterURL),
            episodeProgresses: try container.decodeIfPresent([EpisodeProgress].self, forKey: .episodeProgresses)
                ?? [],
            libraryUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .libraryUpdatedAt),
            trackingUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .trackingUpdatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    public func merged(with other: LibraryEntrySyncSnapshot) throws -> LibraryEntrySyncSnapshot {
        guard identity == other.identity else {
            throw MergeError.identityMismatch(local: identity, remote: other.identity)
        }

        var merged = self
        if Self.isNewer(other.libraryUpdatedAt, than: merged.libraryUpdatedAt) {
            merged.onDisplay = other.onDisplay
            merged.dateSaved = other.dateSaved
            merged.libraryUpdatedAt = other.libraryUpdatedAt
        }

        if Self.isNewer(other.trackingUpdatedAt, than: merged.trackingUpdatedAt) {
            merged.watchStatus = other.watchStatus
            merged.dateStarted = other.dateStarted
            merged.dateFinished = other.dateFinished
            merged.isDateTrackingEnabled = other.isDateTrackingEnabled
            merged.score = other.score
            merged.favorite = other.favorite
            merged.notes = other.notes
            merged.usingCustomPoster = other.usingCustomPoster
            merged.customPosterURL = other.usingCustomPoster ? other.customPosterURL : nil
            merged.trackingUpdatedAt = other.trackingUpdatedAt
        }

        merged.episodeProgresses = Self.mergedEpisodeProgresses(
            merged.episodeProgresses,
            other.episodeProgresses
        )

        merged.deletedAt = Self.resolvedDeletedAt(local: merged, remote: other)
        return merged
    }

    private static func resolvedDeletedAt(
        local: LibraryEntrySyncSnapshot,
        remote: LibraryEntrySyncSnapshot
    ) -> Date? {
        let newestDelete = [local.deletedAt, remote.deletedAt].compactMap(\.self).max()
        guard let newestDelete else { return nil }

        guard
            let relevantClock = latestDate(
                local.libraryUpdatedAt,
                local.trackingUpdatedAt,
                local.episodeProgresses.map(\.updatedAt).max()
            )
        else {
            return newestDelete
        }
        return newestDelete > relevantClock ? newestDelete : nil
    }

    fileprivate static func isNewer(_ candidate: Date?, than existing: Date?) -> Bool {
        guard let candidate else { return false }
        guard let existing else { return true }
        return candidate > existing
    }

    private static func latestDate(_ dates: Date?...) -> Date? {
        dates.compactMap(\.self).max()
    }

    private static func mergedEpisodeProgresses(
        _ lhs: [EpisodeProgress],
        _ rhs: [EpisodeProgress]
    ) -> [EpisodeProgress] {
        var progressBySeason: [Int: EpisodeProgress] = [:]
        for progress in lhs where progress.watchedThroughEpisode > 0 {
            if let existing = progressBySeason[progress.seasonNumber] {
                progressBySeason[progress.seasonNumber] = newerEpisodeProgress(existing, progress)
            } else {
                progressBySeason[progress.seasonNumber] = progress
            }
        }

        for progress in rhs where progress.watchedThroughEpisode > 0 {
            if let existing = progressBySeason[progress.seasonNumber] {
                progressBySeason[progress.seasonNumber] = newerEpisodeProgress(existing, progress)
            } else {
                progressBySeason[progress.seasonNumber] = progress
            }
        }

        return normalizedEpisodeProgresses(Array(progressBySeason.values))
    }

    private static func newerEpisodeProgress(
        _ lhs: EpisodeProgress,
        _ rhs: EpisodeProgress
    ) -> EpisodeProgress {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.watchedThroughEpisode >= rhs.watchedThroughEpisode ? lhs : rhs
        }
        return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
    }

    private static func normalizedEpisodeProgresses(
        _ progresses: [EpisodeProgress]
    ) -> [EpisodeProgress] {
        Dictionary(
            grouping: progresses.filter { $0.seasonNumber > 0 && $0.watchedThroughEpisode > 0 },
            by: \.seasonNumber
        )
        .values
        .compactMap { seasonProgresses in
            seasonProgresses.max { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.watchedThroughEpisode < rhs.watchedThroughEpisode
                }
                return lhs.updatedAt < rhs.updatedAt
            }
        }
        .sorted { lhs, rhs in
            if lhs.seasonNumber == rhs.seasonNumber {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.seasonNumber < rhs.seasonNumber
        }
    }
}

extension AnimeEntry {
    public var syncIdentity: LibraryEntrySyncIdentity {
        LibraryEntrySyncIdentity(entryType: type, tmdbID: tmdbID)
    }

    public func applySyncSnapshot(_ snapshot: LibraryEntrySyncSnapshot, now: Date = .now) throws {
        guard syncIdentity == snapshot.identity else {
            throw LibraryEntrySyncSnapshot.MergeError.identityMismatch(
                local: syncIdentity,
                remote: snapshot.identity
            )
        }

        if let deletedAt = snapshot.deletedAt {
            applySyncTombstone(deletedAt: deletedAt)
            return
        }

        if LibraryEntrySyncSnapshot.isNewer(snapshot.libraryUpdatedAt, than: libraryUpdatedAt) {
            onDisplay = snapshot.onDisplay
            dateSaved = snapshot.dateSaved
            libraryUpdatedAt = snapshot.libraryUpdatedAt
        }

        if LibraryEntrySyncSnapshot.isNewer(snapshot.trackingUpdatedAt, than: trackingUpdatedAt) {
            watchStatus = snapshot.watchStatus
            dateStarted = snapshot.dateStarted
            dateFinished = snapshot.dateFinished
            isDateTrackingEnabled = snapshot.isDateTrackingEnabled
            score = normalizedSyncScore(snapshot.score)
            favorite = snapshot.favorite
            notes = snapshot.notes
            let wasUsingCustomPoster = usingCustomPoster
            usingCustomPoster = snapshot.usingCustomPoster
            if snapshot.usingCustomPoster {
                posterURL = snapshot.customPosterURL
            } else if wasUsingCustomPoster {
                posterURL = nil
            }
            trackingUpdatedAt = snapshot.trackingUpdatedAt
        }

        applySyncEpisodeProgresses(snapshot.episodeProgresses, now: now)
    }

    private func applySyncTombstone(deletedAt: Date) {
        if let latestLocalClock = [
            dateSaved, libraryUpdatedAt, trackingUpdatedAt, episodeProgresses.map(\.updatedAt).max()
        ]
        .compactMap(\.self)
        .max() {
            guard deletedAt > latestLocalClock else { return }
        }
        onDisplay = false
    }

    private func applySyncEpisodeProgresses(
        _ progresses: [LibraryEntrySyncSnapshot.EpisodeProgress],
        now: Date
    ) {
        for progress in progresses where progress.watchedThroughEpisode > 0 {
            if let localProgress = episodeProgress(forSeason: progress.seasonNumber) {
                guard
                    progress.updatedAt > localProgress.updatedAt
                        || (progress.updatedAt == localProgress.updatedAt
                            && progress.watchedThroughEpisode > localProgress.watchedThroughEpisode)
                else {
                    continue
                }
            }
            setEpisodeProgress(
                seasonNumber: progress.seasonNumber,
                watchedThroughEpisode: progress.watchedThroughEpisode,
                now: progress.updatedAt
            )
        }
    }
}

fileprivate func normalizedSyncScore(_ score: Int?) -> Int? {
    guard let score else { return nil }
    return AnimeEntry.validScoreRange.contains(score) ? score : nil
}
