//
//  AnimeEntryDuplicateResolver.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider

enum AnimeEntryDuplicateResolver {
    static func preferredEntry(from entries: some Sequence<AnimeEntry>) -> AnimeEntry? {
        entries.sorted(by: prefers).first
    }

    static func prefers(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        if lhs.onDisplay != rhs.onDisplay {
            return lhs.onDisplay && !rhs.onDisplay
        }

        if lhs.childSeasonEntries.count != rhs.childSeasonEntries.count {
            return lhs.childSeasonEntries.count > rhs.childSeasonEntries.count
        }

        if (lhs.detail != nil) != (rhs.detail != nil) {
            return lhs.detail != nil
        }

        if lhs.dateSaved != rhs.dateSaved {
            return lhs.dateSaved > rhs.dateSaved
        }

        return lhs.name < rhs.name
    }
}
