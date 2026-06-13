//
//  InfoFetcher+Movie.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/12.
//

import DataProvider
import Foundation
import TMDb

fileprivate struct MoviePayload {
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
    /// Returns localized movie info only when the TMDb entry is tagged as animation.
    ///
    /// Non-animation movies return `nil` so direct ID batch lookups obey AniShelf's anime-only policy.
    func animeMovieInfo(tmdbID: Int, language: Language) async throws -> EntryMetadata? {
        let payload = try await moviePayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true
        )

        guard payload.movie.genres?.contains(where: { $0.id == 16 }) == true else {
            return nil
        }

        return movieEntryMetadata(
            from: payload.movie,
            imageResources: payload.imageResources,
            translations: payload.requiredTranslations(),
            imagesConfiguration: payload.imagesConfiguration,
            language: language
        )
    }

    func movieInfo(tmdbID: Int, language: Language) async throws -> EntryMetadata {
        let payload = try await moviePayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true
        )

        return movieEntryMetadata(
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
        async let collection = tmdbClient.movies.images(
            forMovie: tmdbID,
            filter: TMDbImageFilters.movie
        )
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
        -> (EntryMetadata, AnimeEntryDetailDTO)
    {
        let payload = try await moviePayload(
            tmdbID: tmdbID,
            language: language,
            includeTranslations: true,
            includeCredits: true
        )

        return (
            movieEntryMetadata(
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
        async let resolvedImageResources = tmdbClient.movies.images(
            forMovie: tmdbID,
            filter: TMDbImageFilters.movie
        )
        async let resolvedImagesConfiguration = imagesConfiguration()

        let translationsTask =
            includeTranslations
            ? Task { try await movieTranslations(tmdbID: tmdbID) }
            : nil
        let creditsTask =
            includeCredits
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

    private func movieEntryMetadata(
        from movie: Movie,
        imageResources: ImageCollection,
        translations: TranslationDictionaries,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> EntryMetadata {
        EntryMetadata(
            name: movie.title,
            nameTranslations: translations.name,
            overview: movie.overview,
            overviewTranslations: translations.overview,
            posterPath: TMDbImagePath.storagePath(
                from: TMDbImageSelection.preferredPosterPath(
                    from: imageResources.posters,
                    originalLanguageCode: movie.originalLanguage,
                    metadataLanguageCode: language.rawValue
                )
            ),
            backdropPath: TMDbImagePath.storagePath(
                from: TMDbImageSelection.preferredBackdropPath(from: imageResources.backdrops)
            ),
            logoPath: TMDbImagePath.storagePath(
                from: TMDbImageSelection.preferredLogoPath(
                    from: imageResources.logos,
                    originalLanguageCode: movie.originalLanguage,
                    metadataLanguageCode: language.rawValue
                )
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
            heroImagePath: TMDbImagePath.storagePath(
                from: TMDbImageSelection.preferredBackdropPath(from: imageResources.backdrops)
            ),
            logoImagePath: TMDbImagePath.storagePath(
                from: TMDbImageSelection.preferredLogoPath(
                    from: imageResources.logos,
                    originalLanguageCode: movie.originalLanguage,
                    metadataLanguageCode: language.rawValue
                )
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
                    profilePath: TMDbImagePath.storagePath(from: $0.profilePath)
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
