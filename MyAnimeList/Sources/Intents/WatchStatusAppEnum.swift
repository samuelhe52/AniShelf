//
//  WatchStatusAppEnum.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents
import DataProvider

/// App Intents mirror of `AnimeEntry.WatchStatus`.
///
/// App Intents metadata is extracted from types declared in the app target, so the
/// package enum is not conformed to `AppEnum` retroactively.
enum WatchStatusAppEnum: String, AppEnum {
    case planToWatch
    case watching
    case watched
    case dropped

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Watch Status"

    static let caseDisplayRepresentations: [WatchStatusAppEnum: DisplayRepresentation] = [
        .planToWatch: "Planned",
        .watching: "Watching",
        .watched: "Watched",
        .dropped: "Dropped",
    ]

    init(_ status: AnimeEntry.WatchStatus) {
        switch status {
        case .planToWatch: self = .planToWatch
        case .watching: self = .watching
        case .watched: self = .watched
        case .dropped: self = .dropped
        }
    }

    var watchStatus: AnimeEntry.WatchStatus {
        switch self {
        case .planToWatch: .planToWatch
        case .watching: .watching
        case .watched: .watched
        case .dropped: .dropped
        }
    }
}

/// App Intents mirror of the entry kind in `AnimeType`.
enum LibraryEntryKindAppEnum: String, AppEnum {
    case movie
    case series
    case season

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Entry Type"

    static let caseDisplayRepresentations: [LibraryEntryKindAppEnum: DisplayRepresentation] = [
        .movie: "Movie",
        .series: "TV Series",
        .season: "Season",
    ]

    init(_ type: AnimeType) {
        switch type {
        case .movie: self = .movie
        case .series: self = .series
        case .season: self = .season
        }
    }
}
