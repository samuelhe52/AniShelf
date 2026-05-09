//
//  AnimeEntryDetailOrderingV2_7_2.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation

extension SchemaV2_7_2.AnimeEntryDetail {
    public var orderedCharacters: [AnimeEntryCharacter] {
        characters.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedStaff: [AnimeEntryStaff] {
        staff.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedEpisodes: [AnimeEntryEpisodeSummary] {
        episodes.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.episodeNumber < $1.episodeNumber
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}
