//
//  AnimeEntryDetailV2_7_1.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation
import SwiftData

extension SchemaV2_7_1 {
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

        private static func makeCharacters(
            from dtos: [AnimeEntryCharacterDTO]
        ) -> [AnimeEntryCharacter] {
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

    @Model
    public final class AnimeEntryCharacter {
        public var id: Int
        public var characterName: String
        public var actorName: String
        public var profileURL: URL?
        public var displayOrder: Int
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            characterName: String,
            actorName: String,
            profileURL: URL? = nil,
            displayOrder: Int = 0
        ) {
            self.id = id
            self.characterName = characterName
            self.actorName = actorName
            self.profileURL = profileURL
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryCharacterDTO, displayOrder: Int = 0) {
            self.init(
                id: dto.id,
                characterName: dto.characterName,
                actorName: dto.actorName,
                profileURL: dto.profileURL,
                displayOrder: displayOrder
            )
        }

        public convenience init(
            fromLegacy payload: LegacyAnimeEntryCharacterPayload,
            displayOrder: Int = 0
        ) {
            self.init(
                id: payload.id,
                characterName: payload.characterName,
                actorName: payload.actorName,
                profileURL: payload.profileURL,
                displayOrder: displayOrder
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
        public var displayOrder: Int
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            name: String,
            role: String,
            department: String? = nil,
            profileURL: URL? = nil,
            displayOrder: Int = 0
        ) {
            self.id = id
            self.name = name
            self.role = role
            self.department = department
            self.profileURL = profileURL
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryStaffDTO, displayOrder: Int = 0) {
            self.init(
                id: dto.id,
                name: dto.name,
                role: dto.role,
                department: dto.department,
                profileURL: dto.profileURL,
                displayOrder: displayOrder
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
        public var displayOrder: Int
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            episodeNumber: Int,
            title: String,
            airDate: Date? = nil,
            imageURL: URL? = nil,
            displayOrder: Int = 0
        ) {
            self.id = id
            self.episodeNumber = episodeNumber
            self.title = title
            self.airDate = airDate
            self.imageURL = imageURL
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryEpisodeSummaryDTO, displayOrder: Int = 0) {
            self.init(
                id: dto.id,
                episodeNumber: dto.episodeNumber,
                title: dto.title,
                airDate: dto.airDate,
                imageURL: dto.imageURL,
                displayOrder: displayOrder
            )
        }

        public convenience init(
            fromLegacy payload: LegacyAnimeEntryEpisodeSummaryPayload,
            displayOrder: Int = 0
        ) {
            self.init(
                id: payload.id,
                episodeNumber: payload.episodeNumber,
                title: payload.title,
                airDate: payload.airDate,
                imageURL: payload.imageURL,
                displayOrder: displayOrder
            )
        }
    }
}

extension SchemaV2_7_1.AnimeEntry {
    @discardableResult
    public func replaceDetail(from dto: AnimeEntryDetailDTO) -> SchemaV2_7_1.AnimeEntryDetail {
        if let detail {
            detail.apply(dto: dto)
            return detail
        }

        let detail = SchemaV2_7_1.AnimeEntryDetail(from: dto)
        self.detail = detail
        return detail
    }
}
