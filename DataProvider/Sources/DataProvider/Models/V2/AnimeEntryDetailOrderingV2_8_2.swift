//
//  AnimeEntryDetailOrderingV2_8_2.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/2.
//

import Foundation

extension SchemaV2_8_2.AnimeEntryDetail {
    public var orderedProductionCompanies: [SchemaV2_8_2.AnimeEntryProductionCompany] {
        productionCompanies.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedCharacters: [SchemaV2_8_2.AnimeEntryCharacter] {
        characters.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedStaff: [SchemaV2_8_2.AnimeEntryStaff] {
        staff.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.id < $1.id }
            return $0.displayOrder < $1.displayOrder
        }
    }

    public var orderedEpisodes: [SchemaV2_8_2.AnimeEntryEpisodeSummary] {
        episodes.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.episodeNumber < $1.episodeNumber
            }
            return $0.displayOrder < $1.displayOrder
        }
    }
}

extension SchemaV2_8_2.AnimeEntryStaff {
    public var orderedJobs: [SchemaV2_8_2.AnimeEntryStaffJob] {
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
