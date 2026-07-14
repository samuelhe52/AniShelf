//
//  AnimeEntryDetailBridgeV2_8_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation
import SwiftData

extension SchemaV2_8_0.AnimeEntryDetail {
    public func snapshotDTO() -> AnimeEntryDetailDTO {
        AnimeEntryDetailDTO(
            language: language,
            title: title,
            subtitle: subtitle,
            overview: overview,
            status: status,
            airDate: airDate,
            primaryLinkURL: primaryLinkURL,
            logoImagePath: logoImagePath,
            genreIDs: genreIDs,
            voteAverage: voteAverage,
            runtimeMinutes: runtimeMinutes,
            episodeCount: episodeCount,
            seasonCount: seasonCount,
            characters: orderedCharacters.map {
                AnimeEntryCharacterDTO(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profilePath: $0.profilePath
                )
            },
            staff: orderedStaff.map {
                AnimeEntryStaffDTO(
                    id: $0.id,
                    name: $0.name,
                    role: $0.role,
                    department: $0.department,
                    profilePath: $0.profilePath,
                    jobs: $0.orderedJobs.map {
                        AnimeEntryStaffJobDTO(
                            creditID: $0.creditID,
                            job: $0.job,
                            episodeCount: $0.episodeCount
                        )
                    }
                )
            },
            seasons: seasons.sorted {
                if $0.seasonNumber == $1.seasonNumber { return $0.id < $1.id }
                return $0.seasonNumber < $1.seasonNumber
            }.map {
                AnimeEntrySeasonSummaryDTO(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.title,
                    posterPath: $0.posterPath,
                    episodeCount: $0.episodeCount
                )
            },
            episodes: orderedEpisodes.map {
                AnimeEntryEpisodeSummaryDTO(
                    id: $0.id,
                    episodeNumber: $0.episodeNumber,
                    title: $0.title,
                    airDate: $0.airDate,
                    imagePath: $0.imagePath
                )
            }
        )
    }

    public convenience init(from dto: AnimeEntryDetailDTO) {
        self.init(
            language: dto.language,
            title: dto.title,
            subtitle: dto.subtitle,
            overview: dto.overview,
            status: dto.status,
            airDate: dto.airDate,
            primaryLinkURL: dto.primaryLinkURL,
            logoImagePath: dto.logoImagePath,
            logoImageURL: dto.logoImageURL,
            genreIDs: dto.genreIDs,
            voteAverage: dto.voteAverage,
            runtimeMinutes: dto.runtimeMinutes,
            episodeCount: dto.episodeCount,
            seasonCount: dto.seasonCount,
            characters: Self.makeCharacters(from: dto.characters),
            staff: Self.makeStaff(from: dto.staff),
            seasons: dto.seasons.map(SchemaV2_8_0.AnimeEntrySeasonSummary.init(from:)),
            episodes: Self.makeEpisodes(from: dto.episodes)
        )
    }

    public convenience init(fromLegacy payload: LegacyAnimeEntryDetailPayload) {
        self.init(
            language: payload.language,
            title: payload.title,
            subtitle: payload.subtitle,
            overview: payload.overview,
            status: payload.status,
            airDate: payload.airDate,
            primaryLinkURL: payload.primaryLinkURL,
            logoImagePath: payload.logoImagePath,
            logoImageURL: payload.logoImageURL,
            genreIDs: payload.genreIDs,
            voteAverage: payload.voteAverage,
            runtimeMinutes: payload.runtimeMinutes,
            episodeCount: payload.episodeCount,
            seasonCount: payload.seasonCount,
            characters: Self.makeCharacters(fromLegacy: payload.characters),
            staff: [],
            seasons: payload.seasons.map(SchemaV2_8_0.AnimeEntrySeasonSummary.init(fromLegacy:)),
            episodes: Self.makeEpisodes(fromLegacy: payload.episodes)
        )
    }

    public func apply(dto: AnimeEntryDetailDTO) {
        language = dto.language
        title = dto.title
        subtitle = dto.subtitle
        overview = dto.overview
        status = dto.status
        airDate = dto.airDate
        primaryLinkURL = dto.primaryLinkURL
        logoImagePath = TMDbImagePath.storagePath(from: dto.logoImagePath, fallback: dto.logoImageURL)
        genreIDs = dto.genreIDs
        voteAverage = dto.voteAverage
        runtimeMinutes = dto.runtimeMinutes
        episodeCount = dto.episodeCount
        seasonCount = dto.seasonCount
        replaceCharacters(with: dto.characters)
        replaceStaff(with: dto.staff)
        replaceSeasons(with: dto.seasons)
        replaceEpisodes(with: dto.episodes)
    }

    private func replaceCharacters(with dtos: [AnimeEntryCharacterDTO]) {
        if let modelContext {
            for character in characters {
                modelContext.delete(character)
            }
        }
        characters = Self.makeCharacters(from: dtos)
        characters.forEach { $0.detail = self }
    }

    private func replaceStaff(with dtos: [AnimeEntryStaffDTO]) {
        if let modelContext {
            for crewMember in staff {
                modelContext.delete(crewMember)
            }
        }
        staff = Self.makeStaff(from: dtos)
        staff.forEach { $0.detail = self }
    }

    private func replaceSeasons(with dtos: [AnimeEntrySeasonSummaryDTO]) {
        if let modelContext {
            for season in seasons {
                modelContext.delete(season)
            }
        }
        seasons = dtos.map(SchemaV2_8_0.AnimeEntrySeasonSummary.init(from:))
        seasons.forEach { $0.detail = self }
    }

    private func replaceEpisodes(with dtos: [AnimeEntryEpisodeSummaryDTO]) {
        if let modelContext {
            for episode in episodes {
                modelContext.delete(episode)
            }
        }
        episodes = Self.makeEpisodes(from: dtos)
        episodes.forEach { $0.detail = self }
    }

    private static func makeCharacters(
        from dtos: [AnimeEntryCharacterDTO]
    ) -> [SchemaV2_8_0.AnimeEntryCharacter] {
        dtos.enumerated().map {
            SchemaV2_8_0.AnimeEntryCharacter(from: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeCharacters(
        fromLegacy payloads: [LegacyAnimeEntryCharacterPayload]
    ) -> [SchemaV2_8_0.AnimeEntryCharacter] {
        payloads.enumerated().map {
            SchemaV2_8_0.AnimeEntryCharacter(fromLegacy: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeStaff(
        from dtos: [AnimeEntryStaffDTO]
    ) -> [SchemaV2_8_0.AnimeEntryStaff] {
        dtos.enumerated().map {
            SchemaV2_8_0.AnimeEntryStaff(from: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeEpisodes(
        from dtos: [AnimeEntryEpisodeSummaryDTO]
    ) -> [SchemaV2_8_0.AnimeEntryEpisodeSummary] {
        dtos.enumerated().map {
            SchemaV2_8_0.AnimeEntryEpisodeSummary(from: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeEpisodes(
        fromLegacy payloads: [LegacyAnimeEntryEpisodeSummaryPayload]
    ) -> [SchemaV2_8_0.AnimeEntryEpisodeSummary] {
        payloads.enumerated().map {
            SchemaV2_8_0.AnimeEntryEpisodeSummary(fromLegacy: $0.element, displayOrder: $0.offset)
        }
    }
}
