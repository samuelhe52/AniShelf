//
//  LibraryMetadataRefreshTestSupport.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

enum TestApplyError: Error {
    case failed
}

actor MetadataFetchConcurrencyProbe {
    private var firstMovieReturned = false
    private var ninthMovieStartedBeforeFirstMovieReturned = false

    var startedNinthMovieBeforeFirstMovieReturned: Bool {
        ninthMovieStartedBeforeFirstMovieReturned
    }

    func recordRequest(path: String) async throws {
        if path == "/3/movie/9", !firstMovieReturned {
            ninthMovieStartedBeforeFirstMovieReturned = true
        }

        if path == "/3/movie/1" {
            try await Task.sleep(nanoseconds: 250_000_000)
            firstMovieReturned = true
        }
    }
}

actor MetadataRefreshRequestGate {
    private var requestStarted = false
    private var requestStartWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func blockRequest() async {
        requestStarted = true
        requestStartWaiter?.resume()
        requestStartWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForRequest() async {
        guard !requestStarted else { return }
        await withCheckedContinuation { requestStartWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

actor MetadataRefreshCompletionSignal {
    private var didSignal = false

    var isSignaled: Bool {
        didSignal
    }

    func signal() {
        didSignal = true
    }
}

func makeLibraryMetadataRefreshTestFetcher() -> InfoFetcher {
    let httpClient = RecordingTMDbHTTPClient { request in
        HTTPResponse(data: libraryMetadataRefreshFixtureData(for: request.url.path))
    }

    return InfoFetcher(
        client: TMDbClient(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        ),
        fetchTMDbResponseData: { path in
            libraryMetadataRefreshFixtureData(for: path)
        }
    )
}

func libraryMetadataRefreshFixtureData(for path: String) -> Data {
    switch path {
    case "/3/configuration":
        Data(
            #"""
            {
                "images": {
                    "base_url": "http://image.tmdb.org/t/p/",
                    "secure_base_url": "https://image.tmdb.org/t/p/",
                    "backdrop_sizes": ["w300", "w780", "w1280", "original"],
                    "logo_sizes": ["w45", "w92", "w154", "w185", "w300", "w500", "original"],
                    "poster_sizes": ["w92", "w154", "w185", "w342", "w500", "w780", "original"],
                    "profile_sizes": ["w45", "w185", "h632", "original"],
                    "still_sizes": ["w92", "w185", "w300", "original"]
                },
                "change_keys": []
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/images"):
        Data(
            #"""
            {
                "id": 550,
                "backdrops": [
                    {
                        "aspect_ratio": 1.77777777777778,
                        "file_path": "/fCayJrkfRaCRCTh8GqN30f8oyQF.jpg",
                        "height": 720,
                        "iso_639_1": null,
                        "vote_average": 1.21,
                        "vote_count": 435,
                        "width": 1280
                    }
                ],
                "logos": [
                    {
                        "aspect_ratio": 2.5,
                        "file_path": "/fasasakfRaCRCTh8GqN30f8oyQF.jpg",
                        "height": 400,
                        "iso_639_1": null,
                        "vote_average": 5.31,
                        "vote_count": 345,
                        "width": 100
                    }
                ],
                "posters": [
                    {
                        "aspect_ratio": 0.666666666666667,
                        "file_path": "/fpemzjF623QVTe98pCVlwwtFC5N.jpg",
                        "height": 1800,
                        "iso_639_1": "en",
                        "vote_average": 5.21,
                        "vote_count": 3,
                        "width": 1200
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/translations"):
        Data(
            #"""
            {
                "id": 550,
                "translations": [
                    {
                        "iso_3166_1": "US",
                        "iso_639_1": "en",
                        "name": "English",
                        "english_name": "English",
                        "data": {
                            "title": "Fight Club",
                            "overview": "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
                            "homepage": "https://www.foxmovies.com/movies/fight-club",
                            "tagline": "Mischief. Mayhem. Soap."
                        }
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.hasSuffix("/credits"):
        Data(
            #"""
            {
                "id": 550,
                "cast": [
                    {
                        "cast_id": 4,
                        "character": "The Narrator",
                        "credit_id": "52fe4250c3a36847f80149f3",
                        "gender": 2,
                        "id": 819,
                        "name": "Edward Norton",
                        "order": 0,
                        "profile_path": "/eIkFHNlfretLS1spAcIoihKUS62.jpg"
                    }
                ],
                "crew": [
                    {
                        "credit_id": "56380f0cc3a3681b5c0200be",
                        "department": "Writing",
                        "gender": 0,
                        "id": 7469,
                        "job": "Screenplay",
                        "name": "Jim Uhls",
                        "profile_path": null
                    }
                ]
            }
            """#.utf8
        )
    case let path where path.starts(with: "/3/movie/"):
        Data(
            #"""
            {
                "adult": false,
                "backdrop_path": "/fCayJrkfRaCRCTh8GqN30f8oyQF.jpg",
                "belongs_to_collection": null,
                "budget": 63000000,
                "genres": [
                    {
                        "id": 18,
                        "name": "Drama"
                    }
                ],
                "homepage": null,
                "id": 550,
                "imdb_id": "tt0137523",
                "origin_country": ["US"],
                "original_language": "en",
                "original_title": "Fight Club",
                "overview": "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
                "popularity": 0.5,
                "poster_path": null,
                "production_companies": [
                    {
                        "id": 508,
                        "logo_path": "/7PzJdsLGlR7oW4J0J5Xcd0pHGRg.png",
                        "name": "Regency Enterprises",
                        "origin_country": "US"
                    }
                ],
                "production_countries": [
                    {
                        "iso_3166_1": "US",
                        "name": "United States of America"
                    }
                ],
                "release_date": "1999-10-12",
                "revenue": 100853753,
                "runtime": 139,
                "spoken_languages": [
                    {
                        "iso_639_1": "en",
                        "name": "English"
                    }
                ],
                "status": "Released",
                "tagline": "How much can you know about yourself if you've never been in a fight?",
                "title": "Fight Club",
                "video": false,
                "vote_average": 7.8,
                "vote_count": 3439
            }
            """#.utf8
        )
    default:
        Data()
    }
}
