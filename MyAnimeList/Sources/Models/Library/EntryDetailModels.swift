//
//  EntryDetailModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/6.
//

import DataProvider
import SwiftUI

struct EntryDetailProductionCompanyCard: Identifiable {
    let id: Int
    let name: String
    let logoURL: URL?
}

/// Identity for a detail stat card.
///
/// Presentation details derive from the kind so behavior is never inferred from
/// an icon name or a position in the card array.
enum EntryDetailStatKind: String {
    case tmdbScore
    case episodes
    case runtime
    case production

    var symbolName: String {
        switch self {
        case .tmdbScore: "star.fill"
        case .episodes: "play.rectangle.fill"
        case .runtime: "clock.fill"
        case .production: "movieclapper.fill"
        }
    }

    /// Company names are free-form text, unlike the numeric stats, so they may
    /// shrink to fit a card.
    var valueIsShrinkable: Bool { self == .production }
}

struct EntryDetailStatCard: Identifiable {
    let kind: EntryDetailStatKind
    let title: LocalizedStringResource
    let value: String

    var id: EntryDetailStatKind { kind }
    var symbolName: String { kind.symbolName }
    var valueIsShrinkable: Bool { kind.valueIsShrinkable }
}

struct EntryDetailPersonCard: Identifiable {
    let id: Int
    let primaryText: String
    let secondaryText: String
    let profileURL: URL?
}

struct EntryDetailSeasonCard: Identifiable {
    let id: Int
    let seasonNumber: Int
    let title: String
    let subtitle: String
    let posterURL: URL?
}

struct EntryDetailEpisodeCard: Identifiable, Equatable {
    let id: Int
    let episodeNumber: Int
    let title: String
    let subtitle: String
    let imageURL: URL?
}

struct EpisodePreviewStaffRow: Identifiable, Equatable {
    let role: String
    let names: String

    var id: String { role }
}

struct EpisodePreviewContext {
    let seriesTMDbID: Int
    let seasonNumber: Int
    let language: Language
}

enum EntryDetailEpisodePresentation {
    static func isEpisodeWatched(
        _ episodeNumber: Int,
        inSeason seasonNumber: Int,
        watchStatus: AnimeEntry.WatchStatus,
        summary: AnimeEntryEpisodeProgressSummary?
    ) -> Bool {
        switch watchStatus {
        case .watching, .watched, .dropped:
            break
        case .planToWatch:
            return false
        }

        guard seasonNumber > 0, let summary, summary.watchedThroughEpisode > 0
        else { return false }
        return episodeNumber <= summary.watchedThroughEpisode
    }
}

enum EntryDetailSeasonExpansionPolicy {
    static let largeSeriesEpisodeThreshold = 200
    private static let estimatedEpisodesPerSeason = 24

    static func shouldCollapseSeriesSeasonsByDefault(
        episodeCount: Int?,
        seasonCount: Int?,
        seasonCardCount: Int
    ) -> Bool {
        if let episodeCount {
            return episodeCount >= largeSeriesEpisodeThreshold
        }

        let estimatedSeasonCount = seasonCount ?? seasonCardCount
        return estimatedSeasonCount * estimatedEpisodesPerSeason >= largeSeriesEpisodeThreshold
    }
}
