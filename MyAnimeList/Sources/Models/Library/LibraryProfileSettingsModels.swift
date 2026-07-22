//
//  LibraryProfileSettingsModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/6.
//

import DataProvider
import SwiftUI

enum LibraryProfileSettingsLayout: Equatable {
    case compactScroll
    case wideGrid
}

struct LibraryProfileSettingsLayoutPolicy {
    func layout(
        horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> LibraryProfileSettingsLayout {
        guard horizontalSizeClass == .regular, !dynamicTypeSize.isAccessibilitySize else {
            return .compactScroll
        }
        return .wideGrid
    }
}

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
    let totalRuntimeMinutes: Int
    let watchedRuntimeMinutes: Int
    let plannedRuntimeMinutes: Int

    static func runtimeDescription(minutes: Int) -> String {
        guard minutes > 0 else { return String(localized: "N/A") }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainingMinutes)m"
    }

    var totalRuntimeDescription: String {
        Self.runtimeDescription(minutes: totalRuntimeMinutes)
    }

    var watchedRuntimeDescription: String {
        Self.runtimeDescription(minutes: watchedRuntimeMinutes)
    }

    var plannedRuntimeDescription: String {
        Self.runtimeDescription(minutes: plannedRuntimeMinutes)
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
        totalRuntimeMinutes = Self.runtimeMinutes(for: entries)
        watchedRuntimeMinutes = Self.runtimeMinutes(for: entries) { $0.watchStatus == .watched }
        plannedRuntimeMinutes = Self.runtimeMinutes(for: entries) { $0.watchStatus == .planToWatch }
    }

    private static func runtimeMinutes(
        for entries: [AnimeEntry],
        where shouldInclude: (AnimeEntry) -> Bool = { _ in true }
    ) -> Int {
        entries.reduce(0) { partialResult, entry in
            guard shouldInclude(entry), let runtime = entry.detail?.runtimeMinutes else {
                return partialResult
            }
            let multiplier = max(entry.detail?.episodeCount ?? 1, 1)
            return partialResult + runtime * multiplier
        }
    }
}

enum LibraryProfileRuntimeMode: Equatable {
    case total
    case watched
    case planned

    mutating func advance() {
        switch self {
        case .total:
            self = .watched
        case .watched:
            self = .planned
        case .planned:
            self = .total
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .total:
            "Runtime"
        case .watched:
            "Watched Runtime"
        case .planned:
            "Planned Runtime"
        }
    }

    var accessibilityHint: LocalizedStringResource {
        "Tap to cycle runtime statistics."
    }

    func description(for stats: LibraryProfileStats) -> String {
        switch self {
        case .total:
            stats.totalRuntimeDescription
        case .watched:
            stats.watchedRuntimeDescription
        case .planned:
            stats.plannedRuntimeDescription
        }
    }
}

enum LibraryProfileMaintenancePalette {
    static let apiKey = Color(red: 0.38, green: 0.72, blue: 0.98)
    static let cache = Color(red: 0.29, green: 0.77, blue: 0.90)
    static let refresh = Color(red: 0.45, green: 0.62, blue: 0.96)
    static let prefetch = Color(red: 0.33, green: 0.80, blue: 0.74)
    static let support = Color(red: 0.98, green: 0.64, blue: 0.28)
    static let whatsNew = Color(red: 0.95, green: 0.62, blue: 0.33)
    static let about = Color(red: 0.58, green: 0.64, blue: 0.74)
    static let panel = Color(red: 0.42, green: 0.58, blue: 0.76)
}

enum LibraryProfileSettingsSheet: String, Identifiable {
    case changeAPIKey
    case support
    case about

    var id: String { rawValue }
}

struct LibraryProfileSettingsPresentationState: Equatable {
    var presentedSheet: LibraryProfileSettingsSheet?

    mutating func present(_ sheet: LibraryProfileSettingsSheet) {
        presentedSheet = sheet
    }

    mutating func presentSupportSheet() {
        present(.support)
    }
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
