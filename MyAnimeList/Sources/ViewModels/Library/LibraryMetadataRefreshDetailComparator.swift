//
//  LibraryMetadataRefreshDetailComparator.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/14.
//

import DataProvider
import Foundation

enum LibraryMetadataRefreshDetailComparator {
    private struct ComparableProductionCompany: Equatable {
        let id: Int
        let name: String
        let logoPath: String?
    }

    private struct ComparableCharacter: Equatable {
        let id: Int
        let characterName: String
        let actorName: String
        let profilePath: String?
    }

    private struct ComparableStaffJob: Equatable {
        let creditID: String
        let job: String
        let episodeCount: Int
    }

    private struct ComparableStaff: Equatable {
        let id: Int
        let name: String
        let role: String
        let department: String?
        let profilePath: String?
        let jobs: [ComparableStaffJob]
    }

    private struct ComparableSeason: Equatable {
        let id: Int
        let seasonNumber: Int
        let title: String
        let posterPath: String?
        let episodeCount: Int?
    }

    private struct ComparableEpisode: Equatable {
        let id: Int
        let episodeNumber: Int
        let title: String
        let airDate: Date?
        let imagePath: String?
    }

    private struct ComparableDetail: Equatable {
        let language: String
        let title: String
        let subtitle: String?
        let overview: String?
        let status: String?
        let airDate: Date?
        let primaryLinkURL: URL?
        let logoImagePath: String?
        let genreIDs: [Int]
        let voteAverage: Double?
        let runtimeMinutes: Int?
        let episodeCount: Int?
        let seasonCount: Int?
        let productionCompanies: [ComparableProductionCompany]
        let characters: [ComparableCharacter]
        let staff: [ComparableStaff]
        let seasons: [ComparableSeason]
        let episodes: [ComparableEpisode]
    }

    static func matches(
        existing detail: AnimeEntryDetail?,
        fetched dto: AnimeEntryDetailDTO
    ) -> Bool {
        guard let detail else { return false }
        return comparableDetail(from: detail) == comparableDetail(from: dto)
    }

    private static func comparableDetail(from detail: AnimeEntryDetail) -> ComparableDetail {
        ComparableDetail(
            language: detail.language,
            title: detail.title,
            subtitle: detail.subtitle,
            overview: detail.overview,
            status: detail.status,
            airDate: detail.airDate,
            primaryLinkURL: detail.primaryLinkURL,
            logoImagePath: detail.logoImagePath,
            genreIDs: detail.genreIDs.sorted(),
            voteAverage: detail.voteAverage,
            runtimeMinutes: detail.runtimeMinutes,
            episodeCount: detail.episodeCount,
            seasonCount: detail.seasonCount,
            productionCompanies: detail.orderedProductionCompanies.map {
                ComparableProductionCompany(
                    id: $0.id,
                    name: $0.name,
                    logoPath: $0.logoPath
                )
            },
            characters: normalizedCharacters(
                detail.characters.map {
                    ComparableCharacter(
                        id: $0.id,
                        characterName: $0.characterName,
                        actorName: $0.actorName,
                        profilePath: $0.profilePath
                    )
                }
            ),
            staff: normalizedStaff(
                detail.staff.map {
                    ComparableStaff(
                        id: $0.id,
                        name: $0.name,
                        role: $0.role,
                        department: $0.department,
                        profilePath: $0.profilePath,
                        jobs: normalizedStaffJobs(
                            $0.jobs.map {
                                ComparableStaffJob(
                                    creditID: $0.creditID,
                                    job: $0.job,
                                    episodeCount: $0.episodeCount
                                )
                            }
                        )
                    )
                }
            ),
            seasons: normalizedSeasons(
                detail.seasons.map {
                    ComparableSeason(
                        id: $0.id,
                        seasonNumber: $0.seasonNumber,
                        title: $0.title,
                        posterPath: $0.posterPath,
                        episodeCount: $0.episodeCount
                    )
                }
            ),
            episodes: normalizedEpisodes(
                detail.episodes.map {
                    ComparableEpisode(
                        id: $0.id,
                        episodeNumber: $0.episodeNumber,
                        title: $0.title,
                        airDate: $0.airDate,
                        imagePath: $0.imagePath
                    )
                }
            )
        )
    }

