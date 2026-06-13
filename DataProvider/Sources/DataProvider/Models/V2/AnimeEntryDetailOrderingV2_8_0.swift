//
//  AnimeEntryDetailOrderingV2_8_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation

extension SchemaV2_8_0.AnimeEntryDetail {
    public var orderedCharacters: [SchemaV2_8_0.AnimeEntryCharacter] {
        characters.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedStaff: [SchemaV2_8_0.AnimeEntryStaff] {
        staff.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedEpisodes: [SchemaV2_8_0.AnimeEntryEpisodeSummary] {
        episodes.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.episodeNumber < $1.episodeNumber
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}

extension SchemaV2_8_0.AnimeEntryStaff {
    public var orderedJobs: [SchemaV2_8_0.AnimeEntryStaffJob] {
        jobs.sorted {
            if $0.displayOrder == $1.displayOrder {
                if $0.episodeCount == $1.episodeCount {
                    return $0.creditID < $1.creditID
                }
                return $0.episodeCount > $1.episodeCount
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}
