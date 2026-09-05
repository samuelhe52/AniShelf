//
//  ImagePathMigrationBridgeV2_8_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/9/5.
//

import Foundation
import SwiftData

extension SchemaV2_8_0 {
    static func applyImagePathMigrationSnapshot(
        _ snapshot: ImagePathMigrationSnapshotV2_7_9,
        in context: ModelContext
    ) throws {
        guard snapshot.count > 0 else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var matchedCount = 0

        try apply(snapshot.entries, to: AnimeEntry.self, in: context, encoder: encoder) {
            entry,
            paths in
            entry.posterPath = paths.poster
            entry.backdropPath = paths.backdrop
            entry.customPosterPath = entry.usingCustomPoster ? paths.poster : nil
            matchedCount += 1
        }
        try apply(snapshot.details, to: AnimeEntryDetail.self, in: context, encoder: encoder) {
            $0.logoImagePath = $1
            matchedCount += 1
        }
        try apply(snapshot.characters, to: AnimeEntryCharacter.self, in: context, encoder: encoder) {
            $0.profilePath = $1
            matchedCount += 1
        }
        try apply(snapshot.staff, to: AnimeEntryStaff.self, in: context, encoder: encoder) {
            $0.profilePath = $1
            matchedCount += 1
        }
        try apply(snapshot.seasons, to: AnimeEntrySeasonSummary.self, in: context, encoder: encoder) {
            $0.posterPath = $1
            matchedCount += 1
        }
        try apply(snapshot.episodes, to: AnimeEntryEpisodeSummary.self, in: context, encoder: encoder) {
            $0.imagePath = $1
            matchedCount += 1
        }

        guard matchedCount == snapshot.count else {
            throw ImagePathMigrationError.unmatchedModels(
                expected: snapshot.count,
                matched: matchedCount
            )
        }
        try context.save()
    }

    private static func apply<Model: PersistentModel, Value>(
        _ valuesByIdentifier: [Data: Value],
        to modelType: Model.Type,
        in context: ModelContext,
        encoder: JSONEncoder,
        update: (Model, Value) -> Void
    ) throws {
        guard valuesByIdentifier.isEmpty == false else { return }

        for identifier in try context.fetchIdentifiers(FetchDescriptor<Model>()) {
            guard let value = valuesByIdentifier[try encoder.encode(identifier)] else { continue }
            guard let model = context.model(for: identifier) as? Model else {
                throw ImagePathMigrationError.missingTargetModel(identifier)
            }
            update(model, value)
        }
    }
}

fileprivate enum ImagePathMigrationError: Error {
    case missingTargetModel(PersistentIdentifier)
    case unmatchedModels(expected: Int, matched: Int)
}
