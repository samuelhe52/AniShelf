//
//  AnimeEntryMigrationBridgeV2_7_9.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation
import SwiftData

extension AnimeEntryMigrationWatchStatus {
    init(_ status: SchemaV2_7_9.AnimeEntry.WatchStatus) {
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

extension SchemaV2_7_9.AnimeEntry {
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
            originalLanguageCode: originalLanguageCode,
            detail: detail?.migrationDTO(),
            episodeProgresses: episodeProgresses.map {
                AnimeEntryEpisodeProgressMigrationDTO(
                    seasonNumber: $0.seasonNumber,
                    watchedThroughEpisode: $0.watchedThroughEpisode,
                    updatedAt: $0.updatedAt
                )
            },
            onDisplay: onDisplay,
            watchStatus: .init(watchStatus),
            dateSaved: dateSaved,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            isDateTrackingEnabled: isDateTrackingEnabled,
            score: score,
            favorite: favorite,
            notes: notes,
            usingCustomPoster: usingCustomPoster,
            libraryUpdatedAt: libraryUpdatedAt,
            trackingUpdatedAt: trackingUpdatedAt
        )
    }
}
