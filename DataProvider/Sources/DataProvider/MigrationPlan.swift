//
//  MigrationPlan.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/10.
//

import Foundation
import SwiftData

enum MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV1.self,
            SchemaV2.self,
            SchemaV2_0_1.self,
            SchemaV2_1_0.self,
            SchemaV2_1_1.self,
            SchemaV2_2_0.self,
            SchemaV2_2_1.self,
            SchemaV2_3_0.self,
            SchemaV2_3_1.self,
            SchemaV2_3_2.self,
            SchemaV2_4_0.self,
            SchemaV2_4_1.self,
            SchemaV2_5_0.self,
            SchemaV2_6_0.self,
            SchemaV2_7_0.self,
            SchemaV2_7_1.self,
            SchemaV2_7_2.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV2_0_1.self),
            .migrateV201ToV210(),
            .lightweight(fromVersion: SchemaV2_1_0.self, toVersion: SchemaV2_1_1.self),
            .lightweight(fromVersion: SchemaV2_1_1.self, toVersion: SchemaV2_2_0.self),
            .lightweight(fromVersion: SchemaV2_2_0.self, toVersion: SchemaV2_2_1.self),
            .lightweight(fromVersion: SchemaV2_2_1.self, toVersion: SchemaV2_3_0.self),
            .lightweight(fromVersion: SchemaV2_3_0.self, toVersion: SchemaV2_3_1.self),
            .lightweight(fromVersion: SchemaV2_3_1.self, toVersion: SchemaV2_3_2.self),
            .lightweight(fromVersion: SchemaV2_3_2.self, toVersion: SchemaV2_4_0.self),
            .lightweight(fromVersion: SchemaV2_4_0.self, toVersion: SchemaV2_4_1.self),
            .lightweight(fromVersion: SchemaV2_4_1.self, toVersion: SchemaV2_5_0.self),
            .lightweight(fromVersion: SchemaV2_5_0.self, toVersion: SchemaV2_6_0.self),
            .migrateV260ToV270(),
            .migrateV270ToV271(),
            .lightweight(fromVersion: SchemaV2_7_1.self, toVersion: SchemaV2_7_2.self)
        ]
    }
}

extension MigrationStage {
    private struct AnimeEntryV270Snapshot {
        let oldID: PersistentIdentifier
        let parentSeriesOldID: PersistentIdentifier?
        let name: String
        let nameTranslations: [String: String]
        let overview: String?
        let overviewTranslations: [String: String]
        let onAirDate: Date?
        let type: AnimeType
        let linkToDetails: URL?
        let posterURL: URL?
        let backdropURL: URL?
        let tmdbID: Int
        let detail: LegacyAnimeEntryDetailPayload?
        let onDisplay: Bool
        let watchStatus: SchemaV2_6_0.AnimeEntry.WatchStatus
        let dateSaved: Date
        let dateStarted: Date?
        let dateFinished: Date?
        let favorite: Bool
        let notes: String
        let usingCustomPoster: Bool
    }

    private struct AnimeEntryV271Snapshot {
        let oldID: PersistentIdentifier
        let parentSeriesOldID: PersistentIdentifier?
        let name: String
        let nameTranslations: [String: String]
        let overview: String?
        let overviewTranslations: [String: String]
        let onAirDate: Date?
        let type: AnimeType
        let linkToDetails: URL?
        let posterURL: URL?
        let backdropURL: URL?
        let tmdbID: Int
        let detail: AnimeEntryDetailDTO?
        let onDisplay: Bool
        let watchStatus: SchemaV2_7_0.AnimeEntry.WatchStatus
        let dateSaved: Date
        let dateStarted: Date?
        let dateFinished: Date?
        let favorite: Bool
        let notes: String
        let usingCustomPoster: Bool
    }

