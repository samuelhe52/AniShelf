//
//  AnimeEntryDetailOrderingV2_7_8.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/21.
//

import Foundation

extension SchemaV2_7_8.AnimeEntryDetail {
    public var orderedCharacters: [SchemaV2_7_8.AnimeEntryCharacter] {
        characters.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedStaff: [SchemaV2_7_8.AnimeEntryStaff] {
        staff.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedEpisodes: [SchemaV2_7_8.AnimeEntryEpisodeSummary] {
        episodes.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.episodeNumber < $1.episodeNumber
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}

extension SchemaV2_7_8.AnimeEntryStaff {
    public var orderedJobs: [SchemaV2_7_8.AnimeEntryStaffJob] {
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
