//
//  SchemaV2_5_0.swift
//  MyAnimeList
//
//  Created by Samuel He on 2026/3/31.
//

import Foundation
import SwiftData

public enum SchemaV2_5_0: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        .init(2, 5, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [AnimeEntry.self]
    }
}
