//
//  UserEntryInfoAndLibraryStatsTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import Testing
import UIKit

@testable import DataProvider
@testable import MyAnimeList

struct UserEntryInfoAndLibraryStatsTests {
    @Test func testLibraryBatchActionsApplySafeCoreEntryMutations() {
        let first = AnimeEntry.template(id: 11)
        let second = AnimeEntry.template(id: 12)
        let entries = [first, second]

        LibraryBatchAction.favorite(true).apply(to: entries)
        #expect(first.favorite)
        #expect(second.favorite)

        LibraryBatchAction.favorite(false).apply(to: entries)
        #expect(!first.favorite)
        #expect(!second.favorite)

        LibraryBatchAction.dateTracking(false).apply(to: entries)
        #expect(!first.isDateTrackingEnabled)
        #expect(!second.isDateTrackingEnabled)

        LibraryBatchAction.watchStatus(.watched).apply(to: entries)
        #expect(first.watchStatus == .watched)
        #expect(second.watchStatus == .watched)
        #expect(first.dateStarted == nil)
        #expect(second.dateFinished == nil)

        LibraryBatchAction.dateTracking(true).apply(to: entries)
        #expect(first.isDateTrackingEnabled)
        #expect(second.isDateTrackingEnabled)
        #expect(first.dateStarted != nil)
        #expect(second.dateFinished != nil)

        LibraryBatchAction.score(5).apply(to: entries)
        #expect(first.score == 5)
        #expect(second.score == 5)

        LibraryBatchAction.score(nil).apply(to: entries)
        #expect(first.score == nil)
        #expect(second.score == nil)
    }

    @Test func testEntryScoreRoundTripAndChangeDetection() throws {
        let entry = AnimeEntry.template(id: 101)
        let originalUserInfo = entry.userInfo

        entry.setScore(4)
        #expect(entry.score == 4)
        #expect(entry.userInfo.score == 4)
        #expect(entry.userInfoHasChanges(comparedTo: originalUserInfo))

        let encoded = try JSONEncoder().encode(entry.userInfo)
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: encoded)
        #expect(decoded == entry.userInfo)

        let restored = AnimeEntry.template(id: 202)
        restored.updateUserInfo(from: decoded)
        #expect(restored.score == 4)
        #expect(restored.userInfo == decoded)

