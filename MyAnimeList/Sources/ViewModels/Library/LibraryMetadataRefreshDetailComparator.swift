//
//  LibraryMetadataRefreshDetailComparator.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/14.
//

import DataProvider
import Foundation

enum LibraryMetadataRefreshDetailComparator {
    fileprivate struct ComparableProductionCompany: Equatable {
        let id: Int
        let name: String
        let logoPath: String?
    }

    fileprivate struct ComparableCharacter: Equatable {
        let id: Int
        let characterName: String
        let actorName: String
        let profilePath: String?
    }

    fileprivate struct ComparableStaffJob: Equatable {
        let creditID: String
        let job: String
        let episodeCount: Int
    }

    fileprivate struct ComparableStaff: Equatable {
        let id: Int
        let name: String
        let role: String
        let department: String?
        let profilePath: String?
        let jobs: [ComparableStaffJob]
    }

    fileprivate struct ComparableSeason: Equatable {
        let id: Int
        let seasonNumber: Int
        let title: String
        let posterPath: String?
        let episodeCount: Int?
    }

    fileprivate struct ComparableEpisode: Equatable {
        let id: Int
        let episodeNumber: Int
        let title: String
        let airDate: Date?
        let imagePath: String?
    }

    fileprivate struct ComparableDetail: Equatable {
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

    /// The compared metadata of one detail, for callers that keep it to compare later.
    struct Content: Equatable {
        fileprivate let detail: ComparableDetail
    }

    static func matches(
        existing detail: AnimeEntryDetail?,
        fetched dto: AnimeEntryDetailDTO
    ) -> Bool {
        guard let detail else { return false }
        return content(of: detail) == content(of: dto)
    }

    static func content(of detail: AnimeEntryDetail) -> Content {
        Content(detail: comparableDetail(from: detail))
    }

    static func content(of dto: AnimeEntryDetailDTO) -> Content {
        Content(detail: comparableDetail(from: dto))
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
            // Credits and episodes compare in stored display order; genres and seasons, which the
            // detail view sorts itself, are normalized. The view lists cast and episodes in this
            // order and uses it to order staff within a role, so a response that only reorders
            // them is a change. If TMDb's order jitters, the cost is a local rewrite of this
            // detail; detail writes advance no sync clock.
            characters: detail.orderedCharacters.map {
                ComparableCharacter(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profilePath: $0.profilePath
                )
            },
            staff: detail.orderedStaff.map {
                ComparableStaff(
                    id: $0.id,
                    name: $0.name,
                    role: $0.role,
                    department: $0.department,
                    profilePath: $0.profilePath,
                    jobs: $0.orderedJobs.map {
                        ComparableStaffJob(
                            creditID: $0.creditID,
                            job: $0.job,
                            episodeCount: $0.episodeCount
                        )
                    }
                )
            },
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
            episodes: detail.orderedEpisodes.map {
                ComparableEpisode(
                    id: $0.id,
                    episodeNumber: $0.episodeNumber,
                    title: $0.title,
                    airDate: $0.airDate,
                    imagePath: $0.imagePath
                )
            }
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
            // A replacement stores credits and episodes in the response's order as `displayOrder`.
            characters: dto.characters.map {
                ComparableCharacter(
                    id: $0.id,
                    characterName: $0.characterName,
                    actorName: $0.actorName,
                    profilePath: TMDbImagePath.storagePath(
                        from: $0.profilePath,
                        fallback: $0.profileURL
                    )
                )
            },
            staff: dto.staff.map {
                ComparableStaff(
                    id: $0.id,
                    name: $0.name,
                    role: $0.role,
                    department: $0.department,
                    profilePath: TMDbImagePath.storagePath(
                        from: $0.profilePath,
                        fallback: $0.profileURL
                    ),
                    jobs: $0.jobs.map {
                        ComparableStaffJob(
                            creditID: $0.creditID,
                            job: $0.job,
                            episodeCount: $0.episodeCount
                        )
                    }
                )
            },
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
            episodes: dto.episodes.map {
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

}
