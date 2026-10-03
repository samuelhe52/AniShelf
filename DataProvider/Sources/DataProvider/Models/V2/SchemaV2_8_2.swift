//
//  SchemaV2_8_2.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/2.
//

import Foundation
import SwiftData

public enum SchemaV2_8_2: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 8, 2)
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