    private static func comparableDetail(from dto: AnimeEntryDetailDTO) -> ComparableDetail {
        ComparableDetail(
            language: dto.language,
            title: dto.title,
            subtitle: dto.subtitle,
            overview: dto.overview,
            status: dto.status,
            airDate: dto.airDate,
            primaryLinkURL: dto.primaryLinkURL,
            logoImagePath: TMDbImagePath.storagePath(
                from: dto.logoImagePath,
                fallback: dto.logoImageURL
            ),
            genreIDs: dto.genreIDs.sorted(),
            voteAverage: dto.voteAverage,
            runtimeMinutes: dto.runtimeMinutes,
            episodeCount: dto.episodeCount,
            seasonCount: dto.seasonCount,
            productionCompanies: dto.productionCompanies.map {
                ComparableProductionCompany(
                    id: $0.id,
                    name: $0.name,
                    logoPath: TMDbImagePath.storagePath(from: $0.logoPath)
                )
            },
            characters: normalizedCharacters(
                dto.characters.map {
                    ComparableCharacter(
                        id: $0.id,
                        characterName: $0.characterName,
                        actorName: $0.actorName,
                        profilePath: TMDbImagePath.storagePath(
                            from: $0.profilePath,
                            fallback: $0.profileURL
                        )
                    )
                }
            ),
            staff: normalizedStaff(
                dto.staff.map {
                    ComparableStaff(
                        id: $0.id,
                        name: $0.name,
                        role: $0.role,
                        department: $0.department,
                        profilePath: TMDbImagePath.storagePath(
                            from: $0.profilePath,
                            fallback: $0.profileURL
                        ),
                        jobs: normalizedStaffJobs(
                            $0.jobs.map {
                                ComparableStaffJob(
                                    creditID: $0.creditID,
                                    job: $0.job,
                                    episodeCount: $0.episodeCount
                                )
                            }
                        )
                    )
                }
            ),
            seasons: normalizedSeasons(
                dto.seasons.map {
                    ComparableSeason(
                        id: $0.id,
                        seasonNumber: $0.seasonNumber,
                        title: $0.title,
                        posterPath: TMDbImagePath.storagePath(
                            from: $0.posterPath,
                            fallback: $0.posterURL
                        ),
                        episodeCount: $0.episodeCount
                    )
                }
            ),
            episodes: normalizedEpisodes(
                dto.episodes.map {
                    ComparableEpisode(
                        id: $0.id,
                        episodeNumber: $0.episodeNumber,
                        title: $0.title,
                        airDate: $0.airDate,
                        imagePath: TMDbImagePath.storagePath(
                            from: $0.imagePath,
                            fallback: $0.imageURL
                        )
                    )
                }
            )
        )
    }

    private static func normalizedCharacters(
        _ characters: [ComparableCharacter]
    ) -> [ComparableCharacter] {
        characters.sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.characterName != $1.characterName { return $0.characterName < $1.characterName }
            if $0.actorName != $1.actorName { return $0.actorName < $1.actorName }
            return ($0.profilePath ?? "") < ($1.profilePath ?? "")
        }
    }

    private static func normalizedStaffJobs(
        _ jobs: [ComparableStaffJob]
    ) -> [ComparableStaffJob] {
        jobs.sorted {
            staffJobSortKey($0) < staffJobSortKey($1)
        }
    }

    private static func normalizedStaff(
        _ staff: [ComparableStaff]
    ) -> [ComparableStaff] {
        staff.sorted {
            staffSortKey($0) < staffSortKey($1)
        }
    }

    private static func staffJobSortKey(_ job: ComparableStaffJob) -> String {
        [
            job.creditID,
            job.job,
            String(job.episodeCount)
        ].joined(separator: "\u{1F}")
    }

    private static func staffSortKey(_ staff: ComparableStaff) -> String {
        [
            String(staff.id),
            staff.name,
            staff.role,
            staff.department ?? "",
            staff.profilePath ?? "",
            staff.jobs.map(staffJobSortKey).joined(separator: "\u{1E}")
        ].joined(separator: "\u{1F}")
    }

    private static func normalizedSeasons(
        _ seasons: [ComparableSeason]
    ) -> [ComparableSeason] {
        seasons.sorted {
            if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.title != $1.title { return $0.title < $1.title }
            if ($0.posterPath ?? "") != ($1.posterPath ?? "") {
                return ($0.posterPath ?? "") < ($1.posterPath ?? "")
            }
            return ($0.episodeCount ?? -1) < ($1.episodeCount ?? -1)
        }
    }

    private static func normalizedEpisodes(
        _ episodes: [ComparableEpisode]
    ) -> [ComparableEpisode] {
        episodes.sorted {
            if $0.episodeNumber != $1.episodeNumber { return $0.episodeNumber < $1.episodeNumber }
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.title != $1.title { return $0.title < $1.title }
            if $0.airDate != $1.airDate {
                return ($0.airDate ?? .distantPast) < ($1.airDate ?? .distantPast)
            }
            return ($0.imagePath ?? "") < ($1.imagePath ?? "")
        }
    }

}
