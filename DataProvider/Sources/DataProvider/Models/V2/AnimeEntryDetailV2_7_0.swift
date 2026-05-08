//
//  AnimeEntryDetailV2_7_0.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/8.
//

import Foundation
import SwiftData

extension SchemaV2_7_0 {
    @Model
    public final class AnimeEntryDetail {
        public var language: String
        public var title: String
        public var subtitle: String?
        public var overview: String?
        public var status: String?
        public var airDate: Date?
        public var primaryLinkURL: URL?
        public var heroImageURL: URL?
        public var logoImageURL: URL?
        public var genreIDs: [Int]
        public var voteAverage: Double?
        public var runtimeMinutes: Int?
        public var episodeCount: Int?
        public var seasonCount: Int?
        public var entry: AnimeEntry? = nil

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryCharacter.detail)
        public var characters: [AnimeEntryCharacter] = []

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryStaff.detail)
        public var staff: [AnimeEntryStaff] = []

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntrySeasonSummary.detail)
        public var seasons: [AnimeEntrySeasonSummary] = []

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryEpisodeSummary.detail)
        public var episodes: [AnimeEntryEpisodeSummary] = []

        public init(
            language: String,
            title: String,
            subtitle: String? = nil,
            overview: String? = nil,
            status: String? = nil,
            airDate: Date? = nil,
            primaryLinkURL: URL? = nil,
            heroImageURL: URL? = nil,
            logoImageURL: URL? = nil,
            genreIDs: [Int] = [],
            voteAverage: Double? = nil,
            runtimeMinutes: Int? = nil,
            episodeCount: Int? = nil,
            seasonCount: Int? = nil,
            characters: [AnimeEntryCharacter] = [],
            staff: [AnimeEntryStaff] = [],
            seasons: [AnimeEntrySeasonSummary] = [],
            episodes: [AnimeEntryEpisodeSummary] = []
        ) {
            self.language = language
            self.title = title
            self.subtitle = subtitle
            self.overview = overview
            self.status = status
            self.airDate = airDate
            self.primaryLinkURL = primaryLinkURL
            self.heroImageURL = heroImageURL
            self.logoImageURL = logoImageURL
            self.genreIDs = genreIDs
            self.voteAverage = voteAverage
            self.runtimeMinutes = runtimeMinutes
            self.episodeCount = episodeCount
            self.seasonCount = seasonCount
            self.characters = characters
            self.staff = staff
            self.seasons = seasons
            self.episodes = episodes
            attachChildren()
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
                heroImageURL: dto.heroImageURL,
                logoImageURL: dto.logoImageURL,
                genreIDs: dto.genreIDs,
                voteAverage: dto.voteAverage,
                runtimeMinutes: dto.runtimeMinutes,
                episodeCount: dto.episodeCount,
                seasonCount: dto.seasonCount,
                characters: dto.characters.map(AnimeEntryCharacter.init(from:)),
                staff: dto.staff.map(AnimeEntryStaff.init(from:)),
                seasons: dto.seasons.map(AnimeEntrySeasonSummary.init(from:)),
                episodes: dto.episodes.map(AnimeEntryEpisodeSummary.init(from:))
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
                characters: payload.characters.map(AnimeEntryCharacter.init(fromLegacy:)),
                staff: [],
                seasons: payload.seasons.map(AnimeEntrySeasonSummary.init(fromLegacy:)),
                episodes: payload.episodes.map(AnimeEntryEpisodeSummary.init(fromLegacy:))
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

        private func attachChildren() {
            characters.forEach { $0.detail = self }
            staff.forEach { $0.detail = self }
            seasons.forEach { $0.detail = self }
            episodes.forEach { $0.detail = self }
        }

        private func replaceCharacters(with dtos: [AnimeEntryCharacterDTO]) {
            if let modelContext {
                for character in characters {
                    modelContext.delete(character)
                }
            }
            characters = dtos.map(AnimeEntryCharacter.init(from:))
            characters.forEach { $0.detail = self }
        }

        private func replaceStaff(with dtos: [AnimeEntryStaffDTO]) {
            if let modelContext {
                for crewMember in staff {
                    modelContext.delete(crewMember)
                }
            }
            staff = dtos.map(AnimeEntryStaff.init(from:))
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
            episodes = dtos.map(AnimeEntryEpisodeSummary.init(from:))
            episodes.forEach { $0.detail = self }
        }
    }

    @Model
    public final class AnimeEntryCharacter {
        public var id: Int
        public var characterName: String
        public var actorName: String
        public var profileURL: URL?
        public var detail: AnimeEntryDetail? = nil

        public init(id: Int, characterName: String, actorName: String, profileURL: URL? = nil) {
            self.id = id
            self.characterName = characterName
            self.actorName = actorName
            self.profileURL = profileURL
        }

        public convenience init(from dto: AnimeEntryCharacterDTO) {
            self.init(
                id: dto.id,
                characterName: dto.characterName,
                actorName: dto.actorName,
                profileURL: dto.profileURL
            )
        }

        public convenience init(fromLegacy payload: LegacyAnimeEntryCharacterPayload) {
            self.init(
                id: payload.id,
                characterName: payload.characterName,
                actorName: payload.actorName,
                profileURL: payload.profileURL
            )
        }
    }

    @Model
    public final class AnimeEntryStaff {
        public var id: Int
        public var name: String
        public var role: String
        public var department: String?
        public var profileURL: URL?
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            name: String,
            role: String,
            department: String? = nil,
            profileURL: URL? = nil
        ) {
            self.id = id
            self.name = name
            self.role = role
            self.department = department
            self.profileURL = profileURL
        }

        public convenience init(from dto: AnimeEntryStaffDTO) {
            self.init(
                id: dto.id,
                name: dto.name,
                role: dto.role,
                department: dto.department,
                profileURL: dto.profileURL
            )
        }
    }

    @Model
    public final class AnimeEntrySeasonSummary {
        public var id: Int
        public var seasonNumber: Int
        public var title: String
        public var posterURL: URL?
        public var detail: AnimeEntryDetail? = nil

        public init(id: Int, seasonNumber: Int, title: String, posterURL: URL? = nil) {
            self.id = id
            self.seasonNumber = seasonNumber
            self.title = title
            self.posterURL = posterURL
        }

        public convenience init(from dto: AnimeEntrySeasonSummaryDTO) {
            self.init(
                id: dto.id,
                seasonNumber: dto.seasonNumber,
                title: dto.title,
                posterURL: dto.posterURL
            )
        }

        public convenience init(fromLegacy payload: LegacyAnimeEntrySeasonSummaryPayload) {
            self.init(
                id: payload.id,
                seasonNumber: payload.seasonNumber,
                title: payload.title,
                posterURL: payload.posterURL
            )
        }
    }

    @Model
    public final class AnimeEntryEpisodeSummary {
        public var id: Int
        public var episodeNumber: Int
        public var title: String
        public var airDate: Date?
        public var imageURL: URL?
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            episodeNumber: Int,
            title: String,
            airDate: Date? = nil,
            imageURL: URL? = nil
        ) {
            self.id = id
            self.episodeNumber = episodeNumber
            self.title = title
            self.airDate = airDate
            self.imageURL = imageURL
        }

        public convenience init(from dto: AnimeEntryEpisodeSummaryDTO) {
            self.init(
                id: dto.id,
                episodeNumber: dto.episodeNumber,
                title: dto.title,
                airDate: dto.airDate,
                imageURL: dto.imageURL
            )
        }

        public convenience init(fromLegacy payload: LegacyAnimeEntryEpisodeSummaryPayload) {
            self.init(
                id: payload.id,
                episodeNumber: payload.episodeNumber,
                title: payload.title,
                airDate: payload.airDate,
                imageURL: payload.imageURL
            )
        }
    }
}

extension SchemaV2_7_0.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_7_0.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_7_0.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
