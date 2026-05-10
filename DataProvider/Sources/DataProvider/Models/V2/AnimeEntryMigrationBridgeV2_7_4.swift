//
//  AnimeEntryMigrationBridgeV2_7_4.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation

extension SchemaV2_7_4.AnimeEntry.WatchStatus {
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

extension SchemaV2_7_4.AnimeEntry {
    convenience init(
        migrationDTO dto: AnimeEntryMigrationDTO,
        detail: SchemaV2_7_4.AnimeEntryDetail?,
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
            score: dto.score,
            favorite: dto.favorite,
            notes: dto.notes,
            usingCustomPoster: dto.usingCustomPoster
        )
    }
}
