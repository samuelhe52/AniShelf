//
//  InfoFetcher+Movie.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/12.
//

import DataProvider
import Foundation
import TMDb

private struct MoviePayload {
    let movie: Movie
    let imageResources: ImageCollection
    let imagesConfiguration: ImagesConfiguration
    let translations: TranslationDictionaries?
    let credits: ShowCredits?

    func requiredTranslations() -> TranslationDictionaries {
        guard let translations else {
            preconditionFailure("Movie translations were not loaded")
        }
        return translations
    }

    func requiredCredits() -> ShowCredits {
        guard let credits else {
            preconditionFailure("Movie credits were not loaded")
        }
        return credits
    }
}

extension InfoFetcher {
    func movieInfo(tmdbID: Int, language: Language) async throws -> BasicInfo {
        let payload = try await moviePayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true
        )

        return movieBasicInfo(
            from: payload.movie,
            imageResources: payload.imageResources,
            translations: payload.requiredTranslations(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func postersForMovie(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        async let collection = tmdbClient.movies.images(forMovie: tmdbID)
        async let imagesConfiguration = imagesConfiguration()
        let resolvedCollection = try await collection
        return makePosterURLs(
            from: resolvedCollection.posters,
            idealWidth: idealWidth,
            imagesConfiguration: try await imagesConfiguration
        )
    }

    func backdropsForMovie(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.backdropURLs(forMovie: tmdbID, idealWidth: idealWidth)
    }

    func logosForMovie(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.logoURLs(forMovie: tmdbID, idealWidth: idealWidth)
    }

    func movieDetail(
        tmdbID: Int,
        language: Language
    ) async throws -> AnimeEntryDetailDTO {
        let payload = try await moviePayload(
            tmdbID: tmdbID,
            language: language,
            includeCredits: true
        )

        return movieDetail(
            from: payload.movie,
            imageResources: payload.imageResources,
            credits: payload.requiredCredits(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func latestMovieInfo(tmdbID: Int, language: Language) async throws
        -> (BasicInfo, AnimeEntryDetailDTO)
    {
        let payload = try await moviePayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true,
            includeCredits: true
        )

        return (
            movieBasicInfo(
                from: payload.movie,
                imageResources: payload.imageResources,
                translations: payload.requiredTranslations(),
                imagesConfiguration: payload.imagesConfiguration,
                language: language
            ),
            movieDetail(
                from: payload.movie,
                imageResources: payload.imageResources,
                credits: payload.requiredCredits(),
                imagesConfiguration: payload.imagesConfiguration,
                language: language
            )
        )
    }

    private func moviePayload(
        tmdbID: Int,
        language: Language,
        includeTranslations: Bool = false,
        includeCredits: Bool = false
    ) async throws -> MoviePayload {
        async let resolvedMovie = movie(tmdbID, language: language)
        async let resolvedImageResources = tmdbClient.movies.images(forMovie: tmdbID)
        async let resolvedImagesConfiguration = imagesConfiguration()

        let translationsTask = includeTranslations
            ? Task { try await movieTranslations(tmdbID: tmdbID) }
            : nil
        let creditsTask = includeCredits
            ? Task { try await tmdbClient.movies.credits(forMovie: tmdbID, language: language.rawValue) }
            : nil
        defer {
            translationsTask?.cancel()
            creditsTask?.cancel()
        }

        return MoviePayload(
            movie: try await resolvedMovie,
            imageResources: try await resolvedImageResources,
            imagesConfiguration: try await resolvedImagesConfiguration,
            translations: try await translationsTask?.value,
            credits: try await creditsTask?.value
        )
    }

    private func movieBasicInfo(
        from movie: Movie,
        imageResources: ImageCollection,
        translations: TranslationDictionaries,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> BasicInfo {
        BasicInfo(
            name: movie.title,
            nameTranslations: translations.name,
            overview: movie.overview,
            overviewTranslations: translations.overview,
            posterURL: imagesConfiguration.posterURL(
                for: TMDbImageSelection.preferredPosterPath(
                    from: imageResources.posters,
                    originalLanguageCode: movie.originalLanguage,
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
                    originalLanguageCode: movie.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: .max
            ),
            originalLanguageCode: movie.originalLanguage,
            tmdbID: movie.id,
            onAirDate: movie.releaseDate,
            linkToDetails: movie.homepageURL,
            type: .movie
        )
    }

    private func movieDetail(
        from movie: Movie,
        imageResources: ImageCollection,
        credits: ShowCredits,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> AnimeEntryDetailDTO {
        AnimeEntryDetailDTO(
            language: language.rawValue,
            title: movie.title,
            subtitle: movie.tagline?.nilIfEmpty,
            overview: movie.overview?.nilIfEmpty,
            status: movie.status?.rawValue,
            airDate: movie.releaseDate,
            primaryLinkURL: movie.homepageURL,
            heroImageURL: imagesConfiguration.backdropURL(
                for: TMDbImageSelection.preferredBackdropPath(from: imageResources.backdrops),
                idealWidth: 1_280
            ),
            logoImageURL: imagesConfiguration.logoURL(
                for: TMDbImageSelection.preferredLogoPath(
                    from: imageResources.logos,
                    originalLanguageCode: movie.originalLanguage,
                    metadataLanguageCode: language.rawValue
                ),
                idealWidth: 500
            ),
            genreIDs: movie.genres?.map(\.id) ?? [],
            voteAverage: movie.voteAverage,
            runtimeMinutes: movie.runtime,
            characters: credits.cast.prefix(12).map {
                AnimeEntryCharacterDTO(
                    id: $0.id,
                    characterName: $0.character.strippingVoiceQualifier.nilIfEmpty ?? "Character",
                    actorName: Self.preferredActorName(
                        localizedName: $0.name,
                        originalName: nil,
                        language: language
                    ),
                    profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
                )
            },
            staff: makeStaff(
                from: credits.crew.prefix(12),
                imagesConfiguration: imagesConfiguration,
                language: language
            )
        )
    }
}
