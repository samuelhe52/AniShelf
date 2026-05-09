//
//  EntryDetailSupport.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

import SwiftUI

enum EntryDetailL10n {
    static let loading: LocalizedStringResource = "Loading..."
    static let done: LocalizedStringResource = "Done"
    static let showDetail: LocalizedStringResource = "Show Detail"
    static let overview: LocalizedStringResource = "Overview"
    static let score: LocalizedStringResource = "Score"
    static let noScore: LocalizedStringResource = "No score"
    static let clear: LocalizedStringResource = "Clear"
    static let episodes: LocalizedStringResource = "Episodes"
    static let characters: LocalizedStringResource = "Characters"
    static let staff: LocalizedStringResource = "Staff"
    static let tmdb: LocalizedStringResource = "TMDb"
    static let couldNotLoadDetails: LocalizedStringResource = "Couldn't load details"
    static let noOverviewAvailable: LocalizedStringResource = "No overview available."
    static let tmdbScore: LocalizedStringResource = "TMDb Score"
    static let runtime: LocalizedStringResource = "Runtime"
    static let averageRuntime: LocalizedStringResource = "Avg Runtime"
    static let episode: LocalizedStringResource = "Episode"
    static let noEpisodesAvailable: LocalizedStringResource = "No episodes available for this season."
}

enum EntryDetailScrollTarget: Hashable {
    case editingSection
    case episodesSection
}
