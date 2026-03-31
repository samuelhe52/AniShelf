//
//  InfoFetcher.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import Combine
import DataProvider
import Foundation
import SwiftUI
import TMDb

/// A class for fetching media infos from TMDb.
/// - Important: Setup proper monitoring mechanism for the `.tmdbAPIKey` key change in `UserDefaults` as this class does not provide a built-in monitor-and-refresh feature.
final class InfoFetcher: Sendable {
    let tmdbClient: TMDbClient

    init(apiKey: String? = nil) {
        let key = apiKey ?? TMDbAPIKeyStorage().key
        self.tmdbClient = .init(
            apiKey: key ?? "",
            httpClient: RedirectingHTTPClient.relayServer)
    }

    init(client: TMDbClient) {
        self.tmdbClient = client
    }

    func movie(_ tmdbID: Int, language: Language) async throws -> Movie {
        try await tmdbClient.movies.details(forMovie: tmdbID, language: language.rawValue)
    }

    func tvSeries(_ tmdbID: Int, language: Language) async throws -> TVSeries {
        try await tmdbClient.tvSeries.details(forTVSeries: tmdbID, language: language.rawValue)
    }

    func tvSeason(_ parentSeriesID: Int, seasonNumber: Int, language: Language) async throws
        -> TVSeason
    {
        try await tmdbClient.tvSeasons.details(
            forSeason: seasonNumber,
            inTVSeries: parentSeriesID,
            language: language.rawValue)
    }

    func searchAll(name: String, language: Language) async throws -> [Media] {
        let results = try await tmdbClient.search.searchAll(
            query: name, page: 1, language: language.rawValue)
        return results.results.filter {
            switch $0 {
            // 16 is the genre id for animation
            case .movie(let movie): movie.genreIDs.contains(16)
            case .tvSeries(let series): series.genreIDs.contains(16)
            case .person(_): false
            case .collection(_): false
            }
        }
    }

    func searchMovies(name: String, language: Language) async throws -> [MovieListItem] {
        let results = try await tmdbClient.search.searchMovies(
            query: name, page: 1, language: language.rawValue)
        // 16 is the genre id for animation
        return results.results.filter { $0.genreIDs.contains(16) }
    }

    func searchTVSeries(name: String, language: Language) async throws -> [TVSeriesListItem] {
        let results = try await tmdbClient.search.searchTVSeries(
            query: name, page: 1, language: language.rawValue)
        // 16 is the genre id for animation
        return results.results.filter { $0.genreIDs.contains(16) }
    }

    func fetchInfoFromTMDB(entryType: AnimeType, tmdbID: Int, language: Language) async throws
        -> BasicInfo
    {
        switch entryType {
        case .season(let seasonNumber, let parentSeriesID):
            return try await tvSeasonInfo(
                seasonNumber: seasonNumber, parentSeriesID: parentSeriesID, language: language)
        case .movie:
            return try await movieInfo(tmdbID: tmdbID, language: language)
        case .series:
            return try await tvSeriesInfo(tmdbID: tmdbID, language: language)
        }
    }

    func tvSeasonInfo(seasonNumber: Int, parentSeriesID: Int, language: Language) async throws
        -> BasicInfo
    {
        let season = try await tmdbClient.tvSeasons.details(
            forSeason: seasonNumber,
            inTVSeries: parentSeriesID,
            language: language.rawValue)
        let parentSeries = try await tmdbClient.tvSeries.details(
            forTVSeries: parentSeriesID,
            language: language.rawValue)
        let backdropURL = try await parentSeries.backdropURL(client: tmdbClient)
        let logoURL = try await parentSeries.logoURL(client: tmdbClient)
        let linkToDetails = parentSeries.linkToDetails

        // Use the parent series' shared brand assets for the season.
        let basicInfo = try await season.basicInfo(
            client: tmdbClient,
            backdropURL: backdropURL,
            logoURL: logoURL,
            linkToDetails: linkToDetails,
            parentSeriesID: parentSeriesID)
        return basicInfo
    }

