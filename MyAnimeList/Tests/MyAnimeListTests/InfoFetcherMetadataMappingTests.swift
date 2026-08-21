//
//  InfoFetcherMetadataMappingTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct InfoFetcherMetadataMappingTests {
    @Test func testRuntimeDurationMapsToWholeMinutes() {
        #expect(InfoFetcher.runtimeMinutes(from: .seconds(90 * 60)) == 90)
    }

    @Test func testTVSeriesBroadcastDetailsCombinesSchedulingAndExternalIDs() async throws {
        let responseData = Data(
            #"""
            {
                "first_air_date": "2026-01-01",
                "next_episode_to_air": {
                    "season_number": 2,
                    "air_date": "2026-08-13"
                },
                "last_episode_to_air": {
                    "season_number": 2,
                    "air_date": "2026-08-06"
                },
                "seasons": [
                    { "season_number": 1, "air_date": "2026-01-01" },
                    { "season_number": 2, "air_date": "2026-08-01" }
                ],
                "external_ids": {
                    "imdb_id": "tt22248376",
                    "tvdb_id": 424536
                }
            }
            """#.utf8
        )
        let httpClient = RecordingTMDbHTTPClient { request in
            #expect(request.url.path == "/3/tv/209867")
            return HTTPResponse(data: responseData)
        }
        let fetcher = InfoFetcher(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        )

        let details = try await fetcher.tvSeriesBroadcastDetails(tmdbID: 209_867)
        let requests = await httpClient.requests

        #expect(
            details.externalIDs
                == TMDbSeriesExternalIDs(tvdbID: 424_536, imdbID: "tt22248376")
        )
        #expect(details.schedule.nextEpisode?.seasonNumber == 2)
        #expect(
            details.schedule.nextEpisode?.airDate
                == TMDbCalendarDate(year: 2026, month: 8, day: 13)
        )
        #expect(details.schedule.lastEpisode?.seasonNumber == 2)
        #expect(
            details.schedule.lastEpisode?.airDate
                == TMDbCalendarDate(year: 2026, month: 8, day: 6)
        )
        #expect(details.schedule.seasonAirDates.keys.sorted() == [1, 2])
        #expect(requests.count == 1)
        #expect(requests.first?.url.queryValue(named: "api_key") == "test-key")
        #expect(
            requests.first?.url.queryValue(named: "append_to_response") == "external_ids"
        )
    }

    @Test func testTVSeriesBroadcastDetailsKeepsMissingIdentifiersOptional() async throws {
        let responseData = Data(
            #"""
            {
                "first_air_date": null,
                "next_episode_to_air": null,
                "seasons": [],
                "external_ids": { "imdb_id": "  \n", "tvdb_id": null }
            }
            """#.utf8
        )
        let httpClient = RecordingTMDbHTTPClient { _ in
            HTTPResponse(data: responseData)
        }
        let fetcher = InfoFetcher(
            apiKey: "test-key",
            httpClient: httpClient,
            configuration: .default
        )

        let details = try await fetcher.tvSeriesBroadcastDetails(tmdbID: 274_580)

        #expect(details.externalIDs == TMDbSeriesExternalIDs(tvdbID: nil, imdbID: nil))
    }

    @Test func testBroadcastEligibilityPreservesTMDbDateInNegativeOffsetCalendar() async throws {
        let responseData = Data(
            #"""
            {
                "first_air_date": "2020-01-01",
                "next_episode_to_air": {
                    "season_number": 2,
                    "air_date": "2026-08-13"
                },
                "seasons": [],
                "external_ids": { "imdb_id": "tt22248376", "tvdb_id": 424536 }
            }
            """#.utf8
        )
        let fetcher = InfoFetcher(
            apiKey: "test-key",
            httpClient: RecordingTMDbHTTPClient { _ in HTTPResponse(data: responseData) },
            configuration: .default
        )
        let checker = TMDbBroadcastEligibilityChecker(infoFetcher: fetcher)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 13, hour: 1)
            )
        )

        let result = try await checker.check(
            entryType: .series,
            tmdbSeriesID: 209_867,
            now: now,
            calendar: calendar
        )

        #expect(
            result
                == .eligible(
                    externalIDs: TMDbSeriesExternalIDs(
                        tvdbID: 424_536,
                        imdbID: "tt22248376"
                    ),
                    airingEvidence: TMDbAiringEvidence(
                        airDate: TMDbCalendarDate(year: 2026, month: 8, day: 13),
                        basis: .nextEpisode
                    )
                )
        )
    }

    @Test func testStableStaffIdentifierUsesCreditID() {
        let first = InfoFetcher.stableStaffIdentifier(
            creditID: "52fe4250c3a36847f8014a11",
            fallbackID: 7
        )
        let second = InfoFetcher.stableStaffIdentifier(
            creditID: "52fe4250c3a36847f8014a11",
            fallbackID: 99
        )
        let different = InfoFetcher.stableStaffIdentifier(
            creditID: "56380f0cc3a3681b5c0200be",
            fallbackID: 7
        )

        #expect(first == second)
        #expect(first != different)
    }

    @Test func testAggregateStaffMappingMergesRepeatedCrewEntriesAndRetainsJobs() {
        let imagesConfiguration = makeImagesConfiguration()
        let staffDTOs = InfoFetcher.aggregateStaffDTOs(
            from: [
                AggregateCrewMember(
                    id: 10,
                    name: "Creator",
                    originalName: "Creator Original",
                    gender: .unknown,
                    profilePath: nil,
                    jobs: [
                        CrewJob(creditID: "director", job: "Director", episodeCount: 12),
                        CrewJob(creditID: "music", job: "Music", episodeCount: 8)
                    ],
                    knownForDepartment: "Directing",
                    isAdultOnly: nil,
                    totalEpisodeCount: 12,
                    popularity: nil
                ),
                AggregateCrewMember(
                    id: 10,
                    name: "Creator",
                    originalName: "Creator Original",
                    gender: .unknown,
                    profilePath: nil,
                    jobs: [
                        CrewJob(creditID: "writer", job: "Writer", episodeCount: 10)
                    ],
                    knownForDepartment: "Writing",
                    isAdultOnly: nil,
                    totalEpisodeCount: 10,
                    popularity: nil
                )
            ],
            imagesConfiguration: imagesConfiguration,
            language: .english
        )

        #expect(staffDTOs.count == 1)
        #expect(staffDTOs[0].id == 10)
        #expect(staffDTOs[0].role == "Directing")
        #expect(staffDTOs[0].jobs.map { $0.job } == ["Director", "Music", "Writer"])
        #expect(staffDTOs[0].jobs.map { $0.creditID } == ["director", "music", "writer"])
    }
}
