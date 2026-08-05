//
//  ModelContainerLoader.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import SwiftData

/// Loads a model container, using narrowly scoped compatibility measures when needed.
enum ModelContainerLoader {
    static func load(
        schema: Schema,
        configuration: ModelConfiguration,
        allowsRecovery: Bool
    ) throws -> ModelContainer {
        let measures: [(name: String, attempt: () throws -> ModelContainer)] =
            allowsRecovery
            ? [
                (
                    "legacy-v2.6.0-migration",
                    {
                        try ModelContainer(
                            for: schema,
                            migrationPlan: LegacyV260MigrationPlan.self,
                            configurations: configuration
                        )
                    }
                )
            ] : []

        return try load(
            primary: {
                try ModelContainer(
                    for: schema,
                    migrationPlan: MigrationPlan.self,
                    configurations: configuration
                )
            },
            recoveryMeasures: measures
        )
    }

    static func load<Result>(
        primary: () throws -> Result,
        recoveryMeasures: [(name: String, attempt: () throws -> Result)]
    ) throws -> Result {
        do {
            return try primary()
        } catch let primaryError {
            for measure in recoveryMeasures {
                do {
                    let result = try measure.attempt()
                    dataProviderLogger.notice(
                        "Recovery measure \(measure.name, privacy: .public) succeeded"
                    )
                    return result
                } catch {
                    dataProviderLogger.info(
                        "Recovery measure \(measure.name, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }

            throw primaryError
        }
    }
}
