//
//  TMDbMedia+Helpers.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/29.
//

import Foundation
import TMDb
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "TMDbMediaInfoFetching")

fileprivate func firstJapanesePNGPath(from resources: [ImageMetadata]) -> URL? {
    resources
        .filter { $0.languageCode == Language.japanese.rawValue }
        .first { $0.filePath.pathExtension.caseInsensitiveCompare("png") == .orderedSame }?
        .filePath
}

extension Movie {
    /// Returns the basic information for the movie.
    ///
    /// - Parameter client: The TMDb client used to fetch image configuration.
    /// - Returns: A `BasicInfo` struct containing info about the movie.
    /// - Throws: An error if the request fails.
    func basicInfo(client: TMDbClient) async throws -> BasicInfo {
        logger.debug("Fetching basic info for movie \(self.id), name: \(name)")
        let posterURL = try await posterURL(client: client)
        let backdropURL = try await backdropURL(client: client)
        let logoURL = try await logoURL(client: client)
        let translations = try await getTranslations(client: client)
        let nameTranslations = translations.name
        let overviewTranslations = translations.overview

        logger.info("Successfully fetched basic info for movie \(self.id), name: \(name)")
        return BasicInfo(
            name: title,
            nameTranslations: nameTranslations,
            overview: overview,
            overviewTranslations: overviewTranslations,
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            tmdbID: id,
            onAirDate: releaseDate,
            linkToDetails: homepageURL,
            type: .movie
        )
    }

    /// Gets URL for the backdrop image.
    ///
    /// - Parameters:
    ///     - client: The TMDb client used for image configuration。
    ///     - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the backdrop image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func backdropURL(client: TMDb.TMDbClient, idealWidth: Int = .max) async throws -> URL? {
        let imageResources = try await client.movies.images(forMovie: id)
        let backdropPath = imageResources.backdrops.first?.filePath
        let url = try await client.imagesConfiguration.backdropURL(
            for: backdropPath, idealWidth: idealWidth)
        return url
    }

    /// Gets URL for the poster image.
    ///
    /// - Parameters:
    ///     - client: The TMDb client used for image configuration.
    ///     - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the poster image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func posterURL(client: TMDb.TMDbClient, idealWidth: Int = .max) async throws -> URL? {
        let imageResources = try await client.movies.images(forMovie: id)
        let posterPath = imageResources.posters
            .filter { $0.languageCode == Language.japanese.rawValue }
            .first?
            .filePath
        let url = try await client.imagesConfiguration.posterURL(
            for: posterPath, idealWidth: idealWidth)
        return url
    }

    /// Gets URL for the logo image.
    ///
    /// - Parameters:
    ///     - client: The TMDb client used for image configuration.
    ///     - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the logo image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func logoURL(client: TMDb.TMDbClient, idealWidth: Int = .max) async throws -> URL? {
        let imageResources = try await client.movies.images(forMovie: id)
        let logoPath = firstJapanesePNGPath(from: imageResources.logos)
        let url = try await client.imagesConfiguration.logoURL(
            for: logoPath, idealWidth: idealWidth)
        return url
    }

    /// Gets translations for the movie.
    ///
    /// - Parameters:
    ///  - client: The TMDb client used to fetch translations.
    func getTranslations(client: TMDbClient) async throws -> (
        name: [String: String], overview: [String: String]
    ) {
        let translations = try await client.movies.translations(forMovie: id).translations
        let nameTranslations = translations.reduce(into: [String: String]()) {
            result, translation in
            result[translation.languageCode + "-" + translation.countryCode] = translation.data.name
        }
        let overviewTranslations = translations.reduce(into: [String: String]()) {
            result, translation in
            result[translation.languageCode + "-" + translation.countryCode] =
                translation.data.overview
        }
        logger.info(
            "Fetched \(nameTranslations.count) name translations and \(overviewTranslations.count) overview translations for movie \(self.id)"
        )
        return (name: nameTranslations, overview: overviewTranslations)
    }

    var name: String { title }
    var onAirDate: Date? { releaseDate }
    var linkToDetails: URL? { homepageURL }
}

extension TVSeries {
    /// Returns the basic information for the TV series.
    ///
    /// - Parameter client: The TMDb client used to fetch image configuration.
    /// - Returns: A `BasicInfo` struct containing info about the TV series.
    /// - Throws: An error if the request fails.
    func basicInfo(client: TMDbClient) async throws -> BasicInfo {
        logger.debug("Fetching basic info for TV series \(self.id), name: \(name)")
        let posterURL = try await posterURL(client: client)
        let backdropURL = try await backdropURL(client: client)
        let logoURL = try await logoURL(client: client)
        let translations = try await getTranslations(client: client)
        let nameTranslations = translations.name
        let overviewTranslations = translations.overview

        logger.info("Successfully fetched basic info for TV series \(self.id), name: \(name)")
        return BasicInfo(
            name: name,
            nameTranslations: nameTranslations,
            overview: overview,
            overviewTranslations: overviewTranslations,
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            tmdbID: id,
            onAirDate: firstAirDate,
            linkToDetails: homepageURL,
            type: .series
        )
    }

