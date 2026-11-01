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
    var imagesConfiguration: ImagesConfiguration

    /// Shared resolver for persisted TMDb image paths.
    ///
    /// Persisted library data stores TMDb `file_path` values, not concrete rendition URLs. This
    /// resolver intentionally uses AniShelf's static TMDb image configuration fallback so model and
    /// view code can synchronously derive display URLs without coupling persistence reads to a live
    /// `/configuration` request. Metadata fetch flows may still use TMDb's live image configuration
    /// while selecting and returning paths.
    ///
    /// Future improvement: replace this compile-time fallback with a persisted last-known-good TMDb
    /// `/configuration` snapshot that is refreshed opportunistically from live fetches. That would
    /// keep these synchronous call sites while reducing the risk of stale base URLs or size catalogs
    /// if TMDb changes its image configuration again.
    static let current = TMDbImageURLResolver(imagesConfiguration: .tmdbStandardFallback)

    /// The URL of the original-size rendition, for export and other uses that need full resolution.
    ///
    /// Display code takes a `TMDbImage` instead, so its URL matches the cached variant.
    func originalURL(for path: String?, role: TMDbImageRole) -> URL? {
        url(for: path, role: role, size: .original)
    }

    func url(for path: String?, variant: TMDbImageVariant) -> URL? {
        let pathURL = TMDbImagePath.urlPath(from: path)
        // SVG logos are only served at their original size.
        let size: ImageSize = pathURL?.isSVGImageURL == true ? .original : variant.rendition
        return url(for: path, role: variant.role, size: size)
    }

    private func url(for path: String?, role: TMDbImageRole, size: ImageSize) -> URL? {
        let pathURL = TMDbImagePath.urlPath(from: path)
        switch role {
        case .poster:
            return imagesConfiguration.posterURL(for: pathURL, size: size)
        case .backdrop:
            return imagesConfiguration.backdropURL(for: pathURL, size: size)
        case .logo:
            return imagesConfiguration.logoURL(for: pathURL, size: size)
        case .profile:
            return imagesConfiguration.profileURL(for: pathURL, size: size)
        case .still:
            return imagesConfiguration.stillURL(for: pathURL, size: size)
        }
    }
}

extension ImagesConfiguration {
    /// Static app-level fallback for resolving persisted TMDb `file_path` values.
    ///
    /// The TMDb Swift package does not expose a runtime default `ImagesConfiguration`. These values
    /// mirror TMDb's standard image configuration as represented by the pinned package's API fixture,
    /// and they should be updated intentionally if TMDb changes its public image size catalog.
    ///
    /// Future improvement: use this only as a cold-start bootstrap default, then prefer a persisted
    /// last-known-good live `/configuration` snapshot for subsequent synchronous image resolution.
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
    /// The original-size poster through `selectedPosterPath`, so it follows `customPosterPath`
    /// when `usingCustomPoster` is true and `posterPath` otherwise.
    var posterURL: URL? {
        TMDbImageURLResolver.current.originalURL(for: selectedPosterPath, role: .poster)
    }

    /// The selected poster at a display variant.
    func posterImage(_ variant: TMDbImageVariant) -> TMDbImage? {
        TMDbImage(path: selectedPosterPath, variant: variant)
    }

    var backdropImage: TMDbImage? {
        TMDbImage(path: backdropPath, variant: .backdrop)
    }
}

extension AnimeEntryDetail {
    var logoImage: TMDbImage? {
        TMDbImage(path: logoImagePath, variant: .logo)
    }
}

extension AnimeEntryProductionCompany {
    var logoImage: TMDbImage? {
        TMDbImage(path: logoPath, variant: .logo)
    }
}

extension AnimeEntryCharacter {
    var profileImage: TMDbImage? {
        TMDbImage(path: profilePath, variant: .profile)
    }
}

extension AnimeEntryStaff {
    var profileImage: TMDbImage? {
        TMDbImage(path: profilePath, variant: .profile)
    }
}

extension AnimeEntrySeasonSummary {
    var posterImage: TMDbImage? {
        TMDbImage(path: posterPath, variant: .posterThumbnail)
    }
}

extension AnimeEntryEpisodeSummary {
    var stillImage: TMDbImage? {
        TMDbImage(path: imagePath, variant: .still)
    }
}

extension AnimeEntryDetailDTO {
    var resolvedLogoImage: TMDbImage? {
        TMDbImage(path: logoImagePath, variant: .logo)
            ?? TMDbImage(fallbackURL: logoImageURL, variant: .logo)
    }
}

extension AnimeEntryCharacterDTO {
    var resolvedProfileImage: TMDbImage? {
        TMDbImage(path: profilePath, variant: .profile)
            ?? TMDbImage(fallbackURL: profileURL, variant: .profile)
    }
}

extension AnimeEntryStaffDTO {
    var resolvedProfileImage: TMDbImage? {
        TMDbImage(path: profilePath, variant: .profile)
            ?? TMDbImage(fallbackURL: profileURL, variant: .profile)
    }
}

extension AnimeEntrySeasonSummaryDTO {
    var resolvedPosterImage: TMDbImage? {
        TMDbImage(path: posterPath, variant: .posterThumbnail)
            ?? TMDbImage(fallbackURL: posterURL, variant: .posterThumbnail)
    }
}

extension AnimeEntryEpisodeSummaryDTO {
    var resolvedStillImage: TMDbImage? {
        TMDbImage(path: imagePath, variant: .still)
            ?? TMDbImage(fallbackURL: imageURL, variant: .still)
    }
}
