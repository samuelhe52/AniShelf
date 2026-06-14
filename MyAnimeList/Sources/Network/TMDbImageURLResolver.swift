//
//  TMDbImageURLResolver.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import DataProvider
import Foundation
import TMDb

enum TMDbImageRole {
    case poster
    case backdrop
    case logo
    case profile
    case still
}

struct TMDbImageURLResolver {
    static let backdropIdealWidth = 1_280

    var imagesConfiguration: ImagesConfiguration

    /// Shared resolver for persisted TMDb image paths.
    ///
    /// Persisted library data stores TMDb `file_path` values, not concrete rendition URLs. This
    /// resolver intentionally uses AniShelf's static TMDb image configuration fallback so model and
    /// view code can synchronously derive display URLs without coupling persistence reads to a live
    /// `/configuration` request. Metadata fetch flows may still use TMDb's live image configuration
    /// while selecting and returning paths.
    static let current = TMDbImageURLResolver(imagesConfiguration: .tmdbStandardFallback)

    func url(for path: String?, role: TMDbImageRole, idealWidth: Int = .max) -> URL? {
        let pathURL = TMDbImagePath.urlPath(from: path)
        switch role {
        case .poster:
            return imagesConfiguration.posterURL(for: pathURL, idealWidth: idealWidth)
        case .backdrop:
            return imagesConfiguration.backdropURL(for: pathURL, idealWidth: idealWidth)
        case .logo:
            return imagesConfiguration.logoURL(for: pathURL, idealWidth: idealWidth)
        case .profile:
            return imagesConfiguration.profileURL(for: pathURL, idealWidth: idealWidth)
        case .still:
            return imagesConfiguration.stillURL(for: pathURL, idealWidth: idealWidth)
        }
    }
}

extension ImagesConfiguration {
    /// Static app-level fallback for resolving persisted TMDb `file_path` values.
    ///
    /// The TMDb Swift package does not expose a runtime default `ImagesConfiguration`. These values
    /// mirror TMDb's standard image configuration as represented by the pinned package's API fixture,
    /// and they should be updated intentionally if TMDb changes its public image size catalog.
    static let tmdbStandardFallback = ImagesConfiguration(
        baseURL: URL(string: "http://image.tmdb.org/t/p/")!,
        secureBaseURL: URL(string: "https://image.tmdb.org/t/p/")!,
        backdropSizes: ["w300", "w780", "w1280", "original"],
        logoSizes: ["w45", "w92", "w154", "w185", "w300", "w500", "original"],
        posterSizes: ["w92", "w154", "w185", "w342", "w500", "w780", "original"],
        profileSizes: ["w45", "w185", "h632", "original"],
        stillSizes: ["w92", "w185", "w300", "original"]
    )
}

extension AnimeEntry {
    /// Resolves the poster URL through `selectedPosterPath`, so callers automatically use
    /// `customPosterPath` when `usingCustomPoster` is true and `posterPath` otherwise.
    var posterURL: URL? {
        TMDbImageURLResolver.current.url(for: selectedPosterPath, role: .poster)
    }

    var backdropURL: URL? {
        TMDbImageURLResolver.current.url(
            for: backdropPath,
            role: .backdrop,
            idealWidth: TMDbImageURLResolver.backdropIdealWidth
        )
    }
}

extension AnimeEntryDetail {
    var heroImageURL: URL? {
        entry?.backdropURL
    }

    var logoImageURL: URL? {
        TMDbImageURLResolver.current.url(for: logoImagePath, role: .logo, idealWidth: 500)
    }
}

extension AnimeEntryCharacter {
    var profileURL: URL? {
        TMDbImageURLResolver.current.url(for: profilePath, role: .profile, idealWidth: 185)
    }
}

extension AnimeEntryStaff {
    var profileURL: URL? {
        TMDbImageURLResolver.current.url(for: profilePath, role: .profile, idealWidth: 185)
    }
}

extension AnimeEntrySeasonSummary {
    var posterURL: URL? {
        TMDbImageURLResolver.current.url(for: posterPath, role: .poster, idealWidth: 300)
    }
}

extension AnimeEntryEpisodeSummary {
    var imageURL: URL? {
        TMDbImageURLResolver.current.url(for: imagePath, role: .still, idealWidth: 500)
    }
}
