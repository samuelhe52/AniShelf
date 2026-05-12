//
//  InfoFetcher+Series.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/12.
//

import DataProvider
import Foundation
import TMDb

private struct TVSeriesPayload {
    let series: TVSeries
    let imageResources: ImageCollection
    let imagesConfiguration: ImagesConfiguration
    let translations: TranslationDictionaries?
    let credits: TVSeriesAggregateCredits?

    func requiredTranslations() -> TranslationDictionaries {
        guard let translations else {
            preconditionFailure("TV series translations were not loaded")
        }
        return translations
    }

    func requiredCredits() -> TVSeriesAggregateCredits {
        guard let credits else {
            preconditionFailure("TV series credits were not loaded")
        }
        return credits
    }
}

extension InfoFetcher {
    func tvSeriesInfo(tmdbID: Int, language: Language) async throws -> BasicInfo {
        let payload = try await tvSeriesPayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true
        )

        return tvSeriesBasicInfo(
            from: payload.series,
            imageResources: payload.imageResources,
            translations: payload.requiredTranslations(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func postersForSeries(seriesID tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        async let collection = tmdbClient.tvSeries.images(forTVSeries: tmdbID)
        async let imagesConfiguration = imagesConfiguration()
        let resolvedCollection = try await collection
        return makePosterURLs(
            from: resolvedCollection.posters,
            idealWidth: idealWidth,
            imagesConfiguration: try await imagesConfiguration
        )
    }

    func backdropsForSeries(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.backdropURLs(forTVSeries: tmdbID, idealWidth: idealWidth)
    }

    func logosForSeries(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.logoURLs(forTVSeries: tmdbID, idealWidth: idealWidth)
    }

    func tvSeriesDetail(
        tmdbID: Int,
        language: Language
    ) async throws -> AnimeEntryDetailDTO {
        let payload = try await tvSeriesPayload(
            tmdbID: tmdbID,
            language: language,
            includeCredits: true
        )

        return tvSeriesDetail(
            from: payload.series,
            imageResources: payload.imageResources,
            credits: payload.requiredCredits(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func latestTVSeriesInfo(tmdbID: Int, language: Language) async throws
        -> (BasicInfo, AnimeEntryDetailDTO)
    {
        let payload = try await tvSeriesPayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true,
            includeCredits: true
        )

        return (
            tvSeriesBasicInfo(
                from: payload.series,
                imageResources: payload.imageResources,
                translations: payload.requiredTranslations(),
                imagesConfiguration: payload.imagesConfiguration,
                language: language
            ),
            tvSeriesDetail(
                from: payload.series,
                imageResources: payload.imageResources,
                credits: payload.requiredCredits(),
                imagesConfiguration: payload.imagesConfiguration,
                language: language
            )
        )
    }

    private func tvSeriesPayload(
        tmdbID: Int,
        language: Language,
        includeTranslations: Bool = false,
        includeCredits: Bool = false
    ) async throws -> TVSeriesPayload {
        async let resolvedSeries = tvSeries(tmdbID, language: language)
        async let resolvedImageResources = tmdbClient.tvSeries.images(forTVSeries: tmdbID)
        async let resolvedImagesConfiguration = imagesConfiguration()

        let translationsTask = includeTranslations
            ? Task { try await tvSeriesTranslations(tmdbID: tmdbID) }
            : nil
        let creditsTask = includeCredits
            ? Task {
                try await tmdbClient.tvSeries.aggregateCredits(
                    forTVSeries: tmdbID,
                    language: language.rawValue
                )
            }
            : nil
        defer {
            translationsTask?.cancel()
            creditsTask?.cancel()
        }

        return TVSeriesPayload(
            series: try await resolvedSeries,
            imageResources: try await resolvedImageResources,
            imagesConfiguration: try await resolvedImagesConfiguration,
            translations: try await translationsTask?.value,
            credits: try await creditsTask?.value
        )
    }

    private func tvSeriesBasicInfo(
        from series: TVSeries,
        imageResources: ImageCollection,
        translations: TranslationDictionaries,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> BasicInfo {
        BasicInfo(
            name: series.name,
            nameTranslations: translations.name,
            overview: series.overview,
            overviewTranslations: translations.overview,
            posterURL: imagesConfiguration.posterURL(
                for: TMDbImageSelection.preferredPosterPath(
                    from: imageResources.posters,
                    originalLanguageCode: series.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: .max
            ),
            backdropURL: imagesConfiguration.backdropURL(
                for: TMDbImageSelection.preferredBackdropPath(from: imageResources.backdrops),
                idealWidth: .max
            ),
            logoURL: imagesConfiguration.logoURL(
                for: TMDbImageSelection.preferredLogoPath(
                    from: imageResources.logos,
                    originalLanguageCode: series.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: .max
            ),
            originalLanguageCode: series.originalLanguage,
            tmdbID: series.id,
            onAirDate: series.firstAirDate,
            linkToDetails: series.homepageURL,
            type: .series
        )
    }

    private func tvSeriesDetail(
        from series: TVSeries,
        imageResources: ImageCollection,
        credits: TVSeriesAggregateCredits,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> AnimeEntryDetailDTO {
        AnimeEntryDetailDTO(
            language: language.rawValue,
            title: series.name,
            subtitle: series.tagline?.nilIfEmpty,
            overview: series.overview?.nilIfEmpty,
            status: series.status,
            airDate: series.firstAirDate,
            primaryLinkURL: series.homepageURL,
            heroImageURL: imagesConfiguration.backdropURL(
                for: TMDbImageSelection.preferredBackdropPath(from: imageResources.backdrops),
                idealWidth: 1_280
            ),
            logoImageURL: imagesConfiguration.logoURL(
                for: TMDbImageSelection.preferredLogoPath(
                    from: imageResources.logos,
                    originalLanguageCode: series.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: 500
            ),
            genreIDs: series.genres?.map(\.id) ?? [],
            voteAverage: series.voteAverage,
            runtimeMinutes: series.episodeRunTime?.first,
            episodeCount: series.numberOfEpisodes,
            seasonCount: series.numberOfSeasons,
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
            seasons: makeSeasonSummaries(
                from: series.seasons ?? [],
                imagesConfiguration: imagesConfiguration
            )
        )
    }

    private func makeSeasonSummaries(
        from seasons: [TVSeason],
        imagesConfiguration: ImagesConfiguration
    ) -> [AnimeEntrySeasonSummaryDTO] {
        seasons.map {
            AnimeEntrySeasonSummaryDTO(
                id: $0.id,
                seasonNumber: $0.seasonNumber,
                title: $0.name,
                posterURL: imagesConfiguration.posterURL(for: $0.posterPath, idealWidth: 300)
            )
        }
    }
}
