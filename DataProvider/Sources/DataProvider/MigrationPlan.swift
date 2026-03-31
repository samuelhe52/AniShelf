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
            SchemaV2_5_0.self
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
            .lightweight(fromVersion: SchemaV2_4_1.self, toVersion: SchemaV2_5_0.self)
        ]
    }
}

extension MigrationStage {
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
}
