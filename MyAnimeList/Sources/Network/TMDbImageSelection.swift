//
//  TMDbImageSelection.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/12.
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
        metadataLanguageCode: String? = nil
    ) -> URL? {
        preferredPosterPath(
            from: resources.map(Resource.init),
            originalLanguageCode: originalLanguageCode,
            metadataLanguageCode: metadataLanguageCode
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
        metadataLanguageCode: String? = nil
    ) -> URL? {
        preferredPath(
            from: resources,
            rules: posterMatchRules(
                originalLanguageCode: originalLanguageCode,
                metadataLanguageCode: metadataLanguageCode
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
        let pngResources = resources.filter {
            $0.filePath.pathExtension.caseInsensitiveCompare("png") == .orderedSame
        }
        return preferredPath(
            from: pngResources,
            rules: logoMatchRules(
                originalLanguageCode: originalLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
        )
    }

    static func isNoLanguageCode(_ languageCode: String?) -> Bool {
        let normalizedCode = normalizedLanguageCode(languageCode)
        return normalizedCode.isEmpty
            || ["null", "xx", "und", "zxx"].contains(normalizedCode)
    }

    static func posterLanguagePriority(
        for languageCode: String?,
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil
    ) -> Int? {
        for (index, rule) in posterMatchRules(
            originalLanguageCode: originalLanguageCode,
            metadataLanguageCode: metadataLanguageCode
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
        metadataLanguageCode: String?
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
        appendLanguage(metadataLanguageCode)
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
