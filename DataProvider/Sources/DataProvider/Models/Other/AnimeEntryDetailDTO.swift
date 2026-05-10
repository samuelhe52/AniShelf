//
//  AnimeEntryDetailDTO.swift
//  DataProvider
//
//  Created by Samuel He on 2026/3/31.
//

import Foundation

public struct LegacyAnimeEntryDetailPayload: Codable, Equatable, Sendable {
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
    public var characters: [LegacyAnimeEntryCharacterPayload]
    public var seasons: [LegacyAnimeEntrySeasonSummaryPayload]
    public var episodes: [LegacyAnimeEntryEpisodeSummaryPayload]

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
        characters: [LegacyAnimeEntryCharacterPayload] = [],
        seasons: [LegacyAnimeEntrySeasonSummaryPayload] = [],
        episodes: [LegacyAnimeEntryEpisodeSummaryPayload] = []
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
        self.seasons = seasons
        self.episodes = episodes
    }
}

public struct LegacyAnimeEntryCharacterPayload: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var characterName: String
    public var actorName: String
    public var profileURL: URL?

    public init(id: Int, characterName: String, actorName: String, profileURL: URL? = nil) {
        self.id = id
        self.characterName = characterName
        self.actorName = actorName
        self.profileURL = profileURL
    }
}

public struct LegacyAnimeEntrySeasonSummaryPayload: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var title: String
    public var posterURL: URL?

    public init(id: Int, seasonNumber: Int, title: String, posterURL: URL? = nil) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.title = title
        self.posterURL = posterURL
    }
}

public struct LegacyAnimeEntryEpisodeSummaryPayload: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var episodeNumber: Int
    public var title: String
    public var airDate: Date?
    public var imageURL: URL?

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
}

// Fetch-layer DTOs only. Persisted detail data now lives in the v2.7.0 SwiftData model graph.
public struct AnimeEntryDetailDTO: Equatable, Sendable {
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
    public var characters: [AnimeEntryCharacterDTO]
    public var staff: [AnimeEntryStaffDTO]
    public var seasons: [AnimeEntrySeasonSummaryDTO]
    public var episodes: [AnimeEntryEpisodeSummaryDTO]

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
        characters: [AnimeEntryCharacterDTO] = [],
        staff: [AnimeEntryStaffDTO] = [],
        seasons: [AnimeEntrySeasonSummaryDTO] = [],
        episodes: [AnimeEntryEpisodeSummaryDTO] = []
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
    }

    init(fromLegacy payload: LegacyAnimeEntryDetailPayload) {
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
            characters: payload.characters.map {
                AnimeEntryCharacterDTO(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profileURL: $0.profileURL
                )
            },
            staff: [],
            seasons: payload.seasons.map {
                AnimeEntrySeasonSummaryDTO(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.title,
                    posterURL: $0.posterURL
                )
            },
            episodes: payload.episodes.map {
                AnimeEntryEpisodeSummaryDTO(
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

public struct AnimeEntryCharacterDTO: Equatable, Sendable, Identifiable {
    public var id: Int
    public var characterName: String
    public var actorName: String
    public var profileURL: URL?

    public init(id: Int, characterName: String, actorName: String, profileURL: URL? = nil) {
        self.id = id
        self.characterName = characterName
        self.actorName = actorName
        self.profileURL = profileURL
    }
}

public struct AnimeEntryStaffDTO: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var role: String
    public var department: String?
    public var profileURL: URL?
    public var jobs: [AnimeEntryStaffJobDTO]

    public init(
        id: Int,
        name: String,
        role: String,
        department: String? = nil,
        profileURL: URL? = nil,
        jobs: [AnimeEntryStaffJobDTO] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.department = department
        self.profileURL = profileURL
        self.jobs = jobs
    }
}

public struct AnimeEntryStaffJobDTO: Equatable, Sendable, Identifiable {
    public var id: String { creditID }
    public var creditID: String
    public var job: String
    public var episodeCount: Int

    public init(
        creditID: String,
        job: String,
        episodeCount: Int
    ) {
        self.creditID = creditID
        self.job = job
        self.episodeCount = episodeCount
    }
}

public struct AnimeEntrySeasonSummaryDTO: Equatable, Sendable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var title: String
    public var posterURL: URL?

    public init(id: Int, seasonNumber: Int, title: String, posterURL: URL? = nil) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.title = title
        self.posterURL = posterURL
    }
}

public struct AnimeEntryEpisodeSummaryDTO: Equatable, Sendable, Identifiable {
    public var id: Int
    public var episodeNumber: Int
    public var title: String
    public var airDate: Date?
    public var imageURL: URL?

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
}
