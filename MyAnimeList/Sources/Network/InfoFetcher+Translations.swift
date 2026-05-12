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
        let translations = try await tmdbClient.movies.translations(forMovie: tmdbID).translations
        return translationDictionaries(from: translations)
    }

    func tvSeriesTranslations(tmdbID: Int) async throws -> TranslationDictionaries {
        let translations = try await tmdbClient.tvSeries.translations(forTVSeries: tmdbID).translations
        return translationDictionaries(from: translations)
    }

    func tvSeasonTranslations(parentSeriesID: Int, seasonNumber: Int) async throws
        -> TranslationDictionaries
    {
        let translations = try await tmdbClient.tvSeasons.translations(
            forSeason: seasonNumber,
            inTVSeries: parentSeriesID
        ).translations
        return translationDictionaries(from: translations)
    }

    func translationDictionaries(from translations: [Translations]) -> TranslationDictionaries {
        translations.reduce(into: TranslationDictionaries()) { result, translation in
            result.name[translation.languageCode + "-" + translation.countryCode] = translation.data.name
            result.overview[translation.languageCode + "-" + translation.countryCode] =
                translation.data.overview
        }
    }
}
