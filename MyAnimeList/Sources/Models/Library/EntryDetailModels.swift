//
//  EntryDetailModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/6.
//

import DataProvider
import SwiftUI

struct EntryDetailStatCard: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let value: String
    let symbolName: String
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
        guard watchStatus == .watching, seasonNumber > 0, let summary, summary.watchedThroughEpisode > 0
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
