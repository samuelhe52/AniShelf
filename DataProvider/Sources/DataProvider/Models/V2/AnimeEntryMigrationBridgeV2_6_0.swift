//
//  AnimeEntryMigrationBridgeV2_6_0.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import SwiftData

extension AnimeEntryMigrationWatchStatus {
    init(_ status: SchemaV2_6_0.AnimeEntry.WatchStatus) {
        switch status {
        case .planToWatch:
            self = .planToWatch
        case .watching:
            self = .watching
        case .watched:
            self = .watched
        case .dropped:
            self = .dropped
        }
    }
}

extension SchemaV2_6_0.AnimeEntry {
    func migrationDTO(index: Int) -> AnimeEntryMigrationDTO {
        AnimeEntryMigrationDTO(
            originalIndex: index,
            oldID: persistentModelID,
            parentSeriesOldID: parentSeriesEntry?.persistentModelID,
            name: name,
            nameTranslations: nameTranslations,
            overview: overview,
            overviewTranslations: overviewTranslations,
            onAirDate: onAirDate,
            type: type,
            linkToDetails: linkToDetails,
            posterURL: posterURL,
            backdropURL: backdropURL,
            tmdbID: tmdbID,
            detail: detail.map(AnimeEntryDetailDTO.init(fromLegacy:)),
            onDisplay: onDisplay,
            watchStatus: .init(watchStatus),
            dateSaved: dateSaved,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            score: nil,
            favorite: favorite,
            notes: notes,
            usingCustomPoster: usingCustomPoster
        )
    }
}