        entry.setScore(nil)
        #expect(entry.score == nil)
        #expect(!entry.userInfoHasChanges(comparedTo: originalUserInfo))
    }

    @Test func testDateTrackingFlagRoundTripAndChangeDetection() throws {
        let entry = AnimeEntry.template(id: 111)
        let originalUserInfo = entry.userInfo

        entry.isDateTrackingEnabled = false
        entry.dateStarted = referenceDate(year: 2026, month: 5, day: 9)
        entry.dateFinished = referenceDate(year: 2026, month: 5, day: 10)

        #expect(!entry.userInfo.isDateTrackingEnabled)
        #expect(!entry.userInfo.isEmpty)
        #expect(entry.userInfoHasChanges(comparedTo: originalUserInfo))

        let encoded = try JSONEncoder().encode(entry.userInfo)
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: encoded)
        #expect(decoded == entry.userInfo)
        #expect(!decoded.isDateTrackingEnabled)

        let restored = AnimeEntry.template(id: 112)
        restored.updateUserInfo(from: decoded)

        #expect(!restored.isDateTrackingEnabled)
        #expect(restored.dateStarted == referenceDate(year: 2026, month: 5, day: 9))
        #expect(restored.dateFinished == referenceDate(year: 2026, month: 5, day: 10))
        #expect(restored.userInfo == decoded)

        entry.isDateTrackingEnabled = true
        entry.dateStarted = nil
        entry.dateFinished = nil
        #expect(entry.userInfo == originalUserInfo)
        #expect(!entry.userInfoHasChanges(comparedTo: originalUserInfo))
    }

    @Test func testReEnablingDateTrackingNormalizesCurrentWatchStatus() {
        let watching = AnimeEntry.template(id: 211)
        watching.setDateTrackingEnabled(false)
        watching.setWatchStatus(.watching, now: referenceDate(year: 2026, month: 5, day: 9))
        watching.setDateTrackingEnabled(true, now: referenceDate(year: 2026, month: 5, day: 10))
        #expect(watching.dateStarted == referenceDate(year: 2026, month: 5, day: 10))
        #expect(watching.dateFinished == nil)

        let watched = AnimeEntry.template(id: 212)
        watched.setDateTrackingEnabled(false)
        watched.setWatchStatus(.watched, now: referenceDate(year: 2026, month: 5, day: 9))
        watched.setDateTrackingEnabled(true, now: referenceDate(year: 2026, month: 5, day: 10))
        #expect(watched.dateStarted == referenceDate(year: 2026, month: 5, day: 10))
        #expect(watched.dateFinished == referenceDate(year: 2026, month: 5, day: 10))

        let planned = AnimeEntry.template(id: 213)
        planned.setDateTrackingEnabled(false)
        planned.dateStarted = referenceDate(year: 2026, month: 5, day: 3)
        planned.dateFinished = referenceDate(year: 2026, month: 5, day: 7)
        planned.setWatchStatus(.planToWatch, now: referenceDate(year: 2026, month: 5, day: 9))
        planned.setDateTrackingEnabled(true, now: referenceDate(year: 2026, month: 5, day: 10))
        #expect(planned.dateStarted == nil)
        #expect(planned.dateFinished == nil)
    }

    @Test func testEntryScoreNormalizationRejectsOutOfRangeValues() throws {
        let entry = AnimeEntry.template(id: 303)
        entry.setScore(9)

        #expect(entry.score == nil)

        entry.setScore(1)
        #expect(entry.score == 1)

        var payload = try #require(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(entry.userInfo)
            ) as? [String: Any]
        )
        payload["score"] = 99

        let invalidData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: invalidData)
        #expect(decoded.score == nil)
    }

    //    @Test @MainActor func testUserEntryInfoPasteboardRoundTripPreservesScore() throws {
    //        let pasteboard = UIPasteboard.general
    //        let originalItems = pasteboard.items
    //        defer { pasteboard.items = originalItems }
    //
    //        let entry = AnimeEntry.template(id: 404)
    //        entry.setScore(5)
    //        entry.notes = "Keep this"
    //
    //        entry.userInfo.copyToPasteboard()
    //
    //        let pasted = try #require(UserEntryInfo.fromPasteboard())
    //        #expect(pasted.score == 5)
    //        #expect(pasted.notes == "Keep this")
    //    }

    @Test func testLibraryProfileStatsEmptyLibrary() {
        let stats = LibraryProfileStats(entries: [])

        #expect(stats.totalCount == 0)
        #expect(stats.favoriteCount == 0)
        #expect(stats.runtimeMinutes == 0)
    }

    @Test func testLibraryProfileStatsMixedLibrary() {
        let movie = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 1,
            detail: AnimeEntryDetail(language: "en", title: "Movie", runtimeMinutes: 100),
            dateSaved: referenceDate(year: 2026, month: 1, day: 3)
        )
        movie.setWatchStatus(.watched, now: referenceDate(year: 2026, month: 1, day: 3))
        movie.favorite = true
        movie.notes = "Worth rewatching"
        movie.usingCustomPoster = true

        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 2,
            detail: AnimeEntryDetail(
                language: "en",
                title: "Series",
                runtimeMinutes: 24,
                episodeCount: 12
            ),
            dateSaved: referenceDate(year: 2026, month: 2, day: 8)
        )
        series.setWatchStatus(.watching, now: referenceDate(year: 2026, month: 2, day: 8))

        let season = AnimeEntry(
            name: "Season",
            type: .season(seasonNumber: 1, parentSeriesID: 2),
            tmdbID: 3
        )
        season.setWatchStatus(.dropped, now: referenceDate(year: 2026, month: 2, day: 8))

        let stats = LibraryProfileStats(entries: [movie, series, season])

        #expect(stats.totalCount == 3)
        #expect(stats.watchedCount == 1)
        #expect(stats.watchingCount == 1)
        #expect(stats.planToWatchCount == 0)
        #expect(stats.droppedCount == 1)
        #expect(stats.favoriteCount == 1)
        #expect(stats.movieCount == 1)
        #expect(stats.seriesCount == 1)
        #expect(stats.seasonCount == 1)
        #expect(stats.entriesWithNotesCount == 1)
        #expect(stats.runtimeMinutes == 388)
    }
}
