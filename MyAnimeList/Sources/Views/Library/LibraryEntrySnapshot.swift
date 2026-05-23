import DataProvider
import Foundation
import SwiftUI

struct LibraryEntryDisplayItem: Identifiable {
    let entry: AnimeEntry
    let snapshot: LibraryEntrySnapshot

    var id: Int { snapshot.id }

    init(entry: AnimeEntry) {
        self.entry = entry
        self.snapshot = LibraryEntrySnapshot(entry: entry)
    }
}

struct LibraryEntrySnapshot: Identifiable, Equatable {
    let id: Int
    let posterURL: URL?
    let title: String
    let overview: String?
    let primaryMetadata: [String]
    let secondaryMetadata: String?
    let watchStatus: AnimeEntry.WatchStatus
    let score: Int?
    let isFavorite: Bool
    let episodeProgressLabel: String?
    let episodeProgressFraction: Double?
    let dateStarted: Date?
    let dateFinished: Date?

    init(entry: AnimeEntry) {
        let episodeProgress = Self.episodeProgressDisplay(for: entry)

        id = entry.tmdbID
        posterURL = entry.posterURL
        title = entry.displayName
        overview = Self.cleanOverview(entry.displayOverview)
        primaryMetadata = Self.primaryMetadata(for: entry)
        secondaryMetadata = Self.secondaryMetadata(for: entry)
        watchStatus = entry.watchStatus
        score = entry.score
        isFavorite = entry.favorite
        episodeProgressLabel = episodeProgress.label
        episodeProgressFraction = episodeProgress.fraction
        dateStarted = entry.dateStarted
        dateFinished = entry.dateFinished
    }

    private struct EpisodeProgressDisplay {
        let label: String?
        let fraction: Double?

        static let empty = EpisodeProgressDisplay(label: nil, fraction: nil)
    }

    private static func cleanOverview(_ overview: String?) -> String? {
        guard
            let overview = overview?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !overview.isEmpty
        else {
            return nil
        }

        return overview
    }

    private static func primaryMetadata(for entry: AnimeEntry) -> [String] {
        [
            dateText(for: entry.onAirDate),
            typeSummaryText(for: entry)
        ].compactMap(\.self)
    }

    private static func secondaryMetadata(for entry: AnimeEntry) -> String? {
        guard case .season(let seasonNumber, _) = entry.type else { return nil }
        return String(localized: seasonSummaryResource(seasonNumber: seasonNumber))
    }

    private static func dateText(for date: Date?) -> String? {
        date?.formatted(.dateTime.year().month().day())
    }

    private static func typeSummaryText(for entry: AnimeEntry) -> String? {
        switch entry.type {
        case .movie:
            return String(localized: movieSummaryResource(runtime: entry.detail?.runtimeMinutes))
        case .series:
            return entry.detail?.episodeCount.map { String(localized: episodeCountResource($0)) }
                ?? String(localized: "Series")
        case .season(let seasonNumber, _):
            return entry.detail?.episodeCount.map { String(localized: episodeCountResource($0)) }
                ?? String(localized: seasonSummaryResource(seasonNumber: seasonNumber))
        }
    }

    private static func movieSummaryResource(runtime: Int?) -> LocalizedStringResource {
        if let runtime {
            return "\(runtime) min"
        }
        return "Movie"
    }

    private static func seasonSummaryResource(seasonNumber: Int) -> LocalizedStringResource {
        if seasonNumber == 0 {
            return "Specials"
        }
        return "Season \(seasonNumber)"
    }

    private static func episodeCountResource(_ count: Int) -> LocalizedStringResource {
        "\(count) episodes"
    }

    private static func episodeProgressDisplay(for entry: AnimeEntry) -> EpisodeProgressDisplay {
        guard entry.watchStatus == .watching else { return .empty }

        switch entry.type {
        case .movie:
            return .empty
        case .series:
            return seriesEpisodeProgressDisplay(for: entry)
        case .season:
            return seasonEpisodeProgressDisplay(summary: entry.latestEpisodeProgressSummary)
        }
    }

    private static func seasonEpisodeProgressDisplay(
        summary: AnimeEntryEpisodeProgressSummary?
    ) -> EpisodeProgressDisplay {
        guard let summary else { return .empty }

        return EpisodeProgressDisplay(
            label: "EP\(summary.watchedThroughEpisode)",
            fraction: episodeProgressFraction(
                watchedThroughEpisode: summary.watchedThroughEpisode,
                episodeCount: summary.episodeCount
            )
        )
    }

    private static func seriesEpisodeProgressDisplay(for entry: AnimeEntry) -> EpisodeProgressDisplay {
        let seasonNumbers = Set(
            (entry.detail?.seasons.map(\.seasonNumber) ?? []).filter { $0 > 0 }
                + entry.orderedEpisodeProgresses.map(\.seasonNumber)
        )
        .sorted()

        let summaries =
            seasonNumbers
            .map(entry.episodeProgressSummary(forSeason:))

        guard !summaries.isEmpty else {
            return .empty
        }

        let watchedThroughEpisode = summaries.reduce(0) { partialResult, summary in
            partialResult + summary.watchedThroughEpisode
        }
        guard watchedThroughEpisode > 0 else {
            return .empty
        }

        let summariesWithKnownCounts = summaries.filter { summary in
            guard let episodeCount = summary.episodeCount else { return false }
            return episodeCount > 0
        }
        let watchedThroughKnownEpisodes = summariesWithKnownCounts.reduce(0) { partialResult, summary in
            partialResult + summary.watchedThroughEpisode
        }
        let totalEpisodeCount = summariesWithKnownCounts.reduce(0) { partialResult, summary in
            partialResult + (summary.episodeCount ?? 0)
        }

        return EpisodeProgressDisplay(
            label: latestSeriesEpisodeProgressLabel(for: entry.latestEpisodeProgressSummary),
            fraction: episodeProgressFraction(
                watchedThroughEpisode: watchedThroughKnownEpisodes,
                episodeCount: totalEpisodeCount > 0 ? totalEpisodeCount : nil
            )
        )
    }

    private static func latestSeriesEpisodeProgressLabel(
        for summary: AnimeEntryEpisodeProgressSummary?
    ) -> String? {
        guard let summary else { return nil }
        if summary.seasonNumber == 0 {
            return "SP\(summary.watchedThroughEpisode)"
        }
        return "S\(summary.seasonNumber)E\(summary.watchedThroughEpisode)"
    }

    private static func episodeProgressFraction(
        watchedThroughEpisode: Int,
        episodeCount: Int?
    ) -> Double? {
        guard
            let episodeCount,
            episodeCount > 0
        else {
            return nil
        }

        let rawFraction = Double(watchedThroughEpisode) / Double(episodeCount)
        return min(max(rawFraction, 0), 1)
    }
}
