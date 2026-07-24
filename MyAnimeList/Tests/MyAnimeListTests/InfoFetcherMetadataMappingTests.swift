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
