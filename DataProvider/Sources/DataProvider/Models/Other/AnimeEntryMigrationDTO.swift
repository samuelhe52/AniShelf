//
//  AnimeEntryMigrationDTO.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import SwiftData

enum AnimeEntryMigrationWatchStatus {
    case planToWatch
    case watching
    case watched
    case dropped
}

struct AnimeEntryMigrationDTO {
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
    var detail: AnimeEntryDetailDTO?
    var onDisplay: Bool
    var watchStatus: AnimeEntryMigrationWatchStatus
    var dateSaved: Date
    var dateStarted: Date?
    var dateFinished: Date?
    var score: Int?
    var favorite: Bool
    var notes: String
    var usingCustomPoster: Bool

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
