//
//  LibraryProfileSettingsModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/6.
//

import DataProvider
import SwiftUI

struct LibraryProfileStats: Equatable {
    let totalCount: Int
    let watchedCount: Int
    let watchingCount: Int
    let planToWatchCount: Int
    let droppedCount: Int
    let favoriteCount: Int
    let movieCount: Int
    let seriesCount: Int
    let seasonCount: Int
    let entriesWithNotesCount: Int
    let runtimeMinutes: Int

    var runtimeDescription: String {
        guard runtimeMinutes > 0 else { return String(localized: "N/A") }
        let hours = runtimeMinutes / 60
        let minutes = runtimeMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    init(entries: [AnimeEntry]) {
        totalCount = entries.count
        watchedCount = entries.count { $0.watchStatus == .watched }
        watchingCount = entries.count { $0.watchStatus == .watching }
        planToWatchCount = entries.count { $0.watchStatus == .planToWatch }
        droppedCount = entries.count { $0.watchStatus == .dropped }
        favoriteCount = entries.count { $0.favorite }
        movieCount = entries.count { $0.type == .movie }
        seriesCount = entries.count { $0.type == .series }
        seasonCount = entries.count {
            if case .season = $0.type {
                true
            } else {
                false
            }
        }
        entriesWithNotesCount = entries.count { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        runtimeMinutes = entries.reduce(0) { partialResult, entry in
            guard let runtime = entry.detail?.runtimeMinutes else {
                return partialResult
            }
            let multiplier = max(entry.detail?.episodeCount ?? 1, 1)
            return partialResult + runtime * multiplier
        }
    }
}

enum LibraryProfileMaintenancePalette {
    static let apiKey = Color(red: 0.38, green: 0.72, blue: 0.98)
    static let cache = Color(red: 0.29, green: 0.77, blue: 0.90)
    static let refresh = Color(red: 0.45, green: 0.62, blue: 0.96)
    static let prefetch = Color(red: 0.33, green: 0.80, blue: 0.74)
    static let whatsNew = Color(red: 0.95, green: 0.62, blue: 0.33)
    static let about = Color(red: 0.58, green: 0.64, blue: 0.74)
    static let panel = Color(red: 0.42, green: 0.58, blue: 0.76)
}

extension AnimeEntry.WatchStatus {
    var defaultPickerTintColor: Color {
        switch self {
        case .planToWatch:
            .mint
        default:
            libraryTintColor
        }
    }
}
