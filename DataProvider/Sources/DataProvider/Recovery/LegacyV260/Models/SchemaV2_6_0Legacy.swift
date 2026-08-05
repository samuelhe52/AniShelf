//
//  SchemaV2_6_0Legacy.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/5.
//

import Foundation
import SwiftData

enum SchemaV2_6_0Legacy: VersionedSchema {
    /// Recovery-only identifier.
    ///
    /// The store is recognized by its model hash;
    /// this must differ from the later V2.6.0 variant to keep staged checksums unique.
    static var versionIdentifier: Schema.Version { .init(2, 5, 9) }

    static var models: [any PersistentModel.Type] { [AnimeEntry.self] }
}
