//
//  SchemaV2_8_5.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/26.
//

import Foundation
import SwiftData

public enum SchemaV2_8_5: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 8, 5)
    }

    public static var models: [any PersistentModel.Type] {
        [
            AnimeEntry.self,
            AnimeEntryDetail.self,
            AnimeEntryProductionCompany.self,
            AnimeEntryCharacter.self,
            AnimeEntryStaff.self,
            AnimeEntryStaffJob.self,
            AnimeEntrySeasonSummary.self,
            AnimeEntryEpisodeSummary.self,
            AnimeEntryEpisodeProgress.self
        ]
    }
}
