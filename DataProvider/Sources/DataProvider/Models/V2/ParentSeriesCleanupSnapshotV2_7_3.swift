//
//  ParentSeriesCleanupSnapshotV2_7_3.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/9/5.
//

import Foundation
import SwiftData

/// Only the entry metadata needed to choose parents; never materializes detail children.
struct ParentSeriesCleanupSnapshotV2_7_3 {
    let originalIndex: Int
    let oldID: PersistentIdentifier
    let parentSeriesOldID: PersistentIdentifier?
    let parentSeriesID: Int?
    let isRootSeriesEntry: Bool
    let tmdbID: Int
    let onDisplay: Bool
    let hasDetail: Bool
    let usingCustomPoster: Bool
    let dateSaved: Date
}

extension SchemaV2_7_3.AnimeEntry {
    func parentSeriesCleanupSnapshot(index: Int) -> ParentSeriesCleanupSnapshotV2_7_3 {
        let parentID = parentSeriesEntry?.persistentModelID
        return ParentSeriesCleanupSnapshotV2_7_3(
            originalIndex: index,
            oldID: persistentModelID,
            parentSeriesOldID: parentID,
            parentSeriesID: type.parentSeriesID,
            isRootSeriesEntry: parentID == nil && type == .series,
            tmdbID: tmdbID,
            onDisplay: onDisplay,
            hasDetail: detail != nil,
            usingCustomPoster: usingCustomPoster,
            dateSaved: dateSaved
        )
    }
}
