//
//  AnimeEntryMigrationBridgeV2_8_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation

extension SchemaV2_8_0.AnimeEntry.WatchStatus {
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

extension SchemaV2_8_0.AnimeEntry {
    convenience init(
        migrationDTO dto: AnimeEntryMigrationDTO,
        detail: SchemaV2_8_0.AnimeEntryDetail?,
        watchStatus: WatchStatus
    ) {
        let migratedPosterPath = TMDbImagePath.storagePath(from: dto.posterURL)
        self.init(
            name: dto.name,
            nameTranslations: dto.nameTranslations,
            overview: dto.overview,
            overviewTranslations: dto.overviewTranslations,
            onAirDate: dto.onAirDate,
            type: dto.type,
            linkToDetails: dto.linkToDetails,
            posterPath: migratedPosterPath,
            backdropPath: TMDbImagePath.storagePath(from: dto.backdropURL),
            customPosterPath: dto.usingCustomPoster ? migratedPosterPath : nil,
            tmdbID: dto.tmdbID,
            originalLanguageCode: dto.originalLanguageCode,
            detail: detail,
            parentSeriesEntry: nil,
            episodeProgresses: dto.episodeProgresses.map {
                SchemaV2_8_0.AnimeEntryEpisodeProgress(
                    seasonNumber: $0.seasonNumber,
                    watchedThroughEpisode: $0.watchedThroughEpisode,
                    updatedAt: $0.updatedAt
                )
            },
            onDisplay: dto.onDisplay,
            watchStatus: watchStatus,
            dateSaved: dto.dateSaved,
            dateStarted: dto.dateStarted,
            dateFinished: dto.dateFinished,
            isDateTrackingEnabled: dto.isDateTrackingEnabled,
            score: dto.score,
            favorite: dto.favorite,
            notes: dto.notes,
            usingCustomPoster: dto.usingCustomPoster,
            libraryUpdatedAt: dto.libraryUpdatedAt,
            trackingUpdatedAt: dto.trackingUpdatedAt
        )
    }
}
