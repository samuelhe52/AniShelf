//
//  SchemaV2_7_5.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/12.
//

import Foundation
import SwiftData

public enum SchemaV2_7_5: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 7, 5)
    }

    public static var models: [any PersistentModel.Type] {
        [
            AnimeEntry.self,
            AnimeEntryDetail.self,
            AnimeEntryCharacter.self,
            AnimeEntryStaff.self,
            AnimeEntryStaffJob.self,
            AnimeEntrySeasonSummary.self,
            AnimeEntryEpisodeSummary.self
        ]
    }
}
