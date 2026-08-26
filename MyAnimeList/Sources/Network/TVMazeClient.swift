//
//  TVMazeClient.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/10.
//

import Foundation

// MARK: - Transport

enum TVMazeClientError: Error, Equatable {
    case invalidResponse
    case invalidURL
    case httpStatus(Int)
}

struct TVMazeHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
    let retryAfter: String?

    init(statusCode: Int, data: Data = Data(), retryAfter: String? = nil) {
        self.statusCode = statusCode
        self.data = data
        self.retryAfter = retryAfter
    }
}

// MARK: - Client

/// A client for discovering TVMaze identifiers and retrieving hydrated show details.
///
/// Identifier discovery deliberately returns only a TVMaze ID. Call ``show(id:)`` separately
/// when full details, including the embedded next episode, are required.
struct TVMazeClient: Sendable {
    // MARK: - Dependencies

    private let baseURL: URL
    private let maxRateLimitRetries: Int
    private let performRequest: @Sendable (URLRequest) async throws -> TVMazeHTTPResponse
    private let sleep: @Sendable (UInt64) async throws -> Void

    // MARK: - Initialization

    init(session: URLSession = .shared) {
        self.init(
            baseURL: URL(string: "https://api.tvmaze.com")!,
            performRequest: { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw TVMazeClientError.invalidResponse
                }
                return TVMazeHTTPResponse(
                    statusCode: response.statusCode,
                    data: data,
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                )
            }
        )
    }

    init(
        baseURL: URL = URL(string: "https://api.tvmaze.com")!,
        maxRateLimitRetries: Int = 2,
        performRequest: @escaping @Sendable (URLRequest) async throws -> TVMazeHTTPResponse,
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.baseURL = baseURL
        self.maxRateLimitRetries = max(0, maxRateLimitRetries)
        self.performRequest = performRequest
        self.sleep = sleep
    }

    // MARK: - Identifier Discovery

    /// Returns the TVMaze ID mapped to a TVDB ID, or `nil` when TVMaze has no mapping.
    func lookupShowID(tvdbID: Int) async throws -> Int? {
        try await lookupShowID(queryItem: URLQueryItem(name: "thetvdb", value: String(tvdbID)))
    }

    /// Returns the TVMaze ID mapped to an IMDb ID, or `nil` when TVMaze has no mapping.
    func lookupShowID(imdbID: String) async throws -> Int? {
        try await lookupShowID(queryItem: URLQueryItem(name: "imdb", value: imdbID))
    }

    /// Returns TVMaze's ranked title-search results without embedded episode details.
    func searchShows(named query: String) async throws -> [TVMazeShow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let data = try await requestData(
            path: "/search/shows",
            queryItems: [URLQueryItem(name: "q", value: query)]
        )
        guard let data else { return [] }

        return try JSONDecoder()
            .decode([TVMazeSearchResultResponse].self, from: data)
            .map(\.show.value)
    }

    // MARK: - Show Details

    /// Retrieves a show by TVMaze ID with its next episode embedded in the response.
    func show(id: Int) async throws -> TVMazeShow? {
        let data = try await requestData(
            path: "/shows/\(id)",
            queryItems: [URLQueryItem(name: "embed", value: "nextepisode")],
            returnsNilForNotFound: true
        )
        guard let data else { return nil }
        return try JSONDecoder().decode(TVMazeShowResponse.self, from: data).value
    }

    // MARK: - Request Execution

    private func lookupShowID(queryItem: URLQueryItem) async throws -> Int? {
        let data = try await requestData(
            path: "/lookup/shows",
            queryItems: [queryItem],
            returnsNilForNotFound: true
        )
        guard let data else { return nil }
        return try JSONDecoder().decode(TVMazeShowIDResponse.self, from: data).id
    }

    private func requestData(
        path: String,
        queryItems: [URLQueryItem] = [],
        returnsNilForNotFound: Bool = false
    ) async throws -> Data? {
        let request = try makeRequest(path: path, queryItems: queryItems)

        for attempt in 0...maxRateLimitRetries {
            let response = try await performRequest(request)

            if response.statusCode == 404, returnsNilForNotFound {
                return nil
            }

            if response.statusCode == 429, attempt < maxRateLimitRetries {
                try await sleep(retryDelayNanoseconds(response: response, attempt: attempt))
                continue
            }

            guard (200..<300).contains(response.statusCode) else {
                throw TVMazeClientError.httpStatus(response.statusCode)
            }

            return response.data
        }

        throw TVMazeClientError.invalidResponse
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw TVMazeClientError.invalidURL
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw TVMazeClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AniShelf", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func retryDelayNanoseconds(response: TVMazeHTTPResponse, attempt: Int) -> UInt64 {
        if let retryAfter = response.retryAfter,
            let seconds = TimeInterval(retryAfter),
            seconds > 0
        {
            return UInt64(seconds * 1_000_000_000)
        }

        return 500_000_000 * UInt64(1 << attempt)
    }
}