    func movieInfo(tmdbID: Int, language: Language) async throws -> BasicInfo {
        let movie = try await tmdbClient.movies.details(
            forMovie: tmdbID, language: language.rawValue)
        return try await movie.basicInfo(client: tmdbClient)
    }

    func tvSeriesInfo(tmdbID: Int, language: Language) async throws -> BasicInfo {
        let series = try await tmdbClient.tvSeries.details(
            forTVSeries: tmdbID, language: language.rawValue)
        return try await series.basicInfo(client: tmdbClient)
    }

    func postersForMovie(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.posterURLs(forMovie: tmdbID, idealWidth: idealWidth)
    }

    func backdropsForMovie(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.backdropURLs(forMovie: tmdbID, idealWidth: idealWidth)
    }

    func logosForMovie(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.logoURLs(forMovie: tmdbID, idealWidth: idealWidth)
    }

    func postersForSeries(seriesID tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.posterURLs(forTVSeries: tmdbID, idealWidth: idealWidth)
    }

    func backdropsForSeries(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.backdropURLs(forTVSeries: tmdbID, idealWidth: idealWidth)
    }

    func logosForSeries(for tmdbID: Int, idealWidth: Int = .max) async throws
        -> [ImageURLWithMetadata]
    {
        try await tmdbClient.logoURLs(forTVSeries: tmdbID, idealWidth: idealWidth)
    }

    func postersForSeason(
        forSeason seasonNumber: Int,
        inParentSeries parentSeriesID: Int,
        idealWidth: Int = .max
    ) async throws -> [ImageURLWithMetadata] {
        try await tmdbClient.posterURLs(
            forSeason: seasonNumber, inTVSeries: parentSeriesID, idealWidth: idealWidth)
    }

    /// Fetches BasicInfo for all seasons of a TV series.
    func seasonInfos(
        forSeriesID tmdbID: Int,
        language: Language
    ) async throws -> [BasicInfo] {
        let series = try await tvSeries(tmdbID, language: language)
        guard let seasons = series.seasons else { return [] }
        let backdropURL = try await series.backdropURL(client: tmdbClient)
        let logoURL = try await series.logoURL(client: tmdbClient)
        let linkToDetails = series.linkToDetails

        return try await withThrowingTaskGroup(of: BasicInfo.self) { group in
            var results: [BasicInfo] = []
            for season in seasons {
                group.addTask {
                    try await season.basicInfo(
                        client: self.tmdbClient,
                        backdropURL: backdropURL,
                        logoURL: logoURL,
                        linkToDetails: linkToDetails,
                        parentSeriesID: tmdbID)
                }
            }
            for try await info in group {
                results.append(info)
            }
            return results.sorted { ($0.type.seasonNumber ?? 0) < ($1.type.seasonNumber ?? 0) }
        }
    }

    func detailInfo(entryType: AnimeType, tmdbID: Int, language: Language) async throws -> AnimeEntryDetail {
        switch entryType {
        case .movie:
            return try await movieDetail(tmdbID: tmdbID, language: language)
        case .series:
            return try await tvSeriesDetail(tmdbID: tmdbID, language: language)
        case .season(let seasonNumber, let parentSeriesID):
            return try await tvSeasonDetail(
                seasonNumber: seasonNumber,
                parentSeriesID: parentSeriesID,
                language: language
            )
        }
    }

    func seasonEpisodeSummaries(
        parentSeriesID: Int,
        seasonNumber: Int,
        language: Language
    ) async throws -> [AnimeEntryEpisodeSummary] {
        let season = try await tvSeason(parentSeriesID, seasonNumber: seasonNumber, language: language)
        let imagesConfiguration = try await tmdbClient.imagesConfiguration
        return makeEpisodeSummaries(
            from: season.episodes ?? [],
            imagesConfiguration: imagesConfiguration
        )
    }

    func episodePreviewInfo(
        parentSeriesID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        language: Language
    ) async throws -> TVEpisode {
        try await tmdbClient.tvEpisodes.details(
            forEpisode: episodeNumber,
            inSeason: seasonNumber,
            inTVSeries: parentSeriesID,
            language: language.rawValue
        )
    }

