//
//  AnimeEntryDetailMigrationDTOBuilder.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation

func makeAnimeEntryDetailMigrationDTO<Character, Staff, Season, Episode>(
    language: String,
    title: String,
    subtitle: String?,
    overview: String?,
    status: String?,
    airDate: Date?,
    primaryLinkURL: URL?,
    heroImageURL: URL?,
    logoImageURL: URL?,
    genreIDs: [Int],
    voteAverage: Double?,
    runtimeMinutes: Int?,
    episodeCount: Int?,
    seasonCount: Int?,
    characters: [Character],
    staff: [Staff],
    seasons: [Season],
    episodes: [Episode],
    characterDTO: (Character) -> AnimeEntryCharacterDTO,
    staffDTO: (Staff) -> AnimeEntryStaffDTO,
    seasonDTO: (Season) -> AnimeEntrySeasonSummaryDTO,
    episodeDTO: (Episode) -> AnimeEntryEpisodeSummaryDTO
) -> AnimeEntryDetailDTO {
    AnimeEntryDetailDTO(
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
        characters: characters.map(characterDTO),
        staff: staff.map(staffDTO),
        seasons: seasons.map(seasonDTO),
        episodes: episodes.map(episodeDTO)
    )
}

func makeAnimeEntryCharacterDTO(
    id: Int,
    characterName: String,
    actorName: String,
    profileURL: URL?
) -> AnimeEntryCharacterDTO {
    AnimeEntryCharacterDTO(
        id: id,
        characterName: characterName,
        actorName: actorName,
        profileURL: profileURL
    )
}

func makeAnimeEntryStaffDTO(
    id: Int,
    name: String,
    role: String,
    department: String?,
    profileURL: URL?,
    jobs: [AnimeEntryStaffJobDTO] = []
) -> AnimeEntryStaffDTO {
    AnimeEntryStaffDTO(
        id: id,
        name: name,
        role: role,
        department: department,
        profileURL: profileURL,
        jobs: jobs
    )
}

func makeAnimeEntryStaffJobDTO(
    creditID: String,
    job: String,
    episodeCount: Int
) -> AnimeEntryStaffJobDTO {
    AnimeEntryStaffJobDTO(
        creditID: creditID,
        job: job,
        episodeCount: episodeCount
    )
}

func makeAnimeEntrySeasonSummaryDTO(
    id: Int,
    seasonNumber: Int,
    title: String,
    posterURL: URL?
) -> AnimeEntrySeasonSummaryDTO {
    AnimeEntrySeasonSummaryDTO(
        id: id,
        seasonNumber: seasonNumber,
        title: title,
        posterURL: posterURL
    )
}

func makeAnimeEntryEpisodeSummaryDTO(
    id: Int,
    episodeNumber: Int,
    title: String,
    airDate: Date?,
    imageURL: URL?
) -> AnimeEntryEpisodeSummaryDTO {
    AnimeEntryEpisodeSummaryDTO(
        id: id,
        episodeNumber: episodeNumber,
        title: title,
        airDate: airDate,
        imageURL: imageURL
    )
}
