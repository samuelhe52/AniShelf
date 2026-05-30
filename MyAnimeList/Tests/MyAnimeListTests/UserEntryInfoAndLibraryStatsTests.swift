//
//  UserEntryInfoAndLibraryStatsTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
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
        #expect(first.dateStarted == nil)
        #expect(second.dateFinished == nil)

        LibraryBatchAction.score(5).apply(to: entries)
        #expect(first.score == 5)
        #expect(second.score == 5)

        LibraryBatchAction.score(nil).apply(to: entries)
        #expect(first.score == nil)
        #expect(second.score == nil)
    }

    @Test func testLibraryBatchActionsSkipTrackingClockForNoOpEntries() {
        let first = AnimeEntry.template(id: 21)
        let second = AnimeEntry.template(id: 22)
        second.favorite = true
        let timestamp = referenceDate(year: 2026, month: 5, day: 20)
        second.trackingUpdatedAt = timestamp

        LibraryBatchAction.favorite(false).apply(to: [first])
        #expect(first.trackingUpdatedAt == nil)

        LibraryBatchAction.favorite(true).apply(to: [second])
        #expect(second.trackingUpdatedAt == timestamp)
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

    @Test func testEpisodeProgressRoundTripAndChangeDetection() throws {
        let entry = AnimeEntry(name: "Series", type: .series, tmdbID: 113)
        let originalUserInfo = entry.userInfo

        entry.setEpisodeProgress(
            seasonNumber: 2,
            watchedThroughEpisode: 5,
            now: referenceDate(year: 2026, month: 5, day: 11)
        )

        #expect(entry.userInfoHasChanges(comparedTo: originalUserInfo))

        let encoded = try JSONEncoder().encode(entry.userInfo)
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: encoded)
        #expect(decoded == entry.userInfo)
        #expect(decoded.episodeProgresses.map(\.seasonNumber) == [2])

        let restored = AnimeEntry(name: "Restored", type: .series, tmdbID: 114)
        restored.setEpisodeProgress(
            seasonNumber: 1,
            watchedThroughEpisode: 9,
            now: referenceDate(year: 2026, month: 5, day: 10)
        )
        restored.updateUserInfo(from: decoded)

        #expect(restored.orderedEpisodeProgresses.map(\.seasonNumber) == [2])
        #expect(restored.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 5)
        #expect(restored.episodeProgress(forSeason: 1) == nil)

        entry.clearEpisodeProgress(seasonNumber: 2)
        #expect(!entry.userInfoHasChanges(comparedTo: originalUserInfo))
    }

    @Test func testEpisodeProgressDirtyStateIgnoresTimestampOnlyChanges() {
        let entry = AnimeEntry(name: "Series", type: .series, tmdbID: 115)
        entry.setEpisodeProgress(
            seasonNumber: 2,
            watchedThroughEpisode: 5,
            now: referenceDate(year: 2026, month: 5, day: 11)
        )
        let originalUserInfo = entry.userInfo

        entry.setEpisodeProgress(
            seasonNumber: 2,
            watchedThroughEpisode: 4,
            now: referenceDate(year: 2026, month: 5, day: 12)
        )
        #expect(entry.userInfoHasChanges(comparedTo: originalUserInfo))

        entry.setEpisodeProgress(
            seasonNumber: 2,
            watchedThroughEpisode: 5,
            now: referenceDate(year: 2026, month: 5, day: 13)
        )
        #expect(entry.userInfo != originalUserInfo)
        #expect(entry.userInfo.isSemanticallyEquivalent(to: originalUserInfo))
        #expect(!entry.userInfoHasChanges(comparedTo: originalUserInfo))
    }

    @Test func testDateTrackingTogglePreservesCurrentDates() {
        let watching = AnimeEntry.template(id: 211)
        watching.setDateTrackingEnabled(false)
        watching.setWatchStatus(.watching)
        watching.dateStarted = referenceDate(year: 2026, month: 5, day: 8)
        watching.setDateTrackingEnabled(true)
        #expect(watching.dateStarted == referenceDate(year: 2026, month: 5, day: 8))
        #expect(watching.dateFinished == nil)

        let watched = AnimeEntry.template(id: 212)
        watched.setDateTrackingEnabled(false)
        watched.setWatchStatus(.watched)
        watched.dateFinished = referenceDate(year: 2026, month: 5, day: 11)
        watched.setDateTrackingEnabled(true)
        #expect(watched.dateStarted == nil)
        #expect(watched.dateFinished == referenceDate(year: 2026, month: 5, day: 11))

        let planned = AnimeEntry.template(id: 213)
        planned.setDateTrackingEnabled(false)
        planned.dateStarted = referenceDate(year: 2026, month: 5, day: 3)
        planned.dateFinished = referenceDate(year: 2026, month: 5, day: 7)
        planned.setWatchStatus(.planToWatch)
        planned.setDateTrackingEnabled(true)
        #expect(planned.dateStarted == referenceDate(year: 2026, month: 5, day: 3))
        #expect(planned.dateFinished == referenceDate(year: 2026, month: 5, day: 7))
    }

    @Test func testDateUpdateSuggestionsFollowRedesignRules() {
        let planned = AnimeEntry.template(id: 214)
        #expect(planned.dateUpdateSuggestion(forTargetStatus: .planToWatch) == nil)
        planned.dateStarted = referenceDate(year: 2026, month: 5, day: 3)
        #expect(planned.dateUpdateSuggestion(forTargetStatus: .planToWatch) == .clearAllDates)

        let watching = AnimeEntry.template(id: 215)
        #expect(watching.dateUpdateSuggestion(forTargetStatus: .watching) == .setStartDateToNow)
        watching.dateStarted = referenceDate(year: 2026, month: 5, day: 4)
        #expect(watching.dateUpdateSuggestion(forTargetStatus: .watching) == nil)

        let watched = AnimeEntry.template(id: 216)
        #expect(watched.dateUpdateSuggestion(forTargetStatus: .watched) == .setFinishDateToNow)
        watched.dateFinished = referenceDate(year: 2026, month: 5, day: 5)
        #expect(watched.dateUpdateSuggestion(forTargetStatus: .watched) == nil)
        #expect(watched.dateUpdateSuggestion(forTargetStatus: .dropped) == nil)
    }

    @Test func testApplyingDateUpdateSuggestionsOnlyTouchesSuggestedFields() {
        let entry = AnimeEntry.template(id: 217)
        entry.dateStarted = referenceDate(year: 2026, month: 5, day: 3)
        entry.dateFinished = referenceDate(year: 2026, month: 5, day: 7)

        entry.applyDateUpdateSuggestion(
            .setStartDateToNow,
            now: referenceDate(year: 2026, month: 5, day: 10)
        )
        #expect(entry.dateStarted == referenceDate(year: 2026, month: 5, day: 10))
        #expect(entry.dateFinished == referenceDate(year: 2026, month: 5, day: 7))

        entry.applyDateUpdateSuggestion(
            .setFinishDateToNow,
            now: referenceDate(year: 2026, month: 5, day: 11)
        )
        #expect(entry.dateStarted == referenceDate(year: 2026, month: 5, day: 10))
        #expect(entry.dateFinished == referenceDate(year: 2026, month: 5, day: 11))

        entry.applyDateUpdateSuggestion(.clearAllDates)
        #expect(entry.dateStarted == nil)
        #expect(entry.dateFinished == nil)
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
        #expect(stats.totalRuntimeMinutes == 0)
        #expect(stats.watchedRuntimeMinutes == 0)
        #expect(stats.plannedRuntimeMinutes == 0)
        #expect(stats.totalRuntimeDescription == "N/A")
        #expect(stats.watchedRuntimeDescription == "N/A")
        #expect(stats.plannedRuntimeDescription == "N/A")
    }

    @Test func testLibraryProfileStatsMixedLibrary() {
        let movie = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 1,
            detail: AnimeEntryDetail(language: "en", title: "Movie", runtimeMinutes: 100),
            dateSaved: referenceDate(year: 2026, month: 1, day: 3)
        )
        movie.setWatchStatus(.watched)
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
        series.setWatchStatus(.watching)

        let plannedSeason = AnimeEntry(
            name: "Planned Season",
            type: .season(seasonNumber: 2, parentSeriesID: 2),
            tmdbID: 4,
            detail: AnimeEntryDetail(
                language: "en",
                title: "Planned Season",
                runtimeMinutes: 30,
                episodeCount: 10
            )
        )
        plannedSeason.setWatchStatus(.planToWatch)

        let season = AnimeEntry(
            name: "Season",
            type: .season(seasonNumber: 1, parentSeriesID: 2),
            tmdbID: 3
        )
        season.setWatchStatus(.dropped)

        let stats = LibraryProfileStats(entries: [movie, series, plannedSeason, season])

        #expect(stats.totalCount == 4)
        #expect(stats.watchedCount == 1)
        #expect(stats.watchingCount == 1)
        #expect(stats.planToWatchCount == 1)
        #expect(stats.droppedCount == 1)
        #expect(stats.favoriteCount == 1)
        #expect(stats.movieCount == 1)
        #expect(stats.seriesCount == 1)
        #expect(stats.seasonCount == 2)
        #expect(stats.entriesWithNotesCount == 1)
        #expect(stats.totalRuntimeMinutes == 688)
        #expect(stats.watchedRuntimeMinutes == 100)
        #expect(stats.plannedRuntimeMinutes == 300)
    }

    @Test func testLibraryEntrySnapshotIncludesEpisodeProgressSummary() {
        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 501,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Series",
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 504,
                        seasonNumber: 1,
                        title: "Season 1",
                        episodeCount: 12
                    ),
                    AnimeEntrySeasonSummary(
                        id: 502,
                        seasonNumber: 2,
                        title: "Season 2",
                        episodeCount: 12
                    )
                ]
            )
        )
        series.setWatchStatus(.watching)
        series.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 12)
        series.setEpisodeProgress(seasonNumber: 2, watchedThroughEpisode: 5)

        let seriesSnapshot = LibraryEntrySnapshot(entry: series)
        #expect(seriesSnapshot.episodeProgressLabel == "S2E5")
        #expect(seriesSnapshot.episodeProgressFraction == 17.0 / 24.0)

        series.setEpisodeProgress(seasonNumber: 0, watchedThroughEpisode: 1)
        let seriesSnapshotAfterSpecialsAttempt = LibraryEntrySnapshot(entry: series)
        #expect(seriesSnapshotAfterSpecialsAttempt.episodeProgressLabel == "S2E5")
        #expect(seriesSnapshotAfterSpecialsAttempt.episodeProgressFraction == 17.0 / 24.0)

        let season = AnimeEntry(
            name: "Season 2",
            type: .season(seasonNumber: 2, parentSeriesID: 501),
            tmdbID: 503,
            detail: AnimeEntryDetail(language: "en-US", title: "Season 2", episodeCount: 12)
        )
        season.setWatchStatus(.watching)
        season.setEpisodeProgress(seasonNumber: 2, watchedThroughEpisode: 3)
        let seasonSnapshot = LibraryEntrySnapshot(entry: season)
        #expect(seasonSnapshot.episodeProgressLabel == "EP3")
        #expect(seasonSnapshot.episodeProgressFraction == 0.25)

        let movie = AnimeEntry.template(id: 503)
        movie.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 2)
        #expect(LibraryEntrySnapshot(entry: movie).episodeProgressLabel == nil)
        #expect(LibraryEntrySnapshot(entry: movie).episodeProgressFraction == nil)
    }

    @Test func testLibraryEntrySnapshotSeriesAggregateRequiresRefreshedParentSeasonCounts() {
        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 511,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Series",
                seasons: [
                    AnimeEntrySeasonSummary(id: 512, seasonNumber: 1, title: "Season 1"),
                    AnimeEntrySeasonSummary(id: 513, seasonNumber: 2, title: "Season 2")
                ]
            )
        )

        series.setWatchStatus(.watching)
        series.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 12)
        series.setEpisodeProgress(seasonNumber: 2, watchedThroughEpisode: 5)

        let staleSnapshot = LibraryEntrySnapshot(entry: series)
        #expect(staleSnapshot.episodeProgressLabel == "S2E5")
        #expect(staleSnapshot.episodeProgressFraction == nil)

        series.detail = AnimeEntryDetail(
            language: "en-US",
            title: "Series",
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 512,
                    seasonNumber: 1,
                    title: "Season 1",
                    episodeCount: 12
                ),
                AnimeEntrySeasonSummary(
                    id: 513,
                    seasonNumber: 2,
                    title: "Season 2",
                    episodeCount: 12
                )
            ]
        )

        let refreshedSnapshot = LibraryEntrySnapshot(entry: series)
        #expect(refreshedSnapshot.episodeProgressLabel == "S2E5")
        #expect(refreshedSnapshot.episodeProgressFraction == 17.0 / 24.0)
    }

    @Test func testLibraryEntrySnapshotSeriesAggregateIgnoresUnknownFutureSeasonCounts() {
        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 514,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Series",
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 515,
                        seasonNumber: 1,
                        title: "Season 1",
                        episodeCount: 12
                    ),
                    AnimeEntrySeasonSummary(id: 516, seasonNumber: 2, title: "Season 2")
                ]
            )
        )

        series.setWatchStatus(.watching)
        series.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 6)

        let snapshot = LibraryEntrySnapshot(entry: series)
        #expect(snapshot.episodeProgressLabel == "S1E6")
        #expect(snapshot.episodeProgressFraction == 0.5)
    }

    @Test func testLibraryEntrySnapshotSeriesAggregateExcludesSpecialsEvenIfStored() {
        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 521,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Series",
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 522,
                        seasonNumber: 0,
                        title: "Specials",
                        episodeCount: 2
                    ),
                    AnimeEntrySeasonSummary(
                        id: 523,
                        seasonNumber: 1,
                        title: "Season 1",
                        episodeCount: 12
                    ),
                    AnimeEntrySeasonSummary(
                        id: 524,
                        seasonNumber: 2,
                        title: "Season 2",
                        episodeCount: 12
                    )
                ]
            )
        )

        series.setWatchStatus(.watching)
        series.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 12)
        series.setEpisodeProgress(seasonNumber: 2, watchedThroughEpisode: 5)
        let specialsProgress = AnimeEntryEpisodeProgress(
            seasonNumber: 0,
            watchedThroughEpisode: 2,
            updatedAt: referenceDate(year: 2026, month: 5, day: 13)
        )
        specialsProgress.entry = series
        series.episodeProgresses.append(specialsProgress)

        let snapshot = LibraryEntrySnapshot(entry: series)
        #expect(snapshot.episodeProgressLabel == "S2E5")
        #expect(snapshot.episodeProgressFraction == 17.0 / 24.0)
    }

    @Test func testEpisodeProgressHelpersKeepStatusIndependentAndHandleSeasonPartitions() {
        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 601,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Series",
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 602,
                        seasonNumber: 2,
                        title: "Season 2",
                        episodeCount: 12
                    )
                ]
            )
        )

        series.setWatchStatus(.planToWatch)
        series.setEpisodeProgress(seasonNumber: 0, watchedThroughEpisode: 1)
        series.setEpisodeProgress(seasonNumber: 2, watchedThroughEpisode: 50)

        #expect(series.watchStatus == .planToWatch)
        #expect(series.orderedEpisodeProgresses.map(\.seasonNumber) == [2])
        #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 12)
        #expect(series.episodeProgressSummary(forSeason: 0).watchedThroughEpisode == 0)

        series.setWatchStatus(.watched)
        #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 12)

        let listedOnlySeason = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 604),
            tmdbID: 605,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Season 1",
                episodes: (1...5).map {
                    AnimeEntryEpisodeSummary(id: $0, episodeNumber: $0, title: "Episode \($0)")
                }
            )
        )
        listedOnlySeason.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 9)
        #expect(listedOnlySeason.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 5)
        listedOnlySeason.setWatchStatus(.watching)
        let listedOnlySeasonSnapshot = LibraryEntrySnapshot(entry: listedOnlySeason)
        #expect(listedOnlySeasonSnapshot.episodeProgressLabel == "EP5")
        #expect(listedOnlySeasonSnapshot.episodeProgressFraction == 1)

        let singleSeasonSeries = AnimeEntry(
            name: "Single Season Series",
            type: .series,
            tmdbID: 606,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Single Season Series",
                episodeCount: 5,
                seasons: [AnimeEntrySeasonSummary(id: 607, seasonNumber: 1, title: "Season 1")]
            )
        )
        singleSeasonSeries.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 9)
        #expect(singleSeasonSeries.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 5)
        singleSeasonSeries.setWatchStatus(.watching)
        let singleSeasonSeriesSnapshot = LibraryEntrySnapshot(entry: singleSeasonSeries)
        #expect(singleSeasonSeriesSnapshot.episodeProgressLabel == "S1E5")
        #expect(singleSeasonSeriesSnapshot.episodeProgressFraction == 1)

        let specialsOnlySeries = AnimeEntry(name: "Specials", type: .series, tmdbID: 607)
        specialsOnlySeries.setEpisodeProgress(seasonNumber: 0, watchedThroughEpisode: 1)
        let specialsSnapshot = LibraryEntrySnapshot(entry: specialsOnlySeries)
        #expect(specialsOnlySeries.episodeProgresses.isEmpty)
        #expect(specialsSnapshot.episodeProgressLabel == nil)
        #expect(specialsSnapshot.episodeProgressFraction == nil)

        let specialsSeason = AnimeEntry(
            name: "Specials Season",
            type: .season(seasonNumber: 0, parentSeriesID: 608),
            tmdbID: 609
        )
        specialsSeason.setEpisodeProgress(seasonNumber: 0, watchedThroughEpisode: 2)
        #expect(LibraryEntrySnapshot(entry: specialsSeason).episodeProgressLabel == nil)
        #expect(LibraryEntrySnapshot(entry: specialsSeason).episodeProgressFraction == nil)

        let movie = AnimeEntry.template(id: 603)
        movie.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 4)
        #expect(movie.episodeProgresses.isEmpty)
    }

    @Test func testLibraryEntrySnapshotHidesEpisodeProgressOutsideWatching() {
        let season = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 701),
            tmdbID: 702,
            detail: AnimeEntryDetail(language: "en-US", title: "Season 1", episodeCount: 12)
        )

        season.setEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 4)
        #expect(season.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 4)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressLabel == nil)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressFraction == nil)

        season.setWatchStatus(.watching)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressLabel == "EP4")
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressFraction == 4.0 / 12.0)

        season.setWatchStatus(.watched)
        #expect(season.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 4)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressLabel == nil)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressFraction == nil)

        season.setWatchStatus(.planToWatch)
        #expect(season.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 4)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressLabel == nil)
        #expect(LibraryEntrySnapshot(entry: season).episodeProgressFraction == nil)
    }
}
