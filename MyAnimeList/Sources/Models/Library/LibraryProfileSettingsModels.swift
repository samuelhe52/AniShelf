//
//  LibraryProfileSettingsModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/6.
//

import DataProvider
import SwiftUI

enum LibraryProfileSettingsHubColumns: Equatable {
    case single
    case double
}

struct LibraryProfileSettingsLayoutPolicy {
    func hubColumns(
        horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> LibraryProfileSettingsHubColumns {
        guard horizontalSizeClass == .regular, !dynamicTypeSize.isAccessibilitySize else {
            return .single
        }
        return .double
    }
}

enum LibraryProfileSettingsDestination: Hashable, CaseIterable {
    case libraryTracking, appearance, reminders, metadataImages, syncData

    var title: LocalizedStringResource {
        switch self {
        case .libraryTracking: "Library & Tracking"
        case .appearance: "Appearance & Interaction"
        case .reminders: "Airing & Reminders"
        case .metadataImages: "Metadata & Images"
        case .syncData: "Sync & Data"
        }
    }

    /// Hub order walks one continuous hue spectrum after the inline language row at step 0;
    /// each page tints its cards with its step.
    var tint: Color {
        switch self {
        case .libraryTracking: LibraryProfileSettingsPalette.step(1)
        case .appearance: LibraryProfileSettingsPalette.step(2)
        case .reminders: LibraryProfileSettingsPalette.step(3)
        case .metadataImages: LibraryProfileSettingsPalette.step(4)
        case .syncData: LibraryProfileSettingsPalette.step(5)
        }
    }
}

enum LibraryProfileSettingsPalette {
    /// The anime info language row sits inline in the hub Settings card, ahead of the destinations.
    static var language: Color { step(0) }

    /// Teal at step 0, then blue, indigo, violet; the App Info rows continue into pink and rose.
    static func step(_ index: Int) -> Color {
        let hue = (0.47 + 0.07 * Double(index)).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.62, brightness: 0.86)
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
