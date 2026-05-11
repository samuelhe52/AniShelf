//
//  AnimeEntryDetailOrderingV2_7_5.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/12.
//

import Foundation

extension SchemaV2_7_5.AnimeEntryDetail {
    public var orderedCharacters: [SchemaV2_7_5.AnimeEntryCharacter] {
        characters.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedStaff: [SchemaV2_7_5.AnimeEntryStaff] {
        staff.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedEpisodes: [SchemaV2_7_5.AnimeEntryEpisodeSummary] {
        episodes.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.episodeNumber < $1.episodeNumber
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}

extension SchemaV2_7_5.AnimeEntryStaff {
    public var orderedJobs: [SchemaV2_7_5.AnimeEntryStaffJob] {
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
