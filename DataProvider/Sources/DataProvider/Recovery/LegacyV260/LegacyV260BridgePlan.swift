//
//  LegacyV260BridgePlan.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/7.
//

import SwiftData

/// A recovery-only bridge from the released V2.6.0 model into the canonical migration history.
///
/// Once bridged, the ordinary migration plan takes over.
enum LegacyV260BridgePlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV2_6_0Legacy.self,
            SchemaV2_7_0.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .migrateLegacyV260ToV270()
        ]
    }
}
