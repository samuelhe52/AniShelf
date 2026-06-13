//
//  EntryMetadata.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import DataProvider
import Foundation

/// A structure representing persisted entry metadata for an anime.
///
/// The `id` is derived from the `tmdbID` property.
struct EntryMetadata: Equatable, Identifiable, Hashable, Sendable {
    var name: String
    var nameTranslations: [String: String]
    var overview: String?
    var overviewTranslations: [String: String]
    var posterPath: String?
    var backdropPath: String?
    var logoPath: String?
    var originalLanguageCode: String? = nil
    /// The TMDb (The Movie Database) identifier.
    var tmdbID: Int
    var onAirDate: Date?
    /// Home page URL of the anime.
    var linkToDetails: URL?

    /// The type of anime (movie, TV series, season, etc.).
    var type: AnimeType

    var id: Int { tmdbID }

    var posterURL: URL? {
        TMDbImageURLResolver.current.url(for: posterPath, role: .poster)
    }

    var backdropURL: URL? {
        TMDbImageURLResolver.current.url(for: backdropPath, role: .backdrop)
    }

    var logoURL: URL? {
        TMDbImageURLResolver.current.url(for: logoPath, role: .logo, idealWidth: 500)
    }

    init(
        name: String,
        nameTranslations: [String: String],
        overview: String? = nil,
        overviewTranslations: [String: String],
        posterPath: String? = nil,
        backdropPath: String? = nil,
        logoPath: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        originalLanguageCode: String? = nil,
        tmdbID: Int,
        onAirDate: Date? = nil,
        linkToDetails: URL? = nil,
        type: AnimeType
    ) {
        self.name = name
        self.nameTranslations = nameTranslations
        self.overview = overview
        self.overviewTranslations = overviewTranslations
        self.posterPath =
            TMDbImagePath.storagePath(from: posterPath, fallback: posterURL)
        self.backdropPath =
            TMDbImagePath.storagePath(from: backdropPath, fallback: backdropURL)
        self.logoPath =
            TMDbImagePath.storagePath(from: logoPath, fallback: logoURL)
        self.originalLanguageCode = originalLanguageCode
        self.tmdbID = tmdbID
        self.onAirDate = onAirDate
        self.linkToDetails = linkToDetails
        self.type = type
    }
}
