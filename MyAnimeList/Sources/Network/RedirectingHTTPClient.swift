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

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return HTTPResponse(
            statusCode: httpResponse.statusCode,
            data: data
        )
    }
}

extension RedirectingHTTPClient {
    static let relayServer: Self = .init(
        fromHost: "api.themoviedb.org",
        toHost: "tmdb-api.konakona52.com",
        isEnabled: { UserDefaults.standard.usesTMDbRelayServer }
    )
}
