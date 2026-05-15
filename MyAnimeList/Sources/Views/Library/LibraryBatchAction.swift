//
//  LibraryBatchAction.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/15.
//

import DataProvider

enum LibraryBatchAction: Equatable {
    case favorite(Bool)
    case dateTracking(Bool)
    case watchStatus(AnimeEntry.WatchStatus)
    case score(Int?)

    func apply(to entries: [AnimeEntry]) {
        for entry in entries {
            apply(to: entry)
        }
    }

    private func apply(to entry: AnimeEntry) {
        switch self {
        case .favorite(let isFavorite):
            entry.favorite = isFavorite
        case .dateTracking(let isEnabled):
            entry.setDateTrackingEnabled(isEnabled)
        case .watchStatus(let status):
            entry.setWatchStatus(status)
        case .score(let score):
            entry.setScore(score)
        }
    }
}
