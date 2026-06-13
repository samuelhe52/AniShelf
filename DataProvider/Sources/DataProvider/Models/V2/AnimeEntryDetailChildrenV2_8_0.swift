//
//  AnimeEntryDetailChildrenV2_8_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation
import SwiftData

extension SchemaV2_8_0 {
    @Model
    public final class AnimeEntryCharacter {
        public var id: Int
        public var characterName: String
        public var actorName: String
        public var profilePath: String?
        public var displayOrder: Int
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            characterName: String,
            actorName: String,
            profilePath: String? = nil,
            profileURL: URL? = nil,
            displayOrder: Int = 0
        ) {
            self.id = id
            self.characterName = characterName
            self.actorName = actorName
            self.profilePath =
                TMDbImagePath.storagePath(from: profilePath, fallback: profileURL)
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryCharacterDTO, displayOrder: Int = 0) {
            self.init(
                id: dto.id,
                characterName: dto.characterName,
                actorName: dto.actorName,
                profilePath: dto.profilePath,
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
        public var profilePath: String?
        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryStaffJob.staff)
        public var jobs: [AnimeEntryStaffJob] = []
        public var displayOrder: Int
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            name: String,
            role: String,
            department: String? = nil,
            profilePath: String? = nil,
            profileURL: URL? = nil,
            jobs: [AnimeEntryStaffJob] = [],
            displayOrder: Int = 0
        ) {
            self.id = id
            self.name = name
            self.role = role
            self.department = department
            self.profilePath =
                TMDbImagePath.storagePath(from: profilePath, fallback: profileURL)
            self.jobs = jobs
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryStaffDTO, displayOrder: Int = 0) {
            self.init(
                id: dto.id,
                name: dto.name,
                role: dto.role,
                department: dto.department,
                profilePath: dto.profilePath,
                profileURL: dto.profileURL,
                jobs: dto.jobs.enumerated().map {
                    AnimeEntryStaffJob(from: $0.element, displayOrder: $0.offset)
                },
                displayOrder: displayOrder
            )
        }
    }

    @Model
    public final class AnimeEntryStaffJob {
        public var creditID: String
        public var job: String
        public var episodeCount: Int
        public var displayOrder: Int
        public var staff: AnimeEntryStaff? = nil

        public init(
            creditID: String,
            job: String,
            episodeCount: Int,
            displayOrder: Int = 0
        ) {
            self.creditID = creditID
            self.job = job
            self.episodeCount = episodeCount
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryStaffJobDTO, displayOrder: Int = 0) {
            self.init(
                creditID: dto.creditID,
                job: dto.job,
                episodeCount: dto.episodeCount,
                displayOrder: displayOrder
            )
        }
    }

    @Model
    public final class AnimeEntrySeasonSummary {
        public var id: Int
        public var seasonNumber: Int
        public var title: String
        public var posterPath: String?
        public var episodeCount: Int?
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            seasonNumber: Int,
            title: String,
            posterPath: String? = nil,
            posterURL: URL? = nil,
            episodeCount: Int? = nil
        ) {
            self.id = id
            self.seasonNumber = seasonNumber
            self.title = title
            self.posterPath =
                TMDbImagePath.storagePath(from: posterPath, fallback: posterURL)
            self.episodeCount = episodeCount
        }

        public convenience init(from dto: AnimeEntrySeasonSummaryDTO) {
            self.init(
                id: dto.id,
                seasonNumber: dto.seasonNumber,
                title: dto.title,
                posterPath: dto.posterPath,
                posterURL: dto.posterURL,
                episodeCount: dto.episodeCount
            )
        }

        public convenience init(fromLegacy payload: LegacyAnimeEntrySeasonSummaryPayload) {
            self.init(
                id: payload.id,
                seasonNumber: payload.seasonNumber,
                title: payload.title,
                posterURL: payload.posterURL,
                episodeCount: payload.episodeCount
            )
        }
    }

    @Model
    public final class AnimeEntryEpisodeSummary {
        public var id: Int
        public var episodeNumber: Int
        public var title: String
        public var airDate: Date?
        public var imagePath: String?
        public var displayOrder: Int
        public var detail: AnimeEntryDetail? = nil

        public init(
            id: Int,
            episodeNumber: Int,
            title: String,
            airDate: Date? = nil,
            imagePath: String? = nil,
            imageURL: URL? = nil,
            displayOrder: Int = 0
        ) {
            self.id = id
            self.episodeNumber = episodeNumber
            self.title = title
            self.airDate = airDate
            self.imagePath =
                TMDbImagePath.storagePath(from: imagePath, fallback: imageURL)
            self.displayOrder = displayOrder
        }

        public convenience init(from dto: AnimeEntryEpisodeSummaryDTO, displayOrder: Int = 0) {
            self.init(
                id: dto.id,
                episodeNumber: dto.episodeNumber,
                title: dto.title,
                airDate: dto.airDate,
                imagePath: dto.imagePath,
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

    @Model
    public final class AnimeEntryEpisodeProgress {
        public var seasonNumber: Int
        public var watchedThroughEpisode: Int
        public var updatedAt: Date
        public var entry: AnimeEntry? = nil

        public init(
            seasonNumber: Int,
            watchedThroughEpisode: Int,
            updatedAt: Date = .now
        ) {
            self.seasonNumber = seasonNumber
            self.watchedThroughEpisode = max(0, watchedThroughEpisode)
            self.updatedAt = updatedAt
        }
    }
}