    private func movieDetail(tmdbID: Int, language: Language) async throws -> AnimeEntryDetail {
        let movie = try await movie(tmdbID, language: language)
        let heroImageURL = try await movie.backdropURL(client: tmdbClient, idealWidth: 1_280)
        let logoImageURL = try await movie.logoURL(client: tmdbClient, idealWidth: 500)
        let credits = try await tmdbClient.movies.credits(forMovie: movie.id, language: language.rawValue)
        let imagesConfiguration = try await tmdbClient.imagesConfiguration

        return AnimeEntryDetail(
            language: language.rawValue,
            title: movie.title,
            subtitle: movie.tagline?.nilIfEmpty,
            overview: movie.overview?.nilIfEmpty,
            status: movie.status?.rawValue,
            airDate: movie.releaseDate,
            primaryLinkURL: movie.homepageURL,
            heroImageURL: heroImageURL,
            logoImageURL: logoImageURL,
            genreIDs: movie.genres?.map(\.id) ?? [],
            voteAverage: movie.voteAverage,
            runtimeMinutes: movie.runtime,
            characters: credits.cast.prefix(12).map {
                AnimeEntryCharacter(
                    id: $0.id,
                    characterName: $0.character.strippingVoiceQualifier.nilIfEmpty ?? "Character",
                    actorName: Self.preferredActorName(
                        localizedName: $0.name,
                        originalName: nil,
                        language: language
                    ),
                    profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
                )
            }
        )
    }

    private func tvSeriesDetail(tmdbID: Int, language: Language) async throws -> AnimeEntryDetail {
        let series = try await tvSeries(tmdbID, language: language)
        let heroImageURL = try await series.backdropURL(client: tmdbClient, idealWidth: 1_280)
        let logoImageURL = try await series.logoURL(client: tmdbClient, idealWidth: 500)
        let credits = try await tmdbClient.tvSeries.aggregateCredits(
            forTVSeries: series.id,
            language: language.rawValue
        )
        let imagesConfiguration = try await tmdbClient.imagesConfiguration

        return AnimeEntryDetail(
            language: language.rawValue,
            title: series.name,
            subtitle: series.tagline?.nilIfEmpty,
            overview: series.overview?.nilIfEmpty,
            status: series.status,
            airDate: series.firstAirDate,
            primaryLinkURL: series.homepageURL,
            heroImageURL: heroImageURL,
            logoImageURL: logoImageURL,
            genreIDs: series.genres?.map(\.id) ?? [],
            voteAverage: series.voteAverage,
            runtimeMinutes: series.episodeRunTime?.first,
            episodeCount: series.numberOfEpisodes,
            seasonCount: series.numberOfSeasons,
            characters: makeCharacters(
                from: credits.cast.prefix(12),
                imagesConfiguration: imagesConfiguration,
                language: language
            ),
            seasons: makeSeasonSummaries(
                from: series.seasons ?? [],
                imagesConfiguration: imagesConfiguration
            )
        )
    }

    private func tvSeasonDetail(
        seasonNumber: Int,
        parentSeriesID: Int,
        language: Language
    ) async throws -> AnimeEntryDetail {
        async let parentSeries = tvSeries(parentSeriesID, language: language)
        async let season = tvSeason(parentSeriesID, seasonNumber: seasonNumber, language: language)

        let resolvedParentSeries = try await parentSeries
        let resolvedSeason = try await season
        let heroImageURL = try await resolvedParentSeries.backdropURL(client: tmdbClient, idealWidth: 1_280)
        let logoImageURL = try await resolvedParentSeries.logoURL(client: tmdbClient, idealWidth: 500)
        let credits = try await tmdbClient.tvSeasons.aggregateCredits(
            forSeason: resolvedSeason.seasonNumber,
            inTVSeries: resolvedParentSeries.id,
            language: language.rawValue
        )
        let imagesConfiguration = try await tmdbClient.imagesConfiguration

        return AnimeEntryDetail(
            language: language.rawValue,
            title: resolvedParentSeries.name,
            subtitle: resolvedSeason.name,
            overview: resolvedSeason.overview?.nilIfEmpty,
            status: resolvedParentSeries.status,
            airDate: resolvedSeason.airDate,
            primaryLinkURL: resolvedParentSeries.homepageURL,
            heroImageURL: heroImageURL,
            logoImageURL: logoImageURL,
            genreIDs: resolvedParentSeries.genres?.map(\.id) ?? [],
            voteAverage: resolvedParentSeries.voteAverage,
            runtimeMinutes: resolvedParentSeries.episodeRunTime?.first,
            episodeCount: resolvedSeason.episodes?.count,
            characters: makeCharacters(
                from: credits.cast.prefix(12),
                imagesConfiguration: imagesConfiguration,
                language: language
            ),
            episodes: makeEpisodeSummaries(
                from: Array((resolvedSeason.episodes ?? []).prefix(8)),
                imagesConfiguration: imagesConfiguration
            )
        )
    }

