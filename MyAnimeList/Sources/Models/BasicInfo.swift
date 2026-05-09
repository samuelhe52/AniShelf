//
//  BasicInfo.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import DataProvider
import Foundation

/// A structure representing basic information about an anime.
///
/// The `id` is derived from the `tmdbID` property.
struct BasicInfo: Equatable, Identifiable, Hashable, Sendable {
    var name: String
    var nameTranslations: [String: String]
    var overview: String?
    var overviewTranslations: [String: String]
    var posterURL: URL?
    var backdropURL: URL?
    var logoURL: URL?
    /// The TMDb (The Movie Database) identifier.
    var tmdbID: Int
    var onAirDate: Date?
    /// Home page URL of the anime.
    var linkToDetails: URL?

    /// The type of anime (movie, TV series, season, etc.).
    var type: AnimeType

    var id: Int { tmdbID }
}
