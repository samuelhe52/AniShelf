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
    static let save: LocalizedStringResource = "Save"
    static let cancel: LocalizedStringResource = "Cancel"
    static let discard: LocalizedStringResource = "Discard"
    static let discardChanges: LocalizedStringResource = "Discard Changes"
    static let changePoster: LocalizedStringResource = "Change Poster"
    static let overview: LocalizedStringResource = "Overview"
    static let tracking: LocalizedStringResource = "Tracking"
    static let watchStatus: LocalizedStringResource = "Watch Status"
    static let notes: LocalizedStringResource = "Notes"
    static let writeSomeThoughts: LocalizedStringResource = "Write some thoughts..."
    static let score: LocalizedStringResource = "Score"
    static let noScore: LocalizedStringResource = "No score"
    static let clear: LocalizedStringResource = "Clear"
    static let episodes: LocalizedStringResource = "Episodes"
    static let characters: LocalizedStringResource = "Characters"
    static let staff: LocalizedStringResource = "Staff"
    static let convertToWhichSeason: LocalizedStringResource = "Convert to which season?"
    static let noSeasonsAvailable: LocalizedStringResource = "No seasons available"
    static let convertToSeason: LocalizedStringResource = "Convert to Season"
    static let convertToSeries: LocalizedStringResource = "Convert to Series"
    static let convertedToSeason: LocalizedStringResource = "Converted to season"
    static let convertedToSeries: LocalizedStringResource = "Converted to series"
    static let siblingSeasonExists: LocalizedStringResource = "Sibling Season Exists"
    static let convertAnyway: LocalizedStringResource = "Convert Anyway"
    static let siblingSeasonExistsMessage: LocalizedStringResource =
        "Another season entry for this series is already in your library. Converting this season to a series can leave both the series and the sibling season entries in the library."
    static let markAsDropped: LocalizedStringResource = "Mark as Dropped"
    static let undrop: LocalizedStringResource = "Undrop"
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

enum EntryDetailSheet: Identifiable {
    case changePoster
    case sharing

    var id: Self { self }
}

struct EntryDetailPresentationState {
    var activeSheet: EntryDetailSheet?
    var showSeasonPicker = false
    var showSiblingSeasonWarning = false
}

struct EntryDetailConversionState {
    var inProgress = false
    var isFetchingSeasons = false
    var seasonNumberOptions: [Int] = []
}
