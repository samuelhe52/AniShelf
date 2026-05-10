//
//  AnimeEntryDetailMigrationBridgeV2_7_0.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation

extension SchemaV2_7_0.AnimeEntryDetail {
    func migrationDTO() -> AnimeEntryDetailDTO {
        makeAnimeEntryDetailMigrationDTO(
            language: language,
            title: title,
            subtitle: subtitle,
            overview: overview,
            status: status,
            airDate: airDate,
            primaryLinkURL: primaryLinkURL,
            heroImageURL: heroImageURL,
            logoImageURL: logoImageURL,
            genreIDs: genreIDs,
            voteAverage: voteAverage,
            runtimeMinutes: runtimeMinutes,
            episodeCount: episodeCount,
            seasonCount: seasonCount,
            characters: characters,
            staff: staff,
            seasons: seasons,
            episodes: episodes.sorted {
                if $0.episodeNumber == $1.episodeNumber { return $0.id < $1.id }
                return $0.episodeNumber < $1.episodeNumber
            },
            characterDTO: {
                makeAnimeEntryCharacterDTO(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profileURL: $0.profileURL
                )
            },
            staffDTO: {
                makeAnimeEntryStaffDTO(
                    id: $0.id,
                    name: $0.name,
                    role: $0.role,
                    department: $0.department,
                    profileURL: $0.profileURL
                )
            },
            seasonDTO: {
                makeAnimeEntrySeasonSummaryDTO(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.title,
                    posterURL: $0.posterURL
                )
            },
            episodeDTO: {
                makeAnimeEntryEpisodeSummaryDTO(
                    id: $0.id,
                    episodeNumber: $0.episodeNumber,
                    title: $0.title,
                    airDate: $0.airDate,
                    imageURL: $0.imageURL
                )
            }
        )
    }
}
