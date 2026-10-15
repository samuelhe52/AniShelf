//
//  PosterLanguagePreference.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/15.
//

import Foundation

/// Which language the default poster prefers when TMDb has several.
enum PosterLanguagePreference: String, CaseIterable, CustomLocalizedStringResourceConvertible {
    case originalLanguage
    case animeInfoLanguage

    /// Absent or unknown values keep the original-language behavior.
    static func stored(defaults: UserDefaults = .standard) -> PosterLanguagePreference {
        defaults.string(forKey: .defaultPosterLanguage).flatMap(Self.init(rawValue:))
            ?? .originalLanguage
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .originalLanguage: "Prefer Original Language"
        case .animeInfoLanguage: "Follow Anime Info Language"
        }
    }
}
