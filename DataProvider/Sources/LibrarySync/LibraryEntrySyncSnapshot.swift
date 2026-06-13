//
//  LibraryEntrySyncSnapshot.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import DataProvider
import Foundation

/// Stable CloudKit-facing identity for one library entry.
///
/// The identity is derived from AniShelf's entry type plus TMDb identifiers so
/// every device can address the same movie, series, or season record without
/// depending on local SwiftData identifiers.
public struct LibraryEntrySyncIdentity: Codable, Hashable, Sendable {
    public let rawID: String

    /// Creates the record identity for a library entry.
    ///
    /// - Parameters:
    ///   - entryType: Entry kind and, for seasons, the parent series context.
    ///   - tmdbID: TMDb identifier for the concrete entry being synced.
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

    /// Extracts the concrete entry TMDb identifier from the stable record name.
    public var tmdbID: Int? {
        guard let suffix = rawID.split(separator: ":").last else {
            return nil
        }
        return Int(suffix)
    }
}

/// Lean user-owned state that is safe to sync through iCloud.
///
/// This snapshot intentionally excludes fetched TMDb metadata. It carries only
/// the library membership, display, tracking, poster override, note, episode
/// progress fields needed to replay a user's library state on another device.
public struct LibraryEntrySyncSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

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
        case customPosterPath
        case customPosterURL
        case episodeProgresses
        case libraryUpdatedAt
        case trackingUpdatedAt
    }

    /// Per-season episode progress included in a sync snapshot.
    public struct EpisodeProgress: Codable, Equatable, Sendable {
        public var seasonNumber: Int
        public var watchedThroughEpisode: Int
        public var updatedAt: Date

        /// Creates normalized episode progress for one season.
        ///
        /// Negative episode counts are clamped to zero so malformed input does
        /// not advance a remote device.
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
    public var customPosterPath: String?
    public var episodeProgresses: [EpisodeProgress]
    public var libraryUpdatedAt: Date?
    public var trackingUpdatedAt: Date?
    /// Newest sync clock used when deciding whether remote state can clear a
    /// local dirty-queue entry.
    public var latestSyncClock: Date? {
        [
            libraryUpdatedAt,
            trackingUpdatedAt,
            episodeProgresses.map(\.updatedAt).max()
        ]
        .compactMap(\.self)
        .max()
    }

    /// Newest user-state clock used when comparing a snapshot against a tombstone.
    public var latestUserStateClock: Date? {
        [
            dateSaved,
            libraryUpdatedAt,
            trackingUpdatedAt,
            episodeProgresses.map(\.updatedAt).max()
        ]
        .compactMap(\.self)
        .max()
    }

    /// Creates a normalized sync snapshot.
    ///
    /// - Parameters:
    ///   - schemaVersion: Snapshot schema version. Defaults to the current
    ///     version for newly created local snapshots.
    ///   - identity: Stable identity used as the CloudKit record name.
    ///   - tmdbID: TMDb identifier for the concrete movie, series, or season.
    ///   - parentSeriesID: Parent series TMDb identifier for seasons; `nil` for
    ///     movies and series.
    ///   - seasonNumber: Season number for season entries; `nil` for movies and
    ///     series.
    ///   - entryType: AniShelf entry type, including season context.
    ///   - onDisplay: Whether the entry is currently visible in the user's
    ///     library.
    ///   - dateSaved: Local date the user saved the entry.
    ///   - watchStatus: User tracking status.
    ///   - dateStarted: User-entered start date.
    ///   - dateFinished: User-entered finish date.
    ///   - isDateTrackingEnabled: Whether automatic date suggestions are enabled.
    ///   - score: Optional user score. Values outside AniShelf's valid score
    ///     range are dropped.
    ///   - favorite: Favorite flag.
    ///   - notes: User notes.
    ///   - usingCustomPoster: Whether `customPosterPath` should be applied.
    ///   - customPosterPath: User-selected TMDb poster path. Ignored unless
    ///     `usingCustomPoster` is true.
    ///   - episodeProgresses: Per-season episode progress. Entries are
    ///     normalized to one positive progress value per positive season.
    ///   - libraryUpdatedAt: Clock for membership/display changes.
    ///   - trackingUpdatedAt: Clock for status, date, score, favorite, notes,
    ///     poster, and progress changes.
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
        customPosterPath: String?,
        episodeProgresses: [EpisodeProgress],
        libraryUpdatedAt: Date?,
        trackingUpdatedAt: Date?
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
        self.customPosterPath = usingCustomPoster ? TMDbImagePath.storagePath(from: customPosterPath) : nil
        self.episodeProgresses = Self.normalizedEpisodeProgresses(episodeProgresses)
        self.libraryUpdatedAt = libraryUpdatedAt
        self.trackingUpdatedAt = trackingUpdatedAt
    }

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
        trackingUpdatedAt: Date?
    ) {
        self.init(
            schemaVersion: schemaVersion,
            identity: identity,
            tmdbID: tmdbID,
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber,
            entryType: entryType,
            onDisplay: onDisplay,
            dateSaved: dateSaved,
            watchStatus: watchStatus,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            isDateTrackingEnabled: isDateTrackingEnabled,
            score: score,
            favorite: favorite,
            notes: notes,
            usingCustomPoster: usingCustomPoster,
            customPosterPath: TMDbImagePath.storagePath(from: customPosterURL),
            episodeProgresses: episodeProgresses,
            libraryUpdatedAt: libraryUpdatedAt,
            trackingUpdatedAt: trackingUpdatedAt
        )
    }

    /// Projects a local `AnimeEntry` into the lean sync model.
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
            customPosterPath: entry.usingCustomPoster ? entry.customPosterPath : nil,
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
            customPosterPath: try container.decodeIfPresent(String.self, forKey: .customPosterPath)
                ?? TMDbImagePath.storagePath(
                    from: try container.decodeIfPresent(URL.self, forKey: .customPosterURL)
                ),
            episodeProgresses: try container.decodeIfPresent([EpisodeProgress].self, forKey: .episodeProgresses)
                ?? [],
            libraryUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .libraryUpdatedAt),
            trackingUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .trackingUpdatedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(identity, forKey: .identity)
        try container.encode(tmdbID, forKey: .tmdbID)
        try container.encodeIfPresent(parentSeriesID, forKey: .parentSeriesID)
        try container.encodeIfPresent(seasonNumber, forKey: .seasonNumber)
        try container.encode(entryType, forKey: .entryType)
        try container.encode(onDisplay, forKey: .onDisplay)
        try container.encode(dateSaved, forKey: .dateSaved)
        try container.encode(watchStatus, forKey: .watchStatus)
        try container.encodeIfPresent(dateStarted, forKey: .dateStarted)
        try container.encodeIfPresent(dateFinished, forKey: .dateFinished)
        try container.encode(isDateTrackingEnabled, forKey: .isDateTrackingEnabled)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(notes, forKey: .notes)
        try container.encode(usingCustomPoster, forKey: .usingCustomPoster)
        try container.encodeIfPresent(customPosterPath, forKey: .customPosterPath)
        try container.encode(episodeProgresses, forKey: .episodeProgresses)
        try container.encodeIfPresent(libraryUpdatedAt, forKey: .libraryUpdatedAt)
        try container.encodeIfPresent(trackingUpdatedAt, forKey: .trackingUpdatedAt)
    }

    /// Returns the last-writer-wins merge of two snapshots with the same identity.
    ///
    /// Library membership/display fields follow `libraryUpdatedAt`; tracking
    /// fields follow `trackingUpdatedAt`; episode progress merges per season by
    /// progress clock.
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
            merged.customPosterPath = other.usingCustomPoster ? other.customPosterPath : nil
            merged.trackingUpdatedAt = other.trackingUpdatedAt
        }

        merged.episodeProgresses = Self.mergedEpisodeProgresses(
            merged.episodeProgresses,
            other.episodeProgresses
        )

        return merged
    }

    fileprivate static func isNewer(_ candidate: Date?, than existing: Date?) -> Bool {
        guard let candidate else { return false }
        guard let existing else { return true }
        return candidate > existing
    }

    /// Merges progress from both snapshots one season at a time.
    ///
    /// Each season keeps the newest progress clock, with the higher episode
    /// number winning when two updates have the same timestamp.
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

    /// Chooses the progress value that should win for a single season.
    private static func newerEpisodeProgress(
        _ lhs: EpisodeProgress,
        _ rhs: EpisodeProgress
    ) -> EpisodeProgress {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.watchedThroughEpisode >= rhs.watchedThroughEpisode ? lhs : rhs
        }
        return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
    }

    /// Drops invalid/empty progress and returns one sorted value per season.
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
    /// Stable sync identity for this local entry.
    public var syncIdentity: LibraryEntrySyncIdentity {
        LibraryEntrySyncIdentity(entryType: type, tmdbID: tmdbID)
    }

    /// Applies a merged remote snapshot to an existing local entry.
    ///
    /// This method respects the snapshot clocks instead of blindly overwriting
    /// local state.
    ///
    /// - Parameters:
    ///   - snapshot: Remote or merged snapshot for the same sync identity.
    ///   - now: Reserved clock injection point for callers/tests. Episode
    ///     progress application uses each progress value's own `updatedAt`.
    /// - Throws: `MergeError.identityMismatch` when the snapshot targets a
    ///   different sync identity.
    public func applySyncSnapshot(_ snapshot: LibraryEntrySyncSnapshot, now: Date = .now) throws {
        guard syncIdentity == snapshot.identity else {
            throw LibraryEntrySyncSnapshot.MergeError.identityMismatch(
                local: syncIdentity,
                remote: snapshot.identity
            )
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
                customPosterPath = snapshot.customPosterPath
            } else if wasUsingCustomPoster {
                customPosterPath = nil
            }
            trackingUpdatedAt = snapshot.trackingUpdatedAt
        }

        applySyncEpisodeProgresses(snapshot.episodeProgresses, now: now)
    }

    /// Applies a remote snapshot to a newly hydrated local entry.
    ///
    /// Use this when the app had to recreate a missing entry from TMDb metadata
    /// before applying user-owned sync fields. Unlike `applySyncSnapshot`, this
    /// seeds all snapshot fields because there is no meaningful local user state
    /// to preserve.
    ///
    /// - Parameters:
    ///   - snapshot: Remote snapshot used to initialize the entry.
    ///   - now: Reserved clock injection point for callers/tests. Episode
    ///     progress application uses each progress value's own `updatedAt`.
    /// - Throws: `MergeError.identityMismatch` when the snapshot targets a
    ///   different sync identity.
    public func applyInitialSyncSnapshot(_ snapshot: LibraryEntrySyncSnapshot, now: Date = .now) throws {
        guard syncIdentity == snapshot.identity else {
            throw LibraryEntrySyncSnapshot.MergeError.identityMismatch(
                local: syncIdentity,
                remote: snapshot.identity
            )
        }

        onDisplay = snapshot.onDisplay
        dateSaved = snapshot.dateSaved
        libraryUpdatedAt = snapshot.libraryUpdatedAt
        watchStatus = snapshot.watchStatus
        dateStarted = snapshot.dateStarted
        dateFinished = snapshot.dateFinished
        isDateTrackingEnabled = snapshot.isDateTrackingEnabled
        score = normalizedSyncScore(snapshot.score)
        favorite = snapshot.favorite
        notes = snapshot.notes
        usingCustomPoster = snapshot.usingCustomPoster
        if snapshot.usingCustomPoster {
            customPosterPath = snapshot.customPosterPath
        }
        trackingUpdatedAt = snapshot.trackingUpdatedAt

        applySyncEpisodeProgresses(snapshot.episodeProgresses, now: now)
    }

    /// Applies a delete tombstone when it is newer than local user-state clocks.
    ///
    /// Delete sync hides the entry rather than removing the local row, preserving
    /// enough local metadata for later rehydration and conflict resolution.
    public func applySyncTombstone(_ tombstone: LibraryEntrySyncTombstone) throws {
        guard syncIdentity == tombstone.identity else {
            throw LibraryEntrySyncSnapshot.MergeError.identityMismatch(
                local: syncIdentity,
                remote: tombstone.identity
            )
        }
        applySyncTombstone(deletedAt: tombstone.deletedAt)
    }

    /// Applies a delete tombstone when it is newer than local user-state clocks.
    ///
    /// Delete sync hides the entry rather than removing the local row, preserving
    /// enough local metadata for later rehydration and conflict resolution.
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

    /// Applies per-season progress without regressing local progress.
    ///
    /// A remote progress value must have a newer timestamp, or the same
    /// timestamp with a higher episode count, before it updates the entry.
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
            applyEpisodeProgressSnapshot(
                seasonNumber: progress.seasonNumber,
                watchedThroughEpisode: progress.watchedThroughEpisode,
                updatedAt: progress.updatedAt
            )
        }
    }
}

fileprivate func normalizedSyncScore(_ score: Int?) -> Int? {
    guard let score else { return nil }
    return AnimeEntry.validScoreRange.contains(score) ? score : nil
}