    private func makeCharacters<S: Sequence>(
        from cast: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryCharacter] where S.Element == CastMember {
        cast.map {
            AnimeEntryCharacter(
                id: $0.id,
                characterName: $0.character.strippingVoiceQualifier.nilIfEmpty ?? "Character",
                actorName: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: nil,
                    language: language
                ),
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    private func makeCharacters<S: Sequence>(
        from cast: S,
        imagesConfiguration: ImagesConfiguration,
        language: Language
    ) -> [AnimeEntryCharacter] where S.Element == AggregrateCastMember {
        cast.map {
            let primaryRole = $0.roles.max { lhs, rhs in
                lhs.episodeCount < rhs.episodeCount
            }?.character
                .strippingVoiceQualifier
                .nilIfEmpty

            return AnimeEntryCharacter(
                id: $0.id,
                characterName: primaryRole ?? "Character",
                actorName: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: $0.originalName,
                    language: language
                ),
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    private func makeSeasonSummaries(
        from seasons: [TVSeason],
        imagesConfiguration: ImagesConfiguration
    ) -> [AnimeEntrySeasonSummary] {
        seasons
            .filter { $0.seasonNumber > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .map {
                AnimeEntrySeasonSummary(
                    id: $0.id,
                    seasonNumber: $0.seasonNumber,
                    title: $0.name,
                    posterURL: imagesConfiguration.posterURL(for: $0.posterPath, idealWidth: 300)
                )
            }
    }

    private func makeEpisodeSummaries(
        from episodes: [TVEpisode],
        imagesConfiguration: ImagesConfiguration
    ) -> [AnimeEntryEpisodeSummary] {
        episodes.map {
            AnimeEntryEpisodeSummary(
                id: $0.id,
                episodeNumber: $0.episodeNumber,
                title: $0.name,
                airDate: $0.airDate,
                imageURL: imagesConfiguration.stillURL(for: $0.stillPath, idealWidth: 500)
            )
        }
    }

    private static func preferredActorName(localizedName: String, originalName: String?, language: Language)
        -> String
    {
        guard language == .japanese,
            let originalName,
            originalName != localizedName,
            originalName.containsJapaneseScript
        else {
            return localizedName
        }
        return originalName
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var strippingVoiceQualifier: String {
        let voiceMarkerPattern = #"(?i:voice|voiced\s+by|cv|c\.?\s*v\.?)|声優|声の出演|声|吹替え|吹替|吹き替え|ボイス"#
        let patterns = [
            #"\s*[\(\（][^)\）]*(?:__VOICE_MARKERS__)[^)\）]*[\)\）]\s*$"#,
            #"\s*[\[\［][^\]\］]*(?:__VOICE_MARKERS__)[^\]\］]*[\]\］]\s*$"#,
        ].map {
            $0.replacingOccurrences(of: "__VOICE_MARKERS__", with: voiceMarkerPattern)
        }

        var value = self
        while true {
            let stripped = patterns.reduce(value) { partialResult, pattern in
                partialResult.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard stripped != value else {
                return stripped
            }
            value = stripped
        }
    }

    var containsJapaneseScript: Bool {
        unicodeScalars.contains {
            switch $0.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }
    }
}

extension RedirectingHTTPClient {
    static let relayServer: Self = .init(
        fromHost: "api.themoviedb.org", toHost: "tmdb-api.konakona52.com")
}
