//
//  Language.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/12/18.
//

import Foundation

enum Language: String, CaseIterable, CustomLocalizedStringResourceConvertible {
    case english = "en"
    case chinese = "zh"
    case japanese = "ja"

    static var current: Language {
        guard let languageCodeID = Locale.current.language.languageCode?.identifier else {
            return .english
        }
        return Language(rawValue: languageCodeID) ?? .english
    }

    static func followsSystemPreference(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(
            forKey: .useCurrentLocaleForAnimeInfoLanguage,
            defaultValue: defaults.string(forKey: .preferredAnimeInfoLanguage) == nil
        )
    }

    static func resolvedAnimeInfoLanguage(defaults: UserDefaults = .standard) -> Language {
        followsSystemPreference(defaults: defaults)
            ? .current
            : (preferredAnimeInfoLanguage(defaults: defaults) ?? .english)
    }

    static func preferredAnimeInfoLanguage(defaults: UserDefaults = .standard) -> Language? {
        guard let rawValue = defaults.string(forKey: .preferredAnimeInfoLanguage) else {
            return nil
        }
        return Language(rawValue: rawValue)
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .japanese: return "Japanese"
        }
    }

    var rawValueWithRegion: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        }
    }

    static func fromRawValueWithRegion(_ rawValue: String) -> Language? {
        switch rawValue {
        case "zh-CN": return .chinese
        case "en-US": return .english
        case "ja-JP": return .japanese
        default: return nil
        }
    }
}
