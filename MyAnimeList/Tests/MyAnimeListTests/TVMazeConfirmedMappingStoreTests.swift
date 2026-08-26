//
//  TVMazeConfirmedMappingStoreTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/8/11.
//

import Foundation
import Testing

@testable import MyAnimeList

struct TVMazeConfirmedMappingStoreTests {
    @Test func confirmedMappingsPersistAcrossStoreInstancesWithoutReplacingOtherSeries() async {
        let suiteName = "TVMazeConfirmedMappingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let writer = TVMazeConfirmedMappingStore(defaults: defaults)
        let insertion = await writer.confirm(showID: 70, forTMDbSeriesID: 10)
        let unchanged = await writer.confirm(showID: 70, forTMDbSeriesID: 10)
        let otherInsertion = await writer.confirm(showID: 80, forTMDbSeriesID: 20)
        let replacement = await writer.confirm(showID: 71, forTMDbSeriesID: 10)

        let reader = TVMazeConfirmedMappingStore(
            defaults: UserDefaults(suiteName: suiteName)!
        )

        #expect(await reader.showID(forTMDbSeriesID: 10) == 71)
        #expect(await reader.showID(forTMDbSeriesID: 20) == 80)
        #expect(await reader.showID(forTMDbSeriesID: 30) == nil)
        #expect(insertion == .inserted)
        #expect(unchanged == .unchanged)
        #expect(otherInsertion == .inserted)
        #expect(
            replacement
                == .replaced(
                    .init(tmdbSeriesID: 10, previousShowID: 70, newShowID: 71)
                )
        )
    }
}
