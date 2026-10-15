//
//  TMDbImageSelection.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/12.
//

import Foundation
import TMDb

enum TMDbImageSelection {
    struct Resource: Equatable {
        let languageCode: String?
        let filePath: URL
    }

    private enum LanguageMatchRule: Equatable {
        case exact(String)
        case noLanguage
    }

    static func preferredPosterPath(
        from resources: [ImageMetadata],
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil,
        posterLanguage: PosterLanguagePreference = .originalLanguage
    ) -> URL? {
        preferredPosterPath(
            from: resources.map(Resource.init),
            originalLanguageCode: originalLanguageCode,
            metadataLanguageCode: metadataLanguageCode,
            posterLanguage: posterLanguage
        )
    }

    static func preferredBackdropPath(from resources: [ImageMetadata]) -> URL? {
        preferredBackdropPath(from: resources.map(Resource.init))
    }

    static func preferredLogoPath(
        from resources: [ImageMetadata],
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil
    ) -> URL? {
        preferredLogoPath(
            from: resources.map(Resource.init),
            originalLanguageCode: originalLanguageCode,
            metadataLanguageCode: metadataLanguageCode
        )
    }

    static func preferredPosterPath(
        from resources: [Resource],
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil,
        posterLanguage: PosterLanguagePreference = .originalLanguage
    ) -> URL? {
        preferredPath(
            from: resources,
            rules: posterMatchRules(
                originalLanguageCode: originalLanguageCode,
                metadataLanguageCode: metadataLanguageCode,
                posterLanguage: posterLanguage
            )
        )
    }

    static func preferredBackdropPath(from resources: [Resource]) -> URL? {
        resources.first(where: { isNoLanguageCode($0.languageCode) })?.filePath
            ?? resources.first?.filePath
    }

    static func preferredLogoPath(
        from resources: [Resource],
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil
    ) -> URL? {
        let supportedLogoResources =
            resources
            .enumerated()
            .compactMap { resource -> (Resource, Int)? in
                guard let priority = logoFormatPriority(for: resource.element.filePath) else { return nil }
                return (resource.element, priority * resources.count + resource.offset)
            }
            .sorted { lhs, rhs in
                lhs.1 < rhs.1
            }
            .map(\.0)
        return preferredPath(
            from: supportedLogoResources,
            rules: logoMatchRules(
                originalLanguageCode: originalLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
        )
    }

    private static func logoFormatPriority(for filePath: URL) -> Int? {
        switch filePath.pathExtension.lowercased() {
        case "png":
            return 0
        case "svg":
            return 1
        default:
            return nil
        }
    }

    static func isNoLanguageCode(_ languageCode: String?) -> Bool {
        let normalizedCode = normalizedLanguageCode(languageCode)
        return normalizedCode.isEmpty
            || ["null", "xx", "und", "zxx"].contains(normalizedCode)
    }

    static func posterLanguagePriority(
        for languageCode: String?,
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil,
        posterLanguage: PosterLanguagePreference = .originalLanguage
    ) -> Int? {
        for (index, rule) in posterMatchRules(
            originalLanguageCode: originalLanguageCode,
            metadataLanguageCode: metadataLanguageCode,
            posterLanguage: posterLanguage
        ).enumerated() where matches(languageCode: languageCode, rule: rule) {
            return index
        }
        return nil
    }

    private static func preferredPath(
        from resources: [Resource],
        rules: [LanguageMatchRule]
    ) -> URL? {
        for rule in rules {
            if let match = resources.first(where: { matches(languageCode: $0.languageCode, rule: rule) }) {
                return match.filePath
            }
        }
        return nil
    }

    private static func posterMatchRules(
        originalLanguageCode: String?,
        metadataLanguageCode: String?,
        posterLanguage: PosterLanguagePreference
    ) -> [LanguageMatchRule] {
        var rules: [LanguageMatchRule] = []

        func appendLanguage(_ code: String?) {
            let normalizedCode = normalizedLanguageCode(code)
            guard !normalizedCode.isEmpty else { return }
            let rule = LanguageMatchRule.exact(normalizedCode)
            guard !rules.contains(rule) else { return }
            rules.append(rule)
        }

        switch posterLanguage {
        case .originalLanguage:
            appendLanguage(originalLanguageCode)
            appendLanguage(metadataLanguageCode)
        case .animeInfoLanguage:
            appendLanguage(metadataLanguageCode)
            appendLanguage(originalLanguageCode)
        }
        rules.append(.noLanguage)
        return rules
    }

    private static func logoMatchRules(
        originalLanguageCode: String?,
        metadataLanguageCode: String?
    ) -> [LanguageMatchRule] {
        var rules = prioritizedRules(
            originalLanguageCode: originalLanguageCode,
            metadataLanguageCode: metadataLanguageCode,
            includeNoLanguageInMiddle: false
        )
        rules.append(.noLanguage)
        return rules
    }

    private static func prioritizedRules(
        originalLanguageCode: String?,
        metadataLanguageCode: String?,
        includeNoLanguageInMiddle: Bool
    ) -> [LanguageMatchRule] {
        var rules: [LanguageMatchRule] = []

        func appendLanguage(_ code: String?) {
            let normalizedCode = normalizedLanguageCode(code)
            guard !normalizedCode.isEmpty else { return }
            let rule = LanguageMatchRule.exact(normalizedCode)
            guard !rules.contains(rule) else { return }
            rules.append(rule)
        }

        appendLanguage(originalLanguageCode)
        if includeNoLanguageInMiddle {
            rules.append(.noLanguage)
        }
        appendLanguage(metadataLanguageCode)
        return rules
    }

    private static func matches(languageCode: String?, rule: LanguageMatchRule) -> Bool {
        switch rule {
        case .exact(let code):
            return normalizedLanguageCode(languageCode) == code
        case .noLanguage:
            return isNoLanguageCode(languageCode)
        }
    }

    private static func normalizedLanguageCode(_ languageCode: String?) -> String {
        (languageCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

extension TMDbImageSelection.Resource {
    init(_ metadata: ImageMetadata) {
        self.init(languageCode: metadata.languageCode, filePath: metadata.filePath)
    }
}
