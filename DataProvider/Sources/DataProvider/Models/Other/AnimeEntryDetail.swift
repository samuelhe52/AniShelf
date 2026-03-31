//
//  AnimeEntryDetail.swift
//  DataProvider
//
//  Created by Samuel He on 2026/3/31.
//

import Foundation

public struct AnimeEntryDetail: Codable, Equatable, Sendable {
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
    public var characters: [AnimeEntryCharacter]
    public var seasons: [AnimeEntrySeasonSummary]
    public var episodes: [AnimeEntryEpisodeSummary]

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
        self.seasons = seasons
        self.episodes = episodes
    }
}

public struct AnimeEntryCharacter: Codable, Equatable, Sendable, Identifiable {
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

public struct AnimeEntrySeasonSummary: Codable, Equatable, Sendable, Identifiable {
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

public struct AnimeEntryEpisodeSummary: Codable, Equatable, Sendable, Identifiable {
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
