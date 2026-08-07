//
//  LegacyV260MigrationPlan.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/5.
//

import SwiftData

/// A recovery-only path for stores written by the released V2.6.0 model before
/// its shared payload definition was changed in place.
enum LegacyV260MigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV2_6_0Legacy.self,
            SchemaV2_7_0.self,
            SchemaV2_7_1.self,
            SchemaV2_7_2.self,
            SchemaV2_7_3.self,
            SchemaV2_7_4.self,
            SchemaV2_7_5.self,
            SchemaV2_7_6.self,
            SchemaV2_7_7.self,
            SchemaV2_7_8.self,
            SchemaV2_7_9.self,
            SchemaV2_8_0.self,
            SchemaV2_8_1.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .migrateLegacyV260ToV270(),
            .migrateV270ToV271(),
            .lightweight(fromVersion: SchemaV2_7_1.self, toVersion: SchemaV2_7_2.self),
            .lightweight(fromVersion: SchemaV2_7_2.self, toVersion: SchemaV2_7_3.self),
            .migrateV273ToV274(),
            .lightweight(fromVersion: SchemaV2_7_4.self, toVersion: SchemaV2_7_5.self),
            .lightweight(fromVersion: SchemaV2_7_5.self, toVersion: SchemaV2_7_6.self),
            .lightweight(fromVersion: SchemaV2_7_6.self, toVersion: SchemaV2_7_7.self),
            .lightweight(fromVersion: SchemaV2_7_7.self, toVersion: SchemaV2_7_8.self),
            .lightweight(fromVersion: SchemaV2_7_8.self, toVersion: SchemaV2_7_9.self),
            .migrateV279ToV280(),
            .lightweight(fromVersion: SchemaV2_8_0.self, toVersion: SchemaV2_8_1.self)
        ]
    }
}
