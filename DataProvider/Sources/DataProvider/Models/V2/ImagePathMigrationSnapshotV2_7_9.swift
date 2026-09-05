//
//  ImagePathMigrationSnapshotV2_7_9.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/9/5.
//

import Foundation
import SwiftData

struct ImagePathMigrationSnapshotV2_7_9: Sendable {
    struct EntryPaths: Sendable {
        let poster: String?
        let backdrop: String?
    }

    static let empty = ImagePathMigrationSnapshotV2_7_9(
        entries: [:],
        details: [:],
        characters: [:],
        staff: [:],
        seasons: [:],
        episodes: [:]
    )

    let entries: [Data: EntryPaths]
    let details: [Data: String]
    let characters: [Data: String]
    let staff: [Data: String]
    let seasons: [Data: String]
    let episodes: [Data: String]

    var count: Int {
        entries.count + details.count + characters.count + staff.count + seasons.count
            + episodes.count
    }
}

extension SchemaV2_7_9 {
    static func imagePathMigrationSnapshot(
        in context: ModelContext
    ) throws -> ImagePathMigrationSnapshotV2_7_9 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var entries: [Data: ImagePathMigrationSnapshotV2_7_9.EntryPaths] = [:]
        for entry in try context.fetch(FetchDescriptor<AnimeEntry>()) {
            let paths = ImagePathMigrationSnapshotV2_7_9.EntryPaths(
                poster: TMDbImagePath.storagePath(from: entry.posterURL),
                backdrop: TMDbImagePath.storagePath(from: entry.backdropURL)
            )
            guard paths.poster != nil || paths.backdrop != nil else { continue }
            entries[try encoder.encode(entry.persistentModelID)] = paths
        }

        return try ImagePathMigrationSnapshotV2_7_9(
            entries: entries,
            details: captureImagePaths(
                from: AnimeEntryDetail.self,
                in: context,
                encoder: encoder,
                predicate: #Predicate { $0.logoImageURL != nil },
                imageURL: \AnimeEntryDetail.logoImageURL
            ),
            characters: captureImagePaths(
                from: AnimeEntryCharacter.self,
                in: context,
                encoder: encoder,
                predicate: #Predicate { $0.profileURL != nil },
                imageURL: \AnimeEntryCharacter.profileURL
            ),
            staff: captureImagePaths(
                from: AnimeEntryStaff.self,
                in: context,
                encoder: encoder,
                predicate: #Predicate { $0.profileURL != nil },
                imageURL: \AnimeEntryStaff.profileURL
            ),
            seasons: captureImagePaths(
                from: AnimeEntrySeasonSummary.self,
                in: context,
                encoder: encoder,
                predicate: #Predicate { $0.posterURL != nil },
                imageURL: \AnimeEntrySeasonSummary.posterURL
            ),
            episodes: captureImagePaths(
                from: AnimeEntryEpisodeSummary.self,
                in: context,
                encoder: encoder,
                predicate: #Predicate { $0.imageURL != nil },
                imageURL: \AnimeEntryEpisodeSummary.imageURL
            )
        )
    }

    private static func captureImagePaths<Model: PersistentModel>(
        from modelType: Model.Type,
        in context: ModelContext,
        encoder: JSONEncoder,
        predicate: Predicate<Model>,
        imageURL: KeyPath<Model, URL?>
    ) throws -> [Data: String] {
        var paths: [Data: String] = [:]
        for model in try context.fetch(FetchDescriptor<Model>(predicate: predicate)) {
            guard let path = TMDbImagePath.storagePath(from: model[keyPath: imageURL]) else {
                continue
            }
            paths[try encoder.encode(model.persistentModelID)] = path
        }
        return paths
    }
}
