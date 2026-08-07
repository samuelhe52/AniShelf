//
//  InfoFetcher.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import DataProvider
import Foundation
import TMDb

private actor TMDbResourceCache {
    private var cachedImagesConfiguration: ImagesConfiguration?
    private var imagesConfigurationTask: Task<ImagesConfiguration, Error>?

    func imagesConfiguration(client: TMDbClient) async throws -> ImagesConfiguration {
        if let cachedImagesConfiguration {
            return cachedImagesConfiguration
        }
        if let imagesConfigurationTask {
            return try await imagesConfigurationTask.value
        }

        let task = Task { try await client.imagesConfiguration }
        imagesConfigurationTask = task
        do {
            let imagesConfiguration = try await task.value
            cachedImagesConfiguration = imagesConfiguration
            imagesConfigurationTask = nil
            return imagesConfiguration
        } catch {
            imagesConfigurationTask = nil
            throw error
        }
    }
}

/// A class for fetching media infos from TMDb.
/// - Important: Setup proper monitoring mechanism for the `.tmdbAPIKey` key change in `UserDefaults` as this class does not provide a built-in monitor-and-refresh feature.
final class InfoFetcher: Sendable {
    let tmdbClient: TMDbClient
    private let cache: TMDbResourceCache
    private let fetchTranslationResponseData: @Sendable (String) async throws -> Data

    convenience init(apiKey: String? = nil) {
        self.init(
            apiKey: apiKey,
            httpClient: RedirectingHTTPClient.relayAware
        )
    }

    init(
        apiKey: String? = nil,
        httpClient: some HTTPClient,
        configuration: TMDbConfiguration = .system
    ) {
        #if DEBUG
            // LOCAL DEBUG ONLY, NEVER COMMIT A KEY
            let debugKey: String? = nil  // Temporarily replace locally when needed.
            let key = apiKey ?? debugKey ?? TMDbAPIKeyStorage().key
        #else
            let key = apiKey ?? TMDbAPIKeyStorage().key
        #endif
        let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        tmdbClient = .init(
            apiKey: trimmedKey ?? "",
            httpClient: httpClient,
            configuration: configuration
        )
        fetchTranslationResponseData = Self.makeTranslationResponseDataFetcher(
            apiKey: trimmedKey,
            httpClient: httpClient
        )
        cache = .init()
    }

    init(
        client: TMDbClient,
        fetchTranslationResponseData: @escaping @Sendable (String) async throws -> Data
    ) {
        tmdbClient = client
        self.fetchTranslationResponseData = fetchTranslationResponseData
        cache = .init()
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
            language: language.rawValue
        )
    }

    func searchAll(name: String, language: Language) async throws -> [Media] {
        let results = try await tmdbClient.search.searchAll(
            query: name,
            page: 1,
            language: language.rawValue
        )
        return results.results.filter {
            switch $0 {
            case .movie(let movie):
                movie.genreIDs.contains(16)
            case .tvSeries(let series):
                series.genreIDs.contains(16)
            case .person(_), .collection(_):
                false
            }
        }
    }

    func searchMovies(name: String, language: Language) async throws -> [MovieListItem] {
        let results = try await tmdbClient.search.searchMovies(
            query: name,
            page: 1,
            language: language.rawValue
        )
        return results.results.filter { $0.genreIDs.contains(16) }
    }

    func searchTVSeries(name: String, language: Language) async throws -> [TVSeriesListItem] {
        let results = try await tmdbClient.search.searchTVSeries(
            query: name,
            page: 1,
            language: language.rawValue
        )
        return results.results.filter { $0.genreIDs.contains(16) }
    }

    func fetchInfoFromTMDB(entryType: AnimeType, tmdbID: Int, language: Language) async throws
        -> EntryMetadata
    {
        switch entryType {
        case .season(let seasonNumber, let parentSeriesID):
            return try await tvSeasonInfo(
                seasonNumber: seasonNumber,
                parentSeriesID: parentSeriesID,
                language: language
            )
        case .movie:
            return try await movieInfo(tmdbID: tmdbID, language: language)
        case .series:
            return try await tvSeriesInfo(tmdbID: tmdbID, language: language)
        }
    }

    func detailInfo(
        entryType: AnimeType,
        tmdbID: Int,
        language: Language
    ) async throws -> AnimeEntryDetailDTO {
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

    func latestInfo(entryType: AnimeType, tmdbID: Int, language: Language) async throws
        -> (EntryMetadata, AnimeEntryDetailDTO)
    {
        switch entryType {
        case .movie:
            return try await latestMovieInfo(tmdbID: tmdbID, language: language)
        case .series:
            return try await latestTVSeriesInfo(tmdbID: tmdbID, language: language)
        case .season(let seasonNumber, let parentSeriesID):
            return try await latestTVSeasonInfo(
                parentSeriesID: parentSeriesID,
                seasonNumber: seasonNumber,
                language: language
            )
        }
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

    func imagesConfiguration() async throws -> ImagesConfiguration {
        try await cache.imagesConfiguration(client: tmdbClient)
    }

    func makePosterURLs(
        from resources: [ImageMetadata],
        idealWidth: Int,
        imagesConfiguration: ImagesConfiguration
    ) -> [ImageURLWithMetadata] {
        resources.compactMap { resource in
            guard
                let url = imagesConfiguration.posterURL(
                    for: resource.filePath,
                    idealWidth: idealWidth
                )
            else {
                return nil
            }
            return .init(metadata: resource, url: url)
        }
    }

    func translationResponseData(path: String) async throws -> Data {
        try await fetchTranslationResponseData(path)
    }

    private static func makeTranslationResponseDataFetcher<HTTPClientType: HTTPClient>(
        apiKey: String?,
        httpClient: HTTPClientType
    ) -> @Sendable (String) async throws -> Data {
        { path in
            guard let apiKey else {
                throw URLError(.userAuthenticationRequired)
            }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.themoviedb.org"
            components.path = "/3\(path)"
            components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]

            guard let url = components.url else {
                throw URLError(.badURL)
            }

            let response = try await httpClient.perform(
                request: HTTPRequest(url: url)
            )

            guard
                (200..<300).contains(response.statusCode),
                let data = response.data
            else {
                throw URLError(.badServerResponse)
            }

            return data
        }
    }
}

extension InfoFetcher {
    static func productionCompanyDTOs(
        from companies: [ProductionCompany]?
    ) -> [AnimeEntryProductionCompanyDTO] {
        companies?.map {
            AnimeEntryProductionCompanyDTO(
                id: $0.id,
                name: $0.name,
                logoPath: TMDbImagePath.storagePath(from: $0.logoPath)
            )
        } ?? []
    }
}
