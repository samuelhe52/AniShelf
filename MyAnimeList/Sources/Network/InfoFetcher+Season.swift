//
//  InfoFetcher+Season.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/12.
//

import DataProvider
import Foundation
import TMDb

fileprivate struct TVSeasonPayload {
    let parentSeries: TVSeries
    let season: TVSeason
    let parentSeriesImages: ImageCollection
    let imagesConfiguration: ImagesConfiguration
    let seasonPosters: [ImageMetadata]?
    let translations: TranslationDictionaries?
    let credits: TVSeasonAggregateCredits?

    func requiredTranslations() -> TranslationDictionaries {
        guard let translations else {
            preconditionFailure("TV season translations were not loaded")
        }
        return translations
    }

    func requiredCredits() -> TVSeasonAggregateCredits {
        guard let credits else {
            preconditionFailure("TV season credits were not loaded")
        }
        return credits
    }
}

extension InfoFetcher {
    func tvSeasonInfo(seasonNumber: Int, parentSeriesID: Int, language: Language) async throws
        -> BasicInfo
    {
        let payload = try await tvSeasonPayload(
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber,
            language: language,
            includeTranslations: true,
            includeSeasonPosters: true
        )

        return tvSeasonBasicInfo(
            from: payload.season,
            parentSeries: payload.parentSeries,
            parentSeriesImages: payload.parentSeriesImages,
            seasonPosters: payload.seasonPosters,
            translations: payload.requiredTranslations(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func postersForSeason(
        forSeason seasonNumber: Int,
        inParentSeries parentSeriesID: Int,
        idealWidth: Int = .max
    ) async throws -> [ImageURLWithMetadata] {
        async let collection = tmdbClient.tvSeasons.images(
            forSeason: seasonNumber,
            inTVSeries: parentSeriesID
        )
        async let imagesConfiguration = imagesConfiguration()
        let resolvedCollection = try await collection
        return makePosterURLs(
            from: resolvedCollection.posters,
            idealWidth: idealWidth,
            imagesConfiguration: try await imagesConfiguration
        )
    }

    func seasonInfos(
        forSeriesID tmdbID: Int,
        language: Language
    ) async throws -> [BasicInfo] {
        let series = try await tvSeries(tmdbID, language: language)
        guard let seasons = series.seasons else { return [] }

        async let parentSeriesImages = tmdbClient.tvSeries.images(forTVSeries: tmdbID)
        async let imagesConfiguration = imagesConfiguration()
        let resolvedParentSeriesImages = try await parentSeriesImages
        let resolvedImagesConfiguration = try await imagesConfiguration

        return try await withThrowingTaskGroup(of: BasicInfo.self) { group in
            var results: [BasicInfo] = []

            for season in seasons {
                group.addTask {
                    async let seasonPosters = self.bestEffortSeasonPosters(
                        forSeason: season.seasonNumber,
                        inTVSeries: tmdbID
                    )
                    async let translations = self.tvSeasonTranslations(
                        parentSeriesID: tmdbID,
                        seasonNumber: season.seasonNumber
                    )

                    return self.tvSeasonBasicInfo(
                        from: season,
                        parentSeries: series,
                        parentSeriesImages: resolvedParentSeriesImages,
                        seasonPosters: await seasonPosters,
                        translations: try await translations,
                        imagesConfiguration: resolvedImagesConfiguration,
                        language: language
                    )
                }
            }

            for try await info in group {
                results.append(info)
            }

            return results.sorted { ($0.type.seasonNumber ?? 0) < ($1.type.seasonNumber ?? 0) }
        }
    }

    func seasonEpisodeSummaries(
        parentSeriesID: Int,
        seasonNumber: Int,
        language: Language
    ) async throws -> [AnimeEntryEpisodeSummaryDTO] {
        let season = try await tvSeason(parentSeriesID, seasonNumber: seasonNumber, language: language)
        return makeEpisodeSummaries(
            from: season.episodes ?? [],
            imagesConfiguration: try await imagesConfiguration()
        )
    }

    func tvSeasonDetail(
        seasonNumber: Int,
        parentSeriesID: Int,
        language: Language
    ) async throws -> AnimeEntryDetailDTO {
        let payload = try await tvSeasonPayload(
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber,
            language: language,
            includeCredits: true
        )

        return tvSeasonDetail(
            from: payload.season,
            parentSeries: payload.parentSeries,
            parentSeriesImages: payload.parentSeriesImages,
            credits: payload.requiredCredits(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func latestTVSeasonInfo(
        parentSeriesID: Int,
        seasonNumber: Int,
        language: Language
    ) async throws -> (BasicInfo, AnimeEntryDetailDTO) {
        let payload = try await tvSeasonPayload(
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber,
            language: language,
            includeTranslations: true,
            includeCredits: true,
            includeSeasonPosters: true
        )

        return (
            tvSeasonBasicInfo(
                from: payload.season,
                parentSeries: payload.parentSeries,
                parentSeriesImages: payload.parentSeriesImages,
                seasonPosters: payload.seasonPosters,
                translations: payload.requiredTranslations(),
                imagesConfiguration: payload.imagesConfiguration,
                language: language
            ),
            tvSeasonDetail(
                from: payload.season,
                parentSeries: payload.parentSeries,
                parentSeriesImages: payload.parentSeriesImages,
                credits: payload.requiredCredits(),
                imagesConfiguration: payload.imagesConfiguration,
                language: language
            )
        )
    }

    private func tvSeasonPayload(
        parentSeriesID: Int,
        seasonNumber: Int,
        language: Language,
        includeTranslations: Bool = false,
        includeCredits: Bool = false,
        includeSeasonPosters: Bool = false
    ) async throws -> TVSeasonPayload {
        async let resolvedParentSeries = tvSeries(parentSeriesID, language: language)
        async let resolvedSeason = tvSeason(parentSeriesID, seasonNumber: seasonNumber, language: language)
        async let resolvedParentSeriesImages = tmdbClient.tvSeries.images(forTVSeries: parentSeriesID)
        async let resolvedImagesConfiguration = imagesConfiguration()

        let translationsTask =
            includeTranslations
            ? Task {
                try await tvSeasonTranslations(
                    parentSeriesID: parentSeriesID,
                    seasonNumber: seasonNumber
                )
            }
            : nil
        let creditsTask =
            includeCredits
            ? Task {
                try await tmdbClient.tvSeasons.aggregateCredits(
                    forSeason: seasonNumber,
                    inTVSeries: parentSeriesID,
                    language: language.rawValue
                )
            }
            : nil
        let seasonPostersTask =
            includeSeasonPosters
            ? Task {
                await bestEffortSeasonPosters(
                    forSeason: seasonNumber,
                    inTVSeries: parentSeriesID
                )
            }
            : nil
        defer {
            translationsTask?.cancel()
            creditsTask?.cancel()
            seasonPostersTask?.cancel()
        }

        return TVSeasonPayload(
            parentSeries: try await resolvedParentSeries,
            season: try await resolvedSeason,
            parentSeriesImages: try await resolvedParentSeriesImages,
            imagesConfiguration: try await resolvedImagesConfiguration,
            seasonPosters: await seasonPostersTask?.value,
            translations: try await translationsTask?.value,
            credits: try await creditsTask?.value
        )
    }

    private func tvSeasonBasicInfo(
        from season: TVSeason,
        parentSeries: TVSeries,
        parentSeriesImages: ImageCollection,
        seasonPosters: [ImageMetadata]?,
        translations: TranslationDictionaries,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> BasicInfo {
        BasicInfo(
            name: season.name,
            nameTranslations: translations.name,
            overview: season.overview,
            overviewTranslations: translations.overview,
            posterURL: imagesConfiguration.posterURL(
                for: TMDbImageSelection.preferredPosterPath(
                    from: seasonPosters ?? [],
                    originalLanguageCode: parentSeries.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ) ?? season.posterPath
            ),
            backdropURL: imagesConfiguration.backdropURL(
                for: TMDbImageSelection.preferredBackdropPath(from: parentSeriesImages.backdrops),
                idealWidth: .max
            ),
            logoURL: imagesConfiguration.logoURL(
                for: TMDbImageSelection.preferredLogoPath(
                    from: parentSeriesImages.logos,
                    originalLanguageCode: parentSeries.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: .max
            ),
            originalLanguageCode: parentSeries.originalLanguage,
            tmdbID: season.id,
            onAirDate: season.airDate,
            linkToDetails: parentSeries.homepageURL,
            type: .season(seasonNumber: season.seasonNumber, parentSeriesID: parentSeries.id)
        )
    }

    private func tvSeasonDetail(
        from season: TVSeason,
        parentSeries: TVSeries,
        parentSeriesImages: ImageCollection,
        credits: TVSeasonAggregateCredits,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> AnimeEntryDetailDTO {
        AnimeEntryDetailDTO(
            language: language.rawValue,
            title: parentSeries.name,
            subtitle: season.name,
            overview: season.overview?.nilIfEmpty,
            status: parentSeries.status,
            airDate: season.airDate,
            primaryLinkURL: parentSeries.homepageURL,
            heroImageURL: imagesConfiguration.backdropURL(
                for: TMDbImageSelection.preferredBackdropPath(from: parentSeriesImages.backdrops),
                idealWidth: 1_280
            ),
            logoImageURL: imagesConfiguration.logoURL(
                for: TMDbImageSelection.preferredLogoPath(
                    from: parentSeriesImages.logos,
                    originalLanguageCode: parentSeries.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: 500
            ),
            genreIDs: parentSeries.genres?.map(\.id) ?? [],
            voteAverage: parentSeries.voteAverage,
            runtimeMinutes: parentSeries.episodeRunTime?.first,
            episodeCount: season.episodes?.count,
            characters: makeCharacters(
                from: credits.cast.prefix(12),
                imagesConfiguration: imagesConfiguration,
                language: language
            ),
            staff: makeStaff(
                from: credits.crew,
                imagesConfiguration: imagesConfiguration,
                language: language
            ),
            episodes: makeEpisodeSummaries(
                from: season.episodes ?? [],
                imagesConfiguration: imagesConfiguration
            )
        )
    }

    private func makeEpisodeSummaries(
        from episodes: [TVEpisode],
        imagesConfiguration: ImagesConfiguration
    ) -> [AnimeEntryEpisodeSummaryDTO] {
        episodes.map {
            AnimeEntryEpisodeSummaryDTO(
                id: $0.id,
                episodeNumber: $0.episodeNumber,
                title: $0.name,
                airDate: $0.airDate,
                imageURL: imagesConfiguration.stillURL(for: $0.stillPath, idealWidth: 500)
            )
        }
    }

    private func bestEffortSeasonPosters(
        forSeason seasonNumber: Int,
        inTVSeries parentSeriesID: Int
    ) async -> [ImageMetadata]? {
        try? await tmdbClient.tvSeasons.images(
            forSeason: seasonNumber,
            inTVSeries: parentSeriesID
        ).posters
    }
}
