//
//  LibraryBatchAction.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/15.
//

import DataProvider

enum LibraryBatchAction: Equatable {
    case favorite(Bool)
    case dateTracking(Bool)
    case watchStatus(AnimeEntry.WatchStatus)
    case score(Int?)
    /// Adds or removes one category. `knownCategoryIDs` lets the write drop IDs of deleted categories.
    case category(LibraryCategory.ID, isMember: Bool, knownCategoryIDs: Set<LibraryCategory.ID>)

    /// Category changes keep the selection, so the Category menu can stay open
    /// and show the result while the user picks more categories.
    var endsMultiSelection: Bool {
        if case .category = self { return false }
        return true
    }

    func apply(to entries: [AnimeEntry]) {
        for entry in entries {
            apply(to: entry)
        }
    }

    private func apply(to entry: AnimeEntry) {
        switch self {
        case .favorite(let isFavorite):
            entry.updateFavorite(isFavorite)
        case .dateTracking(let isEnabled):
            entry.updateDateTrackingEnabled(isEnabled)
        case .watchStatus(let status):
            entry.updateWatchStatus(status)
        case .score(let score):
            entry.updateScore(score)
        case .category(let id, let isMember, let knownCategoryIDs):
            entry.updateCategoryMembership(id, isMember: isMember, knownCategoryIDs: knownCategoryIDs)
        }
    }
}
