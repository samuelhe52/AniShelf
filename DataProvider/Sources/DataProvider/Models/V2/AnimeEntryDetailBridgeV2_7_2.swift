//
//  AnimeEntryDetailBridgeV2_7_2.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation
import SwiftData

extension SchemaV2_7_2.AnimeEntryDetail {
    public convenience init(from dto: AnimeEntryDetailDTO) {
        self.init(
            language: dto.language,
            title: dto.title,
            subtitle: dto.subtitle,
            overview: dto.overview,
            status: dto.status,
            airDate: dto.airDate,
            primaryLinkURL: dto.primaryLinkURL,
            heroImageURL: dto.heroImageURL,
            logoImageURL: dto.logoImageURL,
            genreIDs: dto.genreIDs,
            voteAverage: dto.voteAverage,
            runtimeMinutes: dto.runtimeMinutes,
            episodeCount: dto.episodeCount,
            seasonCount: dto.seasonCount,
            characters: Self.makeCharacters(from: dto.characters),
            staff: Self.makeStaff(from: dto.staff),
            seasons: dto.seasons.map(AnimeEntrySeasonSummary.init(from:)),
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
            heroImageURL: payload.heroImageURL,
            logoImageURL: payload.logoImageURL,
            genreIDs: payload.genreIDs,
            voteAverage: payload.voteAverage,
            runtimeMinutes: payload.runtimeMinutes,
            episodeCount: payload.episodeCount,
            seasonCount: payload.seasonCount,
            characters: Self.makeCharacters(fromLegacy: payload.characters),
            staff: [],
            seasons: payload.seasons.map(AnimeEntrySeasonSummary.init(fromLegacy:)),
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
        heroImageURL = dto.heroImageURL
        logoImageURL = dto.logoImageURL
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
        seasons = dtos.map(AnimeEntrySeasonSummary.init(from:))
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

    private static func makeCharacters(from dtos: [AnimeEntryCharacterDTO]) -> [AnimeEntryCharacter] {
        dtos.enumerated().map {
            AnimeEntryCharacter(from: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeCharacters(
        fromLegacy payloads: [LegacyAnimeEntryCharacterPayload]
    ) -> [AnimeEntryCharacter] {
        payloads.enumerated().map {
            AnimeEntryCharacter(fromLegacy: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeStaff(from dtos: [AnimeEntryStaffDTO]) -> [AnimeEntryStaff] {
        dtos.enumerated().map {
            AnimeEntryStaff(from: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeEpisodes(
        from dtos: [AnimeEntryEpisodeSummaryDTO]
    ) -> [AnimeEntryEpisodeSummary] {
        dtos.enumerated().map {
            AnimeEntryEpisodeSummary(from: $0.element, displayOrder: $0.offset)
        }
    }

    private static func makeEpisodes(
        fromLegacy payloads: [LegacyAnimeEntryEpisodeSummaryPayload]
    ) -> [AnimeEntryEpisodeSummary] {
        payloads.enumerated().map {
            AnimeEntryEpisodeSummary(fromLegacy: $0.element, displayOrder: $0.offset)
        }
    }
}
