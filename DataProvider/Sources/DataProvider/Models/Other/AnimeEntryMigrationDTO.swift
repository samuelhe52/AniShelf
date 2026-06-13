//
//  AnimeEntryMigrationDTO.swift
//  DataProvider
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
import SwiftData

enum AnimeEntryMigrationWatchStatus: Sendable {
    case planToWatch
    case watching
    case watched
    case dropped
}

struct AnimeEntryEpisodeProgressMigrationDTO: Sendable {
    var seasonNumber: Int
    var watchedThroughEpisode: Int
    var updatedAt: Date
}

struct AnimeEntryMigrationDTO: Sendable {
    var originalIndex: Int
    var oldID: PersistentIdentifier
    var parentSeriesOldID: PersistentIdentifier?
    var name: String
    var nameTranslations: [String: String]
    var overview: String?
    var overviewTranslations: [String: String]
    var onAirDate: Date?
    var type: AnimeType
    var linkToDetails: URL?
    var posterURL: URL?
    var backdropURL: URL?
    var tmdbID: Int
    var originalLanguageCode: String? = nil
    var detail: AnimeEntryDetailDTO?
    var episodeProgresses: [AnimeEntryEpisodeProgressMigrationDTO] = []
    var onDisplay: Bool
    var watchStatus: AnimeEntryMigrationWatchStatus
    var dateSaved: Date
    var dateStarted: Date?
    var dateFinished: Date?
    var isDateTrackingEnabled: Bool = true
    var score: Int?
    var favorite: Bool
    var notes: String
    var usingCustomPoster: Bool
    var libraryUpdatedAt: Date?
    var trackingUpdatedAt: Date?

    var isRootSeriesEntry: Bool {
        parentSeriesOldID == nil && type == .series
    }

    var parentSeriesID: Int? {
        type.parentSeriesID
    }

    var hasDetail: Bool {
        detail != nil
    }
}
