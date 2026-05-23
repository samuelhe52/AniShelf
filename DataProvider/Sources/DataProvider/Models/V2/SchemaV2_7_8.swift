//
//  SchemaV2_7_8.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/21.
//

import Foundation
import SwiftData

public enum SchemaV2_7_8: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 7, 8)
    }

    public static var models: [any PersistentModel.Type] {
        [
            AnimeEntry.self,
            AnimeEntryDetail.self,
            AnimeEntryCharacter.self,
            AnimeEntryStaff.self,
            AnimeEntryStaffJob.self,
            AnimeEntrySeasonSummary.self,
            AnimeEntryEpisodeSummary.self,
            AnimeEntryEpisodeProgress.self
        ]
    }
}
