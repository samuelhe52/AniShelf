//
//  RedirectingHTTPClient.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/4/13.
//

import Foundation
import TMDb

///
/// A custom `HTTPClient` redirecting requests to a certain host to another host.
///
struct RedirectingHTTPClient: HTTPClient {
    let fromHost: String
    let toHost: String
    var isEnabled: @Sendable () -> Bool = { true }
    var maxRateLimitRetries: Int = 2
    var baseRetryDelayNanoseconds: UInt64 = 500_000_000

    func perform(request: HTTPRequest) async throws -> HTTPResponse {
        guard var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        else {
            throw URLError(.badURL)
        }
        if isEnabled(), components.host == fromHost {
            components.host = toHost
        }

        guard let redirectedURL = components.url else {
            throw URLError(.badURL)
        }

        var urlRequest = URLRequest(url: redirectedURL)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.allHTTPHeaderFields = request.headers

        for attempt in 0...maxRateLimitRetries {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 429, attempt < maxRateLimitRetries {
                try await Task.sleep(
                    nanoseconds: retryDelayNanoseconds(
                        for: httpResponse,
                        attempt: attempt
                    )
                )
                continue
            }

            return HTTPResponse(
                statusCode: httpResponse.statusCode,
                data: data
            )
        }

        throw URLError(.cannotParseResponse)
    }

    private func retryDelayNanoseconds(
        for response: HTTPURLResponse,
        attempt: Int
    ) -> UInt64 {
        if let retryAfterNanoseconds = retryAfterNanoseconds(from: response) {
            return retryAfterNanoseconds
        }

        let multiplier = UInt64(1 << attempt)
        return baseRetryDelayNanoseconds * multiplier
    }

    private func retryAfterNanoseconds(from response: HTTPURLResponse) -> UInt64? {
        guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(retryAfter), seconds > 0 {
            return UInt64(seconds * 1_000_000_000)
        }

        return nil
    }
}

extension RedirectingHTTPClient {
    static let relayServer: Self = .init(
        fromHost: "api.themoviedb.org",
        toHost: "tmdb-api.konakona52.com",
        isEnabled: { UserDefaults.standard.usesTMDbRelayServer }
    )
}