    static func migrateV201ToV210() -> MigrationStage {
        var newEntries: [SchemaV2_1_0.AnimeEntry] = []

        return MigrationStage.custom(
            fromVersion: SchemaV2_0_1.self,
            toVersion: SchemaV2_1_0.self,
            willMigrate: { context in
                let descriptor = FetchDescriptor<SchemaV2_0_1.AnimeEntry>()
                let oldEntries = try context.fetch(descriptor)
                newEntries = oldEntries.map { old in
                    let type: AnimeType
                    switch old.entryType {
                    case .movie: type = .movie
                    case .tvSeries: type = .series
                    case .tvSeason(let seasonNumber, let parentSeriesID):
                        type = .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID)
                    }

                    let newEntry = SchemaV2_1_0.AnimeEntry(
                        name: old.name,
                        overview: old.overview,
                        onAirDate: old.onAirDate,
                        type: type,
                        linkToDetails: old.linkToDetails,
                        posterURL: old.posterURL,
                        backdropURL: old.backdropURL,
                        tmdbID: old.tmdbID,
                        useSeriesPoster: old.useSeriesPoster,
                        dateSaved: old.dateSaved,
                        dateStarted: old.dateStarted,
                        dateFinished: old.dateFinished
                    )
                    context.delete(old)
                    return newEntry
                }
                try context.save()
            },
            didMigrate: { context in
                for entry in newEntries {
                    context.insert(entry)
                }
                try context.save()
            }
        )
    }

    static func migrateV260ToV270() -> MigrationStage {
        var snapshots: [AnimeEntryV270Snapshot] = []

        return MigrationStage.custom(
            fromVersion: SchemaV2_6_0.self,
            toVersion: SchemaV2_7_0.self,
            willMigrate: { context in
                let descriptor = FetchDescriptor<SchemaV2_6_0.AnimeEntry>()
                let oldEntries = try context.fetch(descriptor)
                snapshots = oldEntries.map { old in
                    AnimeEntryV270Snapshot(
                        oldID: old.persistentModelID,
                        parentSeriesOldID: old.parentSeriesEntry?.persistentModelID,
                        name: old.name,
                        nameTranslations: old.nameTranslations,
                        overview: old.overview,
                        overviewTranslations: old.overviewTranslations,
                        onAirDate: old.onAirDate,
                        type: old.type,
                        linkToDetails: old.linkToDetails,
                        posterURL: old.posterURL,
                        backdropURL: old.backdropURL,
                        tmdbID: old.tmdbID,
                        detail: old.detail,
                        onDisplay: old.onDisplay,
                        watchStatus: old.watchStatus,
                        dateSaved: old.dateSaved,
                        dateStarted: old.dateStarted,
                        dateFinished: old.dateFinished,
                        favorite: old.favorite,
                        notes: old.notes,
                        usingCustomPoster: old.usingCustomPoster
                    )
                }

                for entry in oldEntries {
                    context.delete(entry)
                }
                try context.save()
            },
            didMigrate: { context in
                var newEntriesByOldID: [PersistentIdentifier: SchemaV2_7_0.AnimeEntry] = [:]

                for snapshot in snapshots {
                    let entry = SchemaV2_7_0.AnimeEntry(
                        name: snapshot.name,
                        nameTranslations: snapshot.nameTranslations,
                        overview: snapshot.overview,
                        overviewTranslations: snapshot.overviewTranslations,
                        onAirDate: snapshot.onAirDate,
                        type: snapshot.type,
                        linkToDetails: snapshot.linkToDetails,
                        posterURL: snapshot.posterURL,
                        backdropURL: snapshot.backdropURL,
                        tmdbID: snapshot.tmdbID,
                        detail: snapshot.detail.map(SchemaV2_7_0.AnimeEntryDetail.init(fromLegacy:)),
                        parentSeriesEntry: nil,
                        onDisplay: snapshot.onDisplay,
                        watchStatus: mapWatchStatus(snapshot.watchStatus),
                        dateSaved: snapshot.dateSaved,
                        dateStarted: snapshot.dateStarted,
                        dateFinished: snapshot.dateFinished,
                        favorite: snapshot.favorite,
                        notes: snapshot.notes,
                        usingCustomPoster: snapshot.usingCustomPoster
                    )
                    context.insert(entry)
                    newEntriesByOldID[snapshot.oldID] = entry
                }

                for snapshot in snapshots {
                    guard
                        let parentSeriesOldID = snapshot.parentSeriesOldID,
                        let entry = newEntriesByOldID[snapshot.oldID],
                        let parentEntry = newEntriesByOldID[parentSeriesOldID]
                    else {
                        continue
                    }
                    entry.parentSeriesEntry = parentEntry
                }

                try context.save()
            }
        )
    }

    static func migrateV270ToV271() -> MigrationStage {
        var snapshots: [AnimeEntryV271Snapshot] = []

        return MigrationStage.custom(
            fromVersion: SchemaV2_7_0.self,
            toVersion: SchemaV2_7_1.self,
            willMigrate: { context in
                let descriptor = FetchDescriptor<SchemaV2_7_0.AnimeEntry>()
                let oldEntries = try context.fetch(descriptor)
                snapshots = oldEntries.map { old in
                    AnimeEntryV271Snapshot(
                        oldID: old.persistentModelID,
                        parentSeriesOldID: old.parentSeriesEntry?.persistentModelID,
                        name: old.name,
                        nameTranslations: old.nameTranslations,
                        overview: old.overview,
                        overviewTranslations: old.overviewTranslations,
                        onAirDate: old.onAirDate,
                        type: old.type,
                        linkToDetails: old.linkToDetails,
                        posterURL: old.posterURL,
                        backdropURL: old.backdropURL,
                        tmdbID: old.tmdbID,
                        detail: old.detail.map { Self.detailDTO(from: $0) },
                        onDisplay: old.onDisplay,
                        watchStatus: old.watchStatus,
                        dateSaved: old.dateSaved,
                        dateStarted: old.dateStarted,
                        dateFinished: old.dateFinished,
                        favorite: old.favorite,
                        notes: old.notes,
                        usingCustomPoster: old.usingCustomPoster
                    )
                }

                for entry in oldEntries {
                    context.delete(entry)
                }
                try context.save()
            },
            didMigrate: { context in
                var newEntriesByOldID: [PersistentIdentifier: SchemaV2_7_1.AnimeEntry] = [:]

                for snapshot in snapshots {
                    let detail = snapshot.detail.map(SchemaV2_7_1.AnimeEntryDetail.init(from:))
                    let entry = SchemaV2_7_1.AnimeEntry(
                        name: snapshot.name,
                        nameTranslations: snapshot.nameTranslations,
                        overview: snapshot.overview,
                        overviewTranslations: snapshot.overviewTranslations,
                        onAirDate: snapshot.onAirDate,
                        type: snapshot.type,
                        linkToDetails: snapshot.linkToDetails,
                        posterURL: snapshot.posterURL,
                        backdropURL: snapshot.backdropURL,
                        tmdbID: snapshot.tmdbID,
                        detail: detail,
                        parentSeriesEntry: nil,
                        onDisplay: snapshot.onDisplay,
                        watchStatus: mapWatchStatus(snapshot.watchStatus),
                        dateSaved: snapshot.dateSaved,
                        dateStarted: snapshot.dateStarted,
                        dateFinished: snapshot.dateFinished,
                        favorite: snapshot.favorite,
                        notes: snapshot.notes,
                        usingCustomPoster: snapshot.usingCustomPoster
                    )
                    context.insert(entry)
                    newEntriesByOldID[snapshot.oldID] = entry
                }

                for snapshot in snapshots {
                    guard
                        let parentSeriesOldID = snapshot.parentSeriesOldID,
                        let entry = newEntriesByOldID[snapshot.oldID],
                        let parentEntry = newEntriesByOldID[parentSeriesOldID]
                    else {
                        continue
                    }
                    entry.parentSeriesEntry = parentEntry
                }

                try context.save()
            }
        )
    }

    private static func mapWatchStatus(
        _ status: SchemaV2_6_0.AnimeEntry.WatchStatus
    ) -> SchemaV2_7_0.AnimeEntry.WatchStatus {
        switch status {
        case .planToWatch:
            .planToWatch
        case .watching:
            .watching
        case .watched:
            .watched
        case .dropped:
            .dropped
        }
    }

    private static func mapWatchStatus(
        _ status: SchemaV2_7_0.AnimeEntry.WatchStatus
    ) -> SchemaV2_7_1.AnimeEntry.WatchStatus {
        switch status {
        case .planToWatch:
            .planToWatch
        case .watching:
            .watching
        case .watched:
            .watched
        case .dropped:
            .dropped
        }
    }

    private static func detailDTO(
        from detail: SchemaV2_7_0.AnimeEntryDetail
    ) -> AnimeEntryDetailDTO {
        AnimeEntryDetailDTO(
            language: detail.language,
            title: detail.title,
            subtitle: detail.subtitle,
            overview: detail.overview,
            status: detail.status,
            airDate: detail.airDate,
            primaryLinkURL: detail.primaryLinkURL,
            heroImageURL: detail.heroImageURL,
            logoImageURL: detail.logoImageURL,
            genreIDs: detail.genreIDs,
            voteAverage: detail.voteAverage,
            runtimeMinutes: detail.runtimeMinutes,
            episodeCount: detail.episodeCount,
            seasonCount: detail.seasonCount,
            characters: detail.characters.map {
                AnimeEntryCharacterDTO(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profileURL: $0.profileURL
                )
            },
            staff: detail.staff.map {
                AnimeEntryStaffDTO(
                    id: $0.id,
                    name: $0.name,
                    role: $0.role,
                    department: $0.department,
                    profileURL: $0.profileURL
                )
            },
            seasons: detail.seasons.map {
                AnimeEntrySeasonSummaryDTO(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.title,
                    posterURL: $0.posterURL
                )
            },
            episodes: detail.episodes.sorted {
                if $0.episodeNumber == $1.episodeNumber { return $0.id < $1.id }
                return $0.episodeNumber < $1.episodeNumber
            }.map {
                AnimeEntryEpisodeSummaryDTO(
                    id: $0.id,
                    episodeNumber: $0.episodeNumber,
                    title: $0.title,
                    airDate: $0.airDate,
                    imageURL: $0.imageURL
                )
            }
        )
    }
}
