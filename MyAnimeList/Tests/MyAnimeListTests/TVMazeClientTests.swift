//
//  TVMazeClientTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/10.
//

import Foundation
import Testing

@testable import MyAnimeList

struct TVMazeClientTests {
    @Test func showTransformsProviderScheduleImageAndNextEpisode() async throws {
        let responseData = Data(
            #"""
            {
              "id": 90814,
              "name": "I Want to Love You Till Your Dying Day",
              "language": "Japanese",
              "premiered": "2026-07-07",
              "schedule": {
                "time": "01:30",
                "days": ["Tuesday"]
              },
              "network": {
                "country": {
                  "timezone": "Asia/Tokyo"
                }
              },
              "webChannel": null,
              "image": {
                "medium": "https://example.com/medium.jpg",
                "original": "https://example.com/original.jpg"
              },
              "_embedded": {
                "nextepisode": {
                  "season": 1,
                  "number": 6,
                  "airdate": "2026-08-11",
                  "airtime": "01:30",
                  "airstamp": "2026-08-11T16:30:00+00:00"
                }
              }
            }
            """#.utf8
        )
        let transport = RecordingTVMazeTransport(
            responses: [TVMazeHTTPResponse(statusCode: 200, data: responseData)]
        )
        let client = TVMazeClient(
            performRequest: { request in
                try await transport.perform(request)
            }
        )

        let show = try #require(await client.show(id: 90_814))
        let requests = await transport.requests
        let request = try #require(requests.first)
        let requestURL = try #require(request.url)

        #expect(requestURL.path == "/shows/90814")
        #expect(queryValue(named: "embed", in: requestURL) == "nextepisode")
        #expect(show.providerLocalSchedule.days == [.tuesday])
        #expect(
            show.providerLocalSchedule.time
                == TVMazeTimeOfDay(hour: 1, minute: 30, context: .provider)
        )
        #expect(show.providerLocalSchedule.dayOffsetFromBroadcastDay == 1)
        #expect(show.timeZone == TimeZone(identifier: "Asia/Tokyo"))
        #expect(show.fullImageURL == URL(string: "https://example.com/original.jpg"))
        #expect(
            show.nextEpisodeAiring?.airStamp
                == ISO8601DateFormatter().date(from: "2026-08-11T16:30:00+00:00")
        )
    }

    @Test func lookupBuildsProviderQueriesAndTreatsNotFoundAsMissing() async throws {
        let transport = RecordingTVMazeTransport(
            responses: [
                TVMazeHTTPResponse(statusCode: 200, data: Data(#"{"id":69956}"#.utf8)),
                TVMazeHTTPResponse(statusCode: 200, data: Data(#"{"id":69956}"#.utf8)),
                TVMazeHTTPResponse(statusCode: 404)
            ]
        )
        let client = TVMazeClient(
            performRequest: { request in
                try await transport.perform(request)
            }
        )

        _ = try await client.lookupShowID(tvdbID: 424_536)
        _ = try await client.lookupShowID(imdbID: "tt22248376")
        let missingResult = try await client.lookupShowID(tvdbID: 1)
        let requests = await transport.requests

        #expect(missingResult == nil)
        #expect(requests.compactMap(\.url?.path) == ["/lookup/shows", "/lookup/shows", "/lookup/shows"])
        #expect(requests[0].url.flatMap { queryValue(named: "thetvdb", in: $0) } == "424536")
        #expect(requests[1].url.flatMap { queryValue(named: "imdb", in: $0) } == "tt22248376")
    }

    @Test func titleSearchReturnsTopCandidateID() async throws {
        let searchResponseData = Data(
            #"""
            [
              {
                "score": 0.9,
                "show": {
                  "id": 69956
                }
              },
              {
                "score": 0.5,
                "show": {
                  "id": 80137
                }
              }
            ]
            """#.utf8
        )
        let transport = RecordingTVMazeTransport(
            responses: [TVMazeHTTPResponse(statusCode: 200, data: searchResponseData)]
        )
        let client = TVMazeClient(
            performRequest: { request in
                try await transport.perform(request)
            }
        )

        let showID = try await client.searchShowID(named: "  Frieren & Himmel  ")
        let requests = await transport.requests
        let searchURL = try #require(requests.first?.url)

        #expect(showID == 69_956)
        #expect(requests.count == 1)
        #expect(searchURL.path == "/search/shows")
        #expect(queryValue(named: "q", in: searchURL) == "Frieren & Himmel")
        #expect(queryValue(named: "embed", in: searchURL) == nil)
    }

    @Test func rateLimitRetriesBeforeReturningResponse() async throws {
        let transport = RecordingTVMazeTransport(
            responses: [
                TVMazeHTTPResponse(statusCode: 429, retryAfter: "2"),
                TVMazeHTTPResponse(statusCode: 200, data: Data(#"{"id":42}"#.utf8))
            ]
        )
        let sleeper = TVMazeSleepRecorder()
        let client = TVMazeClient(
            performRequest: { request in
                try await transport.perform(request)
            },
            sleep: { nanoseconds in
                await sleeper.sleep(nanoseconds)
            }
        )

        _ = try await client.lookupShowID(tvdbID: 7)
        let requests = await transport.requests
        let delays = await sleeper.delays

        #expect(requests.count == 2)
        #expect(delays == [2_000_000_000])
    }
}

private actor RecordingTVMazeTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [TVMazeHTTPResponse]

    init(responses: [TVMazeHTTPResponse]) {
        self.responses = responses
    }

    func perform(_ request: URLRequest) throws -> TVMazeHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw TVMazeClientError.invalidResponse
        }
        return responses.removeFirst()
    }
}

private actor TVMazeSleepRecorder {
    private(set) var delays: [UInt64] = []

    func sleep(_ nanoseconds: UInt64) {
        delays.append(nanoseconds)
    }
}

fileprivate func queryValue(named name: String, in url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == name })?
        .value
}
