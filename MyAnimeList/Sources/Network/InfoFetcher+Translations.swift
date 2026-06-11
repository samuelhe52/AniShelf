//
//  InfoFetcher+Translations.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/12.
//

import Foundation
import TMDb

struct TranslationDictionaries {
    var name: [String: String] = [:]
    var overview: [String: String] = [:]
}

fileprivate struct LenientTranslationCollection<DataType: Decodable>: Decodable {
    let id: Int
    let translations: [LenientTranslation<DataType>]
}

fileprivate struct LenientTranslation<DataType: Decodable>: Decodable {
    let countryCode: String
    let languageCode: String
    let data: DataType

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case languageCode = "iso_639_1"
        case data
    }
}

fileprivate struct LenientMovieTranslationData: Decodable {
    let title: String?
    let overview: String?
}

fileprivate struct LenientTVSeriesTranslationData: Decodable {
    let name: String?
    let overview: String?
}

fileprivate struct LenientTVSeasonTranslationData: Decodable {
    let name: String?
    let overview: String?
}

extension InfoFetcher {
    func movieTranslations(tmdbID: Int) async throws -> TranslationDictionaries {
        do {
            let translations = try await tmdbClient.movies.translations(forMovie: tmdbID)
            return translationDictionaries(from: translations)
        } catch let error as TMDbError {
            return try await fallbackTranslationDictionaries(
                after: error,
                path: "/movie/\(tmdbID)/translations",
                dataType: LenientMovieTranslationData.self,
                name: \.title,
                overview: \.overview
            )
        }
    }

    func tvSeriesTranslations(tmdbID: Int) async throws -> TranslationDictionaries {
        do {
            let translations = try await tmdbClient.tvSeries.translations(forTVSeries: tmdbID)
            return translationDictionaries(from: translations)
        } catch let error as TMDbError {
            return try await fallbackTranslationDictionaries(
                after: error,
                path: "/tv/\(tmdbID)/translations",
                dataType: LenientTVSeriesTranslationData.self,
                name: \.name,
                overview: \.overview
            )
        }
    }

    func tvSeasonTranslations(parentSeriesID: Int, seasonNumber: Int) async throws
        -> TranslationDictionaries
    {
        do {
            let translations = try await tmdbClient.tvSeasons.translations(
                forSeason: seasonNumber,
                inTVSeries: parentSeriesID
            )
            return translationDictionaries(from: translations)
        } catch let error as TMDbError {
            return try await fallbackTranslationDictionaries(
                after: error,
                path: "/tv/\(parentSeriesID)/season/\(seasonNumber)/translations",
                dataType: LenientTVSeasonTranslationData.self,
                name: \.name,
                overview: \.overview
            )
        }
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

    func decodeLenientTranslationDictionaries<DataType: Decodable>(
        from data: Data,
        dataType _: DataType.Type,
        name: (DataType) -> String?,
        overview: (DataType) -> String?
    ) throws -> TranslationDictionaries {
        let collection = try JSONDecoder().decode(LenientTranslationCollection<DataType>.self, from: data)
        return collection.translations.reduce(into: TranslationDictionaries()) { result, translation in
            let key = "\(translation.languageCode)-\(translation.countryCode)"
            if let translatedName = name(translation.data) {
                result.name[key] = translatedName
            }
            if let translatedOverview = overview(translation.data) {
                result.overview[key] = translatedOverview
            }
        }
    }

    private func fallbackTranslationDictionaries<DataType: Decodable>(
        after error: TMDbError,
        path: String,
        dataType: DataType.Type,
        name: (DataType) -> String?,
        overview: (DataType) -> String?
    ) async throws -> TranslationDictionaries {
        guard case .decode = error else {
            throw error
        }

        do {
            // TMDb occasionally returns null for translation title/overview fields
            // (for example `tv/35610` in `zh-TW`), but the upstream package models
            // those values as non-optional strings. Re-decode this endpoint
            // permissively so one sparse translation does not block entry creation.
            let data = try await translationResponseData(path: path)
            return try decodeLenientTranslationDictionaries(
                from: data,
                dataType: dataType,
                name: name,
                overview: overview
            )
        } catch {
            throw error
        }
    }
}
