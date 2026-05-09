//
//  AnimeEntryDetailChildrenV2_7_2.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/9.
//

import Foundation
import SwiftData

extension SchemaV2_7_2 {
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
