//
//  EntryDetailModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/6.
//

import SwiftUI

struct EntryDetailStatCard: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let value: String
    let symbolName: String
}

struct EntryDetailCharacterCard: Identifiable {
    let id: Int
    let characterName: String
    let actorName: String
    let profileURL: URL?
}

struct EntryDetailStaffCard: Identifiable {
    let id: Int
    let name: String
    let role: String
    let department: String?
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

struct EpisodePreviewContext {
    let seriesTMDbID: Int
    let seasonNumber: Int
    let language: Language
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
