//
//  AnimeEntryPreviewFixtureTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/30.
//

import Foundation
import Testing

@testable import DataProvider

@Test func previewFixturesContainStableCoreMetadata() {
    let fixtures: [(entry: AnimeEntry, expectedDate: Date?)] = [
        (.frieren, previewFixtureDate(year: 2023, month: 9, day: 29)),
        (.yourName, previewFixtureDate(year: 2016, month: 7, day: 1)),
        (.clannadSeasonOne, previewFixtureDate(year: 2007, month: 10, day: 5))
    ]

    for fixture in fixtures {
        #expect(fixture.entry.tmdbID > 0)
        #expect(fixture.entry.originalLanguageCode == "ja")
        #expect(fixture.entry.onAirDate == fixture.expectedDate)
        #expect(fixture.entry.linkToDetails != nil)
        #expect(fixture.entry.posterPath != nil)
        #expect(fixture.entry.backdropPath != nil)
        #expect(fixture.entry.overview?.isEmpty == false)
    }
}

@Test func previewFixtureMediaIdentitiesRemainCorrect() {
    #expect(AnimeEntry.frieren.type == .series)
    #expect(AnimeEntry.frieren.tmdbID == 209867)

    #expect(AnimeEntry.yourName.type == .movie)
    #expect(AnimeEntry.yourName.tmdbID == 372058)

    #expect(
        AnimeEntry.clannadSeasonOne.type
            == .season(seasonNumber: 1, parentSeriesID: 24835)
    )
    #expect(AnimeEntry.clannadSeasonOne.tmdbID == 35033)
}

fileprivate func previewFixtureDate(year: Int, month: Int, day: Int) -> Date? {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )
}
