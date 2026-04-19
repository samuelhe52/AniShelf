//
//  SchemaV2_6_0.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/19.
//

import Foundation
import SwiftData

public enum SchemaV2_6_0: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 6, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [AnimeEntry.self]
    }
}
