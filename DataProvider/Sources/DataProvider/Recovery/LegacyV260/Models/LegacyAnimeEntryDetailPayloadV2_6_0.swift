//
//  LegacyAnimeEntryDetailPayloadV2_6_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/5.
//

import Foundation

/// The released V2.6.0 detail value as it was persisted before image paths were added.
///
/// This type exists only to identify and migrate stores written by that model. Do not
/// add fields here: changing a historical SwiftData model's shape makes its stores
/// unrecognizable to staged migration.
struct LegacyAnimeEntryDetailPayloadV2_6_0: Codable, Equatable, Sendable {
    var language: String
    var title: String
    var subtitle: String?
    var overview: String?
    var status: String?
    var airDate: Date?
    var primaryLinkURL: URL?
    var heroImageURL: URL?
    var logoImageURL: URL?
    var genreIDs: [Int]
    var voteAverage: Double?
    var runtimeMinutes: Int?
    var episodeCount: Int?
    var seasonCount: Int?
    var characters: [LegacyAnimeEntryCharacterPayloadV2_6_0]
    var seasons: [LegacyAnimeEntrySeasonSummaryPayloadV2_6_0]
    var episodes: [LegacyAnimeEntryEpisodeSummaryPayloadV2_6_0]
}

struct LegacyAnimeEntryCharacterPayloadV2_6_0: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var characterName: String
    var actorName: String
    var profileURL: URL?
}

struct LegacyAnimeEntrySeasonSummaryPayloadV2_6_0: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var seasonNumber: Int
    var title: String
    var posterURL: URL?
}

struct LegacyAnimeEntryEpisodeSummaryPayloadV2_6_0: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var episodeNumber: Int
    var title: String
    var airDate: Date?
    var imageURL: URL?
}

extension AnimeEntryDetailDTO {
    init(fromV260Legacy payload: LegacyAnimeEntryDetailPayloadV2_6_0) {
        self.init(
            language: payload.language,
            title: payload.title,
            subtitle: payload.subtitle,
            overview: payload.overview,
            status: payload.status,
            airDate: payload.airDate,
            primaryLinkURL: payload.primaryLinkURL,
            logoImageURL: payload.logoImageURL,
            genreIDs: payload.genreIDs,
            voteAverage: payload.voteAverage,
            runtimeMinutes: payload.runtimeMinutes,
            episodeCount: payload.episodeCount,
            seasonCount: payload.seasonCount,
            characters: payload.characters.map {
                .init(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profileURL: $0.profileURL
                )
            },
            staff: [],
            seasons: payload.seasons.map {
                .init(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.title,
                    posterURL: $0.posterURL
                )
            },
            episodes: payload.episodes.map {
                .init(
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