// MARK: - Identifier Responses

fileprivate struct TVMazeShowIDResponse: Decodable {
    let id: Int
}

fileprivate struct TVMazeSearchResultResponse: Decodable {
    let show: TVMazeShowResponse
}

// MARK: - Show Response

fileprivate struct TVMazeShowResponse: Decodable {
    let id: Int
    let name: String
    let language: String?
    let premiered: String?
    let schedule: TVMazeScheduleResponse
    let network: TVMazeChannelResponse?
    let webChannel: TVMazeChannelResponse?
    let image: TVMazeImageResponse?
    let embedded: TVMazeEmbeddedResponse?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case language
        case premiered
        case schedule
        case network
        case webChannel
        case image
        case embedded = "_embedded"
    }

    // MARK: - Domain Model Conversion

    var value: TVMazeShow {
        let timeZone = [network?.country?.timeZone, webChannel?.country?.timeZone]
            .compactMap { $0 }
            .compactMap(TimeZone.init(identifier:))
            .first
        let scheduleTime = TVMazeTimeOfDay(providerValue: schedule.time)

        let nextEpisodeAiring: TVMazeNextEpisodeAiring?
        if let episode = embedded?.nextEpisode,
            let airStamp = episode.airStamp,
            let date = ISO8601DateFormatter().date(from: airStamp)
        {
            nextEpisodeAiring = TVMazeNextEpisodeAiring(
                seasonNumber: episode.season,
                episodeNumber: episode.number,
                airStamp: date
            )
        } else {
            nextEpisodeAiring = nil
        }

        return TVMazeShow(
            id: id,
            name: name,
            language: language,
            premiered: premiered,
            providerLocalSchedule: TVMazeSchedule(
                days: schedule.days.map(TVMazeWeekday.init(providerValue:)),
                time: scheduleTime,
                // TVMaze labels broadcasts from midnight through 04:59 as the previous day.
                dayOffsetFromBroadcastDay: scheduleTime.map { $0.hour < 5 ? 1 : 0 } ?? 0
            ),
            timeZone: timeZone,
            fullImageURL: image?.original.flatMap(URL.init(string:)),
            nextEpisodeAiring: nextEpisodeAiring
        )
    }
}

// MARK: - Nested Show Responses

fileprivate struct TVMazeScheduleResponse: Decodable {
    let time: String
    let days: [String]
}

fileprivate struct TVMazeChannelResponse: Decodable {
    let country: TVMazeCountryResponse?
}

fileprivate struct TVMazeCountryResponse: Decodable {
    let timeZone: String?

    private enum CodingKeys: String, CodingKey {
        case timeZone = "timezone"
    }
}

fileprivate struct TVMazeImageResponse: Decodable {
    let original: String?
}

fileprivate struct TVMazeEmbeddedResponse: Decodable {
    let nextEpisode: TVMazeEpisodeResponse?

    private enum CodingKeys: String, CodingKey {
        case nextEpisode = "nextepisode"
    }
}

fileprivate struct TVMazeEpisodeResponse: Decodable {
    let season: Int?
    let number: Int?
    let airStamp: String?

    private enum CodingKeys: String, CodingKey {
        case season
        case number
        case airStamp = "airstamp"
    }
}
