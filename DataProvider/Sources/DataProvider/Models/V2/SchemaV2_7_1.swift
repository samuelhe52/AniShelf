//
//  SchemaV2_7_1.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation
import SwiftData

public enum SchemaV2_7_1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 7, 1)
    }

    public static var models: [any PersistentModel.Type] {
        [
            AnimeEntry.self,
            AnimeEntryDetail.self,
            AnimeEntryCharacter.self,
            AnimeEntryStaff.self,
            AnimeEntrySeasonSummary.self,
            AnimeEntryEpisodeSummary.self
        ]
    }
}