    /// Gets URL for the poster image.
    ///
    /// - Parameters:
    ///     - client: The TMDb client used for image configuration.
    ///     - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the poster image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func posterURL(client: TMDbClient, idealWidth: Int = .max) async throws -> URL? {
        let imageResources = try await client.tvSeries.images(forTVSeries: id)
        let posterPath = imageResources.posters
            .filter { $0.languageCode == Language.japanese.rawValue }
            .first?
            .filePath
        return try await client.imagesConfiguration.posterURL(
            for: posterPath, idealWidth: idealWidth)
    }

    /// Gets URL for the backdrop image.
    ///
    /// - Parameters:
    ///     - client: The TMDb client used for image configuration.
    ///     - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the backdrop image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func backdropURL(client: TMDbClient, idealWidth: Int = .max) async throws -> URL? {
        let imageResources = try await client.tvSeries.images(forTVSeries: id)
        let backdropPath = imageResources.backdrops.first?.filePath
        return try await client.imagesConfiguration.backdropURL(
            for: backdropPath, idealWidth: idealWidth)
    }

    /// Gets URL for the logo image.
    ///
    /// - Parameters:
    ///     - client: The TMDb client used for image configuration.
    ///     - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the logo image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func logoURL(client: TMDbClient, idealWidth: Int = .max) async throws -> URL? {
        let imageResources = try await client.tvSeries.images(forTVSeries: id)
        let logoPath = firstJapanesePNGPath(from: imageResources.logos)
        return try await client.imagesConfiguration.logoURL(for: logoPath, idealWidth: idealWidth)
    }

    /// Gets translations for the TV series.
    ///
    /// - Parameters:
    ///  - client: The TMDb client used to fetch translations.
    func getTranslations(client: TMDbClient) async throws -> (
        name: [String: String], overview: [String: String]
    ) {
        let translations = try await client.tvSeries.translations(forTVSeries: id).translations
        let nameTranslations = translations.reduce(into: [String: String]()) {
            result, translation in
            result[translation.languageCode + "-" + translation.countryCode] = translation.data.name
        }
        let overviewTranslations = translations.reduce(into: [String: String]()) {
            result, translation in
            result[translation.languageCode + "-" + translation.countryCode] =
                translation.data.overview
        }
        logger.info(
            "Fetched \(nameTranslations.count) name translations and \(overviewTranslations.count) overview translations for TV series \(self.id)"
        )
        return (name: nameTranslations, overview: overviewTranslations)
    }

    var onAirDate: Date? { firstAirDate }
    var linkToDetails: URL? { homepageURL }
}

extension TVSeason {
    ///
    /// Returns the basic information for the TV season.
    ///
    /// - Parameters:
    ///   - client: The TMDb client used to fetch image configuration.
    ///   - backdropURL: A backdrop URL that the returned `BasicInfo` uses. Default to nil since seasons don't have their own backdrops.
    ///   - logoURL: A logo URL that the returned `BasicInfo` uses. Default to nil since seasons don't have their own logos.
    ///   - linkToDetails: A homepage URL for this season. Default to nil since seasons don't have their own homepages.
    ///   - parentSeriesID: This season's parent series' TMDB ID.
    /// - Returns: A `BasicInfo` struct containing info about the TV season.
    /// - Throws: An error if the request fails.
    func basicInfo(
        client: TMDbClient,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        linkToDetails: URL? = nil,
        parentSeriesID: Int
    ) async throws -> BasicInfo {
        logger.debug(
            "Fetching basic info for season \(self.seasonNumber) of series \(parentSeriesID), name: \(name)"
        )
        let seasonPoster: URL? = try await client.imagesConfiguration.posterURL(for: posterPath)
        logger.info(
            "Successfully fetched basic info for season \(self.seasonNumber) of series \(parentSeriesID), name: \(name)"
        )
        let translations = try await getTranslations(client: client, parentSeriesID: parentSeriesID)
        let nameTranslations = translations.name
        let overviewTranslations = translations.overview
        return BasicInfo(
            name: name,
            nameTranslations: nameTranslations,
            overview: overview,
            overviewTranslations: overviewTranslations,
            posterURL: seasonPoster,
            backdropURL: backdropURL,
            logoURL: logoURL,
            tmdbID: id,
            onAirDate: airDate,
            linkToDetails: linkToDetails,
            type: .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID)
        )
    }

    /// Gets URL for the season's poster image.
    ///
    /// - Parameters:
    ///   - parentSeriesID: The ID of the parent TV series.
    ///   - client: The TMDb client used for image configuration.
    ///   - idealWidth: The preferred width of the returned image. The actual image may be larger.
    /// - Returns: URL for the poster image, or `nil` if not available.
    /// - Throws: An error if the request fails.
    func posterURL(parentSeriesID: Int, client: TMDbClient, idealWidth: Int = .max) async throws
        -> URL?
    {
        let imageResources = try await client.tvSeasons.images(
            forSeason: seasonNumber, inTVSeries: parentSeriesID)
        let posterPath = imageResources.posters
            .filter { $0.languageCode == Language.japanese.rawValue }
            .first?
            .filePath
        return try await client.imagesConfiguration.posterURL(
            for: posterPath, idealWidth: idealWidth)
    }

    /// Gets translations for the TV season.
    ///
    /// - Parameters:
    ///  - client: The TMDb client used to fetch translations.
    func getTranslations(client: TMDbClient, parentSeriesID: Int) async throws -> (
        name: [String: String], overview: [String: String]
    ) {
        let translations = try await client.tvSeasons.translations(
            forSeason: seasonNumber, inTVSeries: parentSeriesID
        ).translations
        let nameTranslations = translations.reduce(into: [String: String]()) {
            result, translation in
            result[translation.languageCode + "-" + translation.countryCode] = translation.data.name
        }
        let overviewTranslations = translations.reduce(into: [String: String]()) {
            result, translation in
            result[translation.languageCode + "-" + translation.countryCode] =
                translation.data.overview
        }
        logger.info(
            "Fetched \(nameTranslations.count) name translations and \(overviewTranslations.count) overview translations for season \(self.seasonNumber) of series \(parentSeriesID)"
        )
        return (name: nameTranslations, overview: overviewTranslations)
    }

    var onAirDate: Date? { airDate }
    var linkToDetails: URL? { nil }
}
