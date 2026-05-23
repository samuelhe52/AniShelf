//
//  InfoFetcher+Translations.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/12.
//

import Foundation
import TMDb

struct TranslationDictionaries {
    var name: [String: String] = [:]
    var overview: [String: String] = [:]
}

extension InfoFetcher {
    func movieTranslations(tmdbID: Int) async throws -> TranslationDictionaries {
        let translations = try await tmdbClient.movies.translations(forMovie: tmdbID)
        return translationDictionaries(from: translations)
    }

    func tvSeriesTranslations(tmdbID: Int) async throws -> TranslationDictionaries {
        let translations = try await tmdbClient.tvSeries.translations(forTVSeries: tmdbID)
        return translationDictionaries(from: translations)
    }

    func tvSeasonTranslations(parentSeriesID: Int, seasonNumber: Int) async throws
        -> TranslationDictionaries
    {
        let translations = try await tmdbClient.tvSeasons.translations(
            forSeason: seasonNumber,
            inTVSeries: parentSeriesID
        )
        return translationDictionaries(from: translations)
    }

    func translationDictionaries(
        from translations: TranslationCollection<MovieTranslationData>
    ) -> TranslationDictionaries {
        translationDictionaries(
            from: translations,
            name: { $0.title },
            overview: { $0.overview }
        )
    }

    func translationDictionaries(
        from translations: TranslationCollection<TVSeriesTranslationData>
    ) -> TranslationDictionaries {
        translationDictionaries(
            from: translations,
            name: { $0.name },
            overview: { $0.overview }
        )
    }

    func translationDictionaries(
        from translations: TranslationCollection<TVSeasonTranslationData>
    ) -> TranslationDictionaries {
        translationDictionaries(
            from: translations,
            name: { $0.name },
            overview: { $0.overview }
        )
    }

    func translationDictionaries<DataType>(
        from translations: TranslationCollection<DataType>,
        name: (DataType) -> String?,
        overview: (DataType) -> String?
    ) -> TranslationDictionaries where DataType: Codable & Equatable & Hashable & Sendable {
        translations.translations.reduce(into: TranslationDictionaries()) { result, translation in
            let key = "\(translation.languageCode)-\(translation.countryCode)"
            if let translatedName = name(translation.data) {
                result.name[key] = translatedName
            }
            if let translatedOverview = overview(translation.data) {
                result.overview[key] = translatedOverview
            }
        }
    }
}
