//
//  LibraryTrackingIntents.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents
import DataProvider
import Foundation

// MARK: - Intents

struct SetWatchStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Watch Status"
    static let description = IntentDescription(
        "Changes an entry's watch status. Starting or finishing fills in an empty start or finish date."
    )

    @Parameter(title: "Entry")
    var entry: LibraryEntryEntity

    @Parameter(title: "Status")
    var status: WatchStatusAppEnum

    @Dependency private var context: AppIntentLibraryContext

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$entry) to \(\.$status)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LibraryEntryEntity> & ProvidesDialog {
        let updated = try context.setWatchStatus(status.watchStatus, forEntryID: entry.id)
        return .result(
            value: updated,
            dialog: "\(updated.name) is now \(status.watchStatus.localizedStringResource)."
        )
    }
}

struct MarkNextEpisodeWatchedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Next Episode Watched"
    static let description = IntentDescription(
        "Adds one watched episode. Watching the last episode marks the entry as Watched."
    )

    @Parameter(title: "Entry")
    var entry: LibraryEntryEntity

    @Dependency private var context: AppIntentLibraryContext

    static var parameterSummary: some ParameterSummary {
        Summary("Mark the next episode of \(\.$entry) watched")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LibraryEntryEntity> & ProvidesDialog {
        let outcome = try context.markNextEpisodeWatched(forEntryID: entry.id)
        return .result(value: outcome.entity, dialog: outcome.dialog)
    }
}

struct SetEpisodeProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Episode Progress"
    static let description = IntentDescription(
        "Sets the last watched episode. Without a season, a series uses the season you changed most recently."
    )

    @Parameter(title: "Entry")
    var entry: LibraryEntryEntity

    @Parameter(title: "Episode", inclusiveRange: (0, 9_999))
    var episode: Int

    @Parameter(title: "Season", inclusiveRange: (1, 999))
    var season: Int?

    @Dependency private var context: AppIntentLibraryContext

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$entry) to episode \(\.$episode)") {
            \.$season
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LibraryEntryEntity> & ProvidesDialog {
        let outcome = try context.setEpisodeProgress(episode, season: season, forEntryID: entry.id)
        return .result(value: outcome.entity, dialog: outcome.dialog)
    }
}

struct ToggleFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Favorite"
    static let description = IntentDescription("Adds an entry to favorites, or removes it if it is already one.")

    @Parameter(title: "Entry")
    var entry: LibraryEntryEntity

    @Dependency private var context: AppIntentLibraryContext

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle favorite for \(\.$entry)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LibraryEntryEntity> & ProvidesDialog {
        let updated = try context.toggleFavorite(forEntryID: entry.id)
        let dialog: IntentDialog =
            updated.isFavorite
            ? "Added \(updated.name) to favorites."
            : "Removed \(updated.name) from favorites."
        return .result(value: updated, dialog: dialog)
    }
}

struct SetScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Score"
    static let description = IntentDescription("Sets an entry's score from 1 to 5. Use 0 to remove the score.")

    @Parameter(title: "Entry")
    var entry: LibraryEntryEntity

    @Parameter(title: "Score", inclusiveRange: (0, 5))
    var score: Int

    @Dependency private var context: AppIntentLibraryContext

    static var parameterSummary: some ParameterSummary {
        Summary("Set the score of \(\.$entry) to \(\.$score)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LibraryEntryEntity> & ProvidesDialog {
        let updated = try context.setScore(score, forEntryID: entry.id)
        let dialog: IntentDialog =
            if let newScore = updated.score {
                "Scored \(updated.name) \(newScore) out of 5."
            } else {
                "Removed the score of \(updated.name)."
            }
        return .result(value: updated, dialog: dialog)
    }
}

// MARK: - Tracking rules

struct LibraryEpisodeProgressOutcome {
    let entity: LibraryEntryEntity
    let seasonNumber: Int
    let watchedThroughEpisode: Int
    /// The last episode was reached, so the entry moved to Watched.
    let markedWatched: Bool

    var dialog: IntentDialog {
        markedWatched
            ? "Watched episode \(watchedThroughEpisode) of \(entity.name). It is now marked as Watched."
            : "Watched through episode \(watchedThroughEpisode) of \(entity.name)."
    }
}

extension AppIntentLibraryContext {
    /// Changes the status and applies the date suggestion the detail view would offer.
    func setWatchStatus(
        _ status: AnimeEntry.WatchStatus,
        forEntryID entryID: LibraryEntryEntity.ID,
        now: Date = .now
    ) throws -> LibraryEntryEntity {
        try performTrackingChange(forEntryID: entryID) { entry in
            guard entry.updateWatchStatus(status, at: now) else { return }
            if let suggestion = entry.dateUpdateSuggestion(forTargetStatus: status) {
                entry.applyDateUpdateSuggestion(suggestion, now: now)
            }
        }
    }

    func markNextEpisodeWatched(
        forEntryID entryID: LibraryEntryEntity.ID,
        now: Date = .now
    ) throws -> LibraryEpisodeProgressOutcome {
        try requireEpisodeTracking()
        return try performEpisodeProgressChange(forEntryID: entryID, now: now) { entry in
            let seasonNumber = try Self.nextEpisodeSeason(for: entry)
            let watched = entry.episodeProgressSummary(forSeason: seasonNumber).watchedThroughEpisode
            return (seasonNumber, watched + 1)
        }
    }

