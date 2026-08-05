//
//  LegacyV260MigrationStage.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import SwiftData

extension MigrationStage {
    static func migrateLegacyV260ToV270() -> MigrationStage {
        let snapshots = MigrationState<[AnimeEntryMigrationDTO]>([])

        return MigrationStage.custom(
            fromVersion: SchemaV2_6_0Legacy.self,
            toVersion: SchemaV2_7_0.self,
            willMigrate: { context in
                snapshots.set(
                    try Self.captureAndDeleteEntries(in: context) {
                        (index: Int, entry: SchemaV2_6_0Legacy.AnimeEntry) in
                        entry.migrationDTO(index: index)
                    })
            },
            didMigrate: { context in
                try Self.rebuildEntries(
                    from: snapshots.get(),
                    in: context,
                    makeEntry: { snapshot in
                        SchemaV2_7_0.AnimeEntry(
                            migrationDTO: snapshot,
                            detail: snapshot.detail.map(SchemaV2_7_0.AnimeEntryDetail.init(from:)),
                            watchStatus: .init(snapshot.watchStatus)
                        )
                    },
                    setParent: { entry, parentEntry in
                        entry.parentSeriesEntry = parentEntry
                    }
                )
            }
        )
    }
}
