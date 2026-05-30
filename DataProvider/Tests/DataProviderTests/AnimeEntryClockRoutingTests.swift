//
//  AnimeEntryClockRoutingTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Foundation
import Testing

@testable import DataProvider

@Test func trackingUpdateHelpersStampOnlyTrackingClock() async throws {
    let entry = AnimeEntry.template()
    let timestamp = referenceDate(day: 1)

    entry.updateFavorite(true, at: timestamp)
    #expect(entry.favorite)
    #expect(entry.trackingUpdatedAt == timestamp)
    #expect(entry.libraryUpdatedAt == nil)

    let scoreTimestamp = referenceDate(day: 2)
    entry.updateScore(4, at: scoreTimestamp)
    #expect(entry.score == 4)
    #expect(entry.trackingUpdatedAt == scoreTimestamp)
    #expect(entry.libraryUpdatedAt == nil)
}

@Test func noOpTrackingUpdateHelpersDoNotStampTrackingClock() async throws {
    let entry = AnimeEntry.template()
    let timestamp = referenceDate(day: 6)

    #expect(!entry.updateWatchStatus(.planToWatch, at: timestamp))
    #expect(!entry.updateFavorite(false, at: timestamp))
    #expect(!entry.updateScore(nil, at: timestamp))
    #expect(entry.trackingUpdatedAt == nil)
    #expect(entry.libraryUpdatedAt == nil)
}

@Test func libraryUpdateHelpersStampOnlyLibraryClock() async throws {
    let entry = AnimeEntry.template()
    let timestamp = referenceDate(day: 3)

    entry.updateDisplayState(false, at: timestamp)
    #expect(!entry.onDisplay)
    #expect(entry.libraryUpdatedAt == timestamp)
    #expect(entry.trackingUpdatedAt == nil)
}

@Test func rawUserInfoMutationHelpersDoNotStampClocks() async throws {
    let entry = AnimeEntry.template()
    let source = AnimeEntry.template(id: 1)
    source.setWatchStatus(.watched)
    source.setScore(5)
    source.favorite = true
    source.notes = "Imported"
    let userInfo = UserEntryInfo(from: source)

    entry.updateUserInfo(from: userInfo)

    #expect(entry.watchStatus == .watched)
    #expect(entry.score == 5)
    #expect(entry.favorite)
    #expect(entry.notes == "Imported")
    #expect(entry.libraryUpdatedAt == nil)
    #expect(entry.trackingUpdatedAt == nil)
}

@Test func userActionUserInfoHelperStampsTrackingClock() async throws {
    let entry = AnimeEntry.template()
    let timestamp = referenceDate(day: 4)
    let source = AnimeEntry.template(id: 1)
    source.setWatchStatus(.watching)
    source.favorite = true
    source.notes = "Pasted"
    let userInfo = UserEntryInfo(from: source)

    entry.updateUserInfoFromUserAction(userInfo, at: timestamp)

    #expect(entry.watchStatus == .watching)
    #expect(entry.favorite)
    #expect(entry.notes == "Pasted")
    #expect(entry.trackingUpdatedAt == timestamp)
    #expect(entry.libraryUpdatedAt == nil)
}

@Test func userEpisodeProgressHelperStampsTrackingClockAndProgressTimestamp() async throws {
    let entry = AnimeEntry(name: "Series", type: .series, tmdbID: 200)
    let timestamp = referenceDate(day: 5)

    let didUpdate = entry.updateEpisodeProgress(
        seasonNumber: 1,
        watchedThroughEpisode: 3,
        at: timestamp
    )

    #expect(didUpdate)
    #expect(entry.episodeProgress(forSeason: 1)?.watchedThroughEpisode == 3)
    #expect(entry.episodeProgress(forSeason: 1)?.updatedAt == timestamp)
    #expect(entry.trackingUpdatedAt == timestamp)
    #expect(entry.libraryUpdatedAt == nil)

    let noChangeTimestamp = referenceDate(day: 6)
    let didNoOp = entry.updateEpisodeProgress(
        seasonNumber: 1,
        watchedThroughEpisode: 3,
        at: noChangeTimestamp
    )

    #expect(!didNoOp)
    #expect(entry.episodeProgress(forSeason: 1)?.updatedAt == timestamp)
    #expect(entry.trackingUpdatedAt == timestamp)
}

@Test func libraryCreationHelperDoesNotStampTrackingClock() async throws {
    let entry = AnimeEntry.template()
    let timestamp = referenceDate(day: 7)

    entry.markCreatedForLibrary(at: timestamp)

    #expect(entry.libraryUpdatedAt == timestamp)
    #expect(entry.trackingUpdatedAt == nil)
}

fileprivate func referenceDate(day: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: day))!
}
