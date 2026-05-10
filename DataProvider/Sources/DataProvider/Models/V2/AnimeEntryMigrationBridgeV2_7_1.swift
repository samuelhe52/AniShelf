//
//  AnimeEntryMigrationBridgeV2_7_1.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import SwiftData

extension AnimeEntryMigrationWatchStatus {
    init(_ status: SchemaV2_7_1.AnimeEntry.WatchStatus) {
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

extension SchemaV2_7_1.AnimeEntry.WatchStatus {
    init(_ status: AnimeEntryMigrationWatchStatus) {
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

extension SchemaV2_7_1.AnimeEntry {
    convenience init(
        migrationDTO dto: AnimeEntryMigrationDTO,
        detail: SchemaV2_7_1.AnimeEntryDetail?,
        watchStatus: WatchStatus
    ) {
        self.init(
            name: dto.name,
            nameTranslations: dto.nameTranslations,
            overview: dto.overview,
            overviewTranslations: dto.overviewTranslations,
            onAirDate: dto.onAirDate,
            type: dto.type,
            linkToDetails: dto.linkToDetails,
            posterURL: dto.posterURL,
            backdropURL: dto.backdropURL,
            tmdbID: dto.tmdbID,
            detail: detail,
            parentSeriesEntry: nil,
            onDisplay: dto.onDisplay,
            watchStatus: watchStatus,
            dateSaved: dto.dateSaved,
            dateStarted: dto.dateStarted,
            dateFinished: dto.dateFinished,
            favorite: dto.favorite,
            notes: dto.notes,
            usingCustomPoster: dto.usingCustomPoster
        )
    }

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
            detail: detail?.migrationDTO(),
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
