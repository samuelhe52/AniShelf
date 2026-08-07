//
//  ModelContainerLoader.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import Foundation
import SwiftData

/// Loads a model container, using narrowly scoped compatibility measures when needed.
enum ModelContainerLoader {
    static func load(
        schema: Schema,
        configuration: ModelConfiguration,
        allowsRecovery: Bool
    ) throws -> ModelContainer {
        let makeCurrentContainer = {
            try ModelContainer(
                for: schema,
                migrationPlan: MigrationPlan.self,
                configurations: configuration
            )
        }
        let measures: [(name: String, attempt: () throws -> ModelContainer)] =
            allowsRecovery
            ? [
                (
                    "legacy-v2.6.0-bridge",
                    {
                        try bridgeLegacyV260Store(at: configuration.url)
                        return try makeCurrentContainer()
                    }
                )
            ] : []

        return try load(
            primary: makeCurrentContainer,
            recoveryMeasures: measures
        )
    }

    private static func bridgeLegacyV260Store(at storeURL: URL) throws {
        let bridgeSchema = Schema(versionedSchema: SchemaV2_7_0.self)
        let bridgeConfiguration = ModelConfiguration(
            schema: bridgeSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        _ = try ModelContainer(
            for: bridgeSchema,
            migrationPlan: LegacyV260BridgePlan.self,
            configurations: bridgeConfiguration
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
