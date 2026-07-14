//
//  EntryDetailSupport.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/4/4.
//

import DataProvider
import SwiftUI

enum EntryDetailL10n {
    static let loading: LocalizedStringResource = "Loading..."
    static let done: LocalizedStringResource = "Done"
    static let showDetail: LocalizedStringResource = "Show Detail"
    static let save: LocalizedStringResource = "Save"
    static let cancel: LocalizedStringResource = "Cancel"
    static let notNow: LocalizedStringResource = "Not Now"
    static let discard: LocalizedStringResource = "Discard"
    static let discardChanges: LocalizedStringResource = "Discard Changes"
    static let changePoster: LocalizedStringResource = "Change Poster"
    static let overview: LocalizedStringResource = "Overview"
    static let tracking: LocalizedStringResource = "Tracking"
    static let watchStatus: LocalizedStringResource = "Watch Status"
    static let planned: LocalizedStringResource = "Planned"
    static let watching: LocalizedStringResource = "Watching"
    static let watched: LocalizedStringResource = "Watched"
    static let episodeProgress: LocalizedStringResource = "Episode Progress"
    static let trackDates: LocalizedStringResource = "Track Dates"
    static let hideDates: LocalizedStringResource = "Hide Dates"
    static let dateStarted: LocalizedStringResource = "Date Started"
    static let dateFinished: LocalizedStringResource = "Date Finished"
    static let droppedDatesLocked: LocalizedStringResource =
        "Dates are locked while this entry is dropped."
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
    static let markAsWatched: LocalizedStringResource = "Mark as Watched"
    static let markAsWatchedPromptTitle: LocalizedStringResource = "Mark as Watched?"
    static let updateDatesPromptTitle: LocalizedStringResource = "Update Dates?"
    static let later: LocalizedStringResource = "Later"
    static let setToNow: LocalizedStringResource = "Set to Now"
    static let clearDates: LocalizedStringResource = "Clear Dates"
    static let planToWatchDateSuggestionMessage: LocalizedStringResource =
        "You're setting this entry to Planned. Clear all tracked dates?"
    static let watchingDateSuggestionMessage: LocalizedStringResource =
        "You're setting this entry to Watching. Set the start date to now?"
    static let watchedDateSuggestionMessage: LocalizedStringResource =
        "You're setting this entry to Watched. Set the finish date to now?"
    static let seasonEpisodeProgressFinishedMessage: LocalizedStringResource =
        "You've watched through all episodes in this season."
    static let seriesEpisodeProgressFinishedMessage: LocalizedStringResource =
        "You've watched through every numbered season in this series."
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

extension EntryDetailL10n {
    static func dateSuggestionMessage(
        for suggestion: AnimeEntryDateUpdateSuggestion
    ) -> LocalizedStringResource {
        switch suggestion {
        case .clearAllDates:
            planToWatchDateSuggestionMessage
        case .setStartDateToNow:
            watchingDateSuggestionMessage
        case .setFinishDateToNow:
            watchedDateSuggestionMessage
        }
    }

    static func dateSuggestionActionTitle(
        for suggestion: AnimeEntryDateUpdateSuggestion
    ) -> LocalizedStringResource {
        switch suggestion {
        case .clearAllDates:
            clearDates
        case .setStartDateToNow, .setFinishDateToNow:
            setToNow
        }
    }
}
