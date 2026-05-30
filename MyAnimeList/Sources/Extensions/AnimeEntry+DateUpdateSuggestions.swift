//
//  AnimeEntry+DateUpdateSuggestions.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import DataProvider
import Foundation

enum AnimeEntryDateUpdateSuggestion: Equatable, Identifiable {
    case clearAllDates
    case setStartDateToNow
    case setFinishDateToNow

    var id: Self { self }
}

extension AnimeEntry {
    func dateUpdateSuggestion(forTargetStatus status: WatchStatus) -> AnimeEntryDateUpdateSuggestion? {
        switch status {
        case .planToWatch:
            guard dateStarted != nil || dateFinished != nil else { return nil }
            return .clearAllDates
        case .watching:
            return dateStarted == nil ? .setStartDateToNow : nil
        case .watched:
            return dateFinished == nil ? .setFinishDateToNow : nil
        case .dropped:
            return nil
        }
    }

    func applyDateUpdateSuggestion(_ suggestion: AnimeEntryDateUpdateSuggestion, now: Date = .now) {
        switch suggestion {
        case .clearAllDates:
            dateStarted = nil
            dateFinished = nil
        case .setStartDateToNow:
            dateStarted = now
        case .setFinishDateToNow:
            dateFinished = now
        }
        markTrackingModified(at: now)
    }
}