    func setEpisodeProgress(
        _ episode: Int,
        season requestedSeason: Int?,
        forEntryID entryID: LibraryEntryEntity.ID,
        now: Date = .now
    ) throws -> LibraryEpisodeProgressOutcome {
        try requireEpisodeTracking()
        return try performEpisodeProgressChange(forEntryID: entryID, now: now) { entry in
            (try Self.progressSeason(for: entry, requested: requestedSeason), episode)
        }
    }

    func toggleFavorite(
        forEntryID entryID: LibraryEntryEntity.ID,
        now: Date = .now
    ) throws -> LibraryEntryEntity {
        try performTrackingChange(forEntryID: entryID) { entry in
            entry.toggleFavorite(at: now)
        }
    }

    /// Sets a 1–5 score; 0 removes it.
    func setScore(
        _ score: Int,
        forEntryID entryID: LibraryEntryEntity.ID,
        now: Date = .now
    ) throws -> LibraryEntryEntity {
        guard defaults.isLibraryScoringEnabled else { throw LibraryIntentError.scoringDisabled }
        return try performTrackingChange(forEntryID: entryID) { entry in
            entry.updateScore(score == 0 ? nil : score, at: now)
        }
    }

    // MARK: Helpers

    private func requireEpisodeTracking() throws {
        guard defaults.isEpisodeProgressTrackingEnabled else {
            throw LibraryIntentError.episodeTrackingDisabled
        }
    }

    private func performEpisodeProgressChange(
        forEntryID entryID: LibraryEntryEntity.ID,
        now: Date,
        target: (AnimeEntry) throws -> (seasonNumber: Int, episode: Int)
    ) throws -> LibraryEpisodeProgressOutcome {
        var seasonNumber = 0
        var watchedThroughEpisode = 0
        var markedWatched = false
        let entity = try performTrackingChange(forEntryID: entryID) { entry in
            let target = try target(entry)
            seasonNumber = target.seasonNumber
            markedWatched = Self.updateEpisodeProgress(
                of: entry,
                seasonNumber: target.seasonNumber,
                to: target.episode,
                now: now
            )
            watchedThroughEpisode = entry.episodeProgressSummary(forSeason: seasonNumber).watchedThroughEpisode
        }
        return LibraryEpisodeProgressOutcome(
            entity: entity,
            seasonNumber: seasonNumber,
            watchedThroughEpisode: watchedThroughEpisode,
            markedWatched: markedWatched
        )
    }

    /// Runs one tracking change, saves it, and rebases any open detail's undo baseline.
    ///
    /// Saving the main context reaches the existing observers, which refresh the library,
    /// queue the change for sync, and update Spotlight.
    private func performTrackingChange(
        forEntryID entryID: LibraryEntryEntity.ID,
        _ change: (AnimeEntry) throws -> Void
    ) throws -> LibraryEntryEntity {
        let entry = try entry(for: entryID)
        let before = entry.userInfo
        try change(entry)
        if let trackingChange = LibraryEntryTrackingChange(
            identity: entry.libraryIdentity,
            before: before,
            after: entry.userInfo,
            trackingUpdatedAt: entry.trackingUpdatedAt
        ) {
            try store.repository.save()
            trackingChange.post()
        }
        return LibraryEntryEntity(entry: entry)
    }

    /// Applies new progress, then marks the entry Watched if that reached the last episode,
    /// as answering "Mark as Watched" in the detail view would.
    ///
    /// - Returns: Whether the entry moved to Watched.
    private static func updateEpisodeProgress(
        of entry: AnimeEntry,
        seasonNumber: Int,
        to episode: Int,
        now: Date
    ) -> Bool {
        let previous = entry.episodeProgressSummary(forSeason: seasonNumber).watchedThroughEpisode
        entry.updateEpisodeProgress(seasonNumber: seasonNumber, watchedThroughEpisode: episode, at: now)
        guard
            entry.episodeProgressCompletionPrompt(
                forSeason: seasonNumber,
                previousWatchedThroughEpisode: previous
            ) != nil
        else { return false }
        // A marked rewatch counts one more completed rewatch here.
        entry.updateWatchStatus(.watched, at: now)
        if let suggestion = entry.dateUpdateSuggestion(forTargetStatus: .watched) {
            entry.applyDateUpdateSuggestion(suggestion, now: now)
        }
        return true
    }

    /// The season the progress slider in the detail view would show first.
    static func progressSeason(for entry: AnimeEntry, requested: Int?) throws -> Int {
        switch entry.type {
        case .movie:
            throw LibraryIntentError.notEpisodic
        case .season(let seasonNumber, _):
            guard seasonNumber > 0 else { throw LibraryIntentError.notEpisodic }
            return seasonNumber
        case .series:
            if let requested { return requested }
            let options = entry.episodeProgressSeasonOptions
            if let latest = entry.latestEpisodeProgressSummary?.seasonNumber, options.contains(latest) {
                return latest
            }
            return options.first ?? 1
        }
    }

    /// The progress season, or for a series whose season is complete, the next unfinished one.
    static func nextEpisodeSeason(for entry: AnimeEntry) throws -> Int {
        let preferred = try progressSeason(for: entry, requested: nil)
        var candidates = [preferred]
        if entry.type == .series {
            let remainingSeasons = entry.episodeProgressSeasonOptions.drop { $0 != preferred }
            if !remainingSeasons.isEmpty {
                candidates = Array(remainingSeasons)
            }
        }
        guard
            let season = candidates.first(where: { seasonNumber in
                let summary = entry.episodeProgressSummary(forSeason: seasonNumber)
                guard let episodeCount = summary.episodeCount else { return true }
                return summary.watchedThroughEpisode < episodeCount
            })
        else {
            throw LibraryIntentError.allEpisodesWatched
        }
        return season
    }
}
