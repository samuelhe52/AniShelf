//
//  LibraryAppIntentsTests.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import DataProvider
import Foundation
import Testing

@testable import MyAnimeList

@MainActor
struct LibraryAppIntentsTests {
    let defaults: UserDefaults
    let store: LibraryStore

    init() {
        let suiteName = "LibraryAppIntentsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: .episodeProgressTrackingEnabled)
        store = LibraryStore(
            dataProvider: DataProvider(inMemory: true),
            preferences: LibraryPreferences(defaults: defaults)
        )
    }

    private func makeContext(
        allowsLibraryActivity: Bool = true,
        hasTMDbAPIKey: Bool = true
    ) -> AppIntentLibraryContext {
        AppIntentLibraryContext(
            store: store,
            defaults: defaults,
            allowsLibraryActivity: { allowsLibraryActivity },
            hasTMDbAPIKey: { hasTMDbAPIKey }
        )
    }

    private func insert(_ entries: AnimeEntry...) throws {
        for entry in entries {
            try store.repository.newEntry(entry)
        }
        try store.refreshLibrary()
    }

    /// A visible season under a hidden parent series, as the app stores added seasons.
    private func makeSeason(
        episodeCount: Int = 12,
        watchStatus: AnimeEntry.WatchStatus = .watching
    ) -> (parent: AnimeEntry, season: AnimeEntry) {
        let parent = AnimeEntry(name: "Frieren", type: .series, tmdbID: 100)
        parent.setDisplayState(false)
        let season = AnimeEntry(
            name: "Frieren Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 100),
            tmdbID: 101,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Season 1",
                status: "Ended",
                episodeCount: episodeCount
            )
        )
        season.parentSeriesEntry = parent
        season.setWatchStatus(watchStatus)
        return (parent, season)
    }

    // MARK: - Entity and query

    @Test func seasonEntityUsesParentNameAndStableIdentityExcludingHiddenParent() throws {
        let (parent, season) = makeSeason()
        try insert(parent, season)
        let context = makeContext()

        let entities = try context.entities(for: [season.libraryIdentity.rawID, parent.libraryIdentity.rawID])

        let entity = try #require(entities.only)
        #expect(LibraryEntryIdentity(rawID: entity.id) == season.libraryIdentity)
        #expect(entity.name == "Frieren")
        let seasonLabel = try #require(LibraryEntrySnapshot(entry: season).secondaryMetadata)
        #expect(entity.subtitle.hasPrefix("\(seasonLabel) · "))
        #expect(entity.alternateNames.contains("Frieren Season 1"))
        #expect(entity.kind == .season)
        #expect(entity.seasonNumber == 1)
    }

    @Test func unknownMalformedAndDeletedIdentifiersResolveToNothing() throws {
        let movie = makeLibraryEntry(name: "Movie", tmdbID: 1, daySaved: 1)
        try insert(movie)
        let context = makeContext()
        let movieID = movie.libraryIdentity.rawID
        store.deleteEntry(movie)

        #expect(try context.entities(for: [movieID, "movie:999", "not-an-id"]).isEmpty)
        #expect(throws: LibraryIntentError.entryNotFound) {
            try context.toggleFavorite(forEntryID: movieID)
        }
    }

    @Test func stringSearchRanksNamesBeforeOverviewsAndIgnoresNotes() throws {
        let overviewMatch = makeLibraryEntry(name: "Another Story", tmdbID: 1, daySaved: 2)
        overviewMatch.overview = "A story about a mage."
        let nameMatch = makeLibraryEntry(name: "The Mage", tmdbID: 2, daySaved: 1)
        let notesMatch = makeLibraryEntry(name: "Unrelated", tmdbID: 3, daySaved: 3)
        notesMatch.notes = "Mage notes"
        try insert(overviewMatch, nameMatch, notesMatch)

        let results = try makeContext().entities(matching: "mage")

        #expect(results.map(\.name) == ["The Mage", "Another Story"])
    }

    @Test func propertyQueryFiltersSortsAndLimits() throws {
        try insert(
            makeLibraryEntry(name: "Bravo", tmdbID: 1, watchStatus: .watched, daySaved: 1, score: 5, favorite: true),
            makeLibraryEntry(name: "Alpha", tmdbID: 2, watchStatus: .watched, daySaved: 2, score: 4),
            makeLibraryEntry(name: "Charlie", tmdbID: 3, watchStatus: .watched, daySaved: 3, score: 2),
            makeLibraryEntry(name: "Delta", tmdbID: 4, watchStatus: .dropped, daySaved: 4, score: 5)
        )
        let context = makeContext()
        let byName = [LibraryEntrySortDescriptor(key: .name, ascending: true)]

        let watchedAndScored = try context.entities(
            matching: [.status(.watched), .scoreAtLeast(4)],
            requiringAll: true,
            sortedBy: byName,
            limit: nil
        )
        #expect(watchedAndScored.map(\.name) == ["Alpha", "Bravo"])

        let favoriteOrDropped = try context.entities(
            matching: [.favorite(true), .status(.dropped)],
            requiringAll: false,
            sortedBy: [LibraryEntrySortDescriptor(key: .dateSaved, ascending: false)],
            limit: 1
        )
        #expect(favoriteOrDropped.map(\.name) == ["Delta"])

        let notWatchedByName = try context.entities(
            matching: [.statusNot(.watched), .nameContains("del")],
            requiringAll: true,
            sortedBy: byName,
            limit: nil
        )
        #expect(notWatchedByName.map(\.name) == ["Delta"])
    }

    @Test func suggestionsListWatchingEntriesFirst() throws {
        let watching = makeLibraryEntry(name: "Watching", tmdbID: 1, watchStatus: .watching, daySaved: 1)
        let newest = makeLibraryEntry(name: "Newest", tmdbID: 2, daySaved: 3)
        let older = makeLibraryEntry(name: "Older", tmdbID: 3, daySaved: 2)
        try insert(watching, newest, older)

        #expect(try makeContext().suggestedEntities().map(\.name) == ["Watching", "Newest", "Older"])
    }

    // MARK: - Gates

    @Test func blockedLibraryRefusesWithTheGateReason() throws {
        let movie = makeLibraryEntry(name: "Movie", tmdbID: 1, daySaved: 1)
        try insert(movie)

        #expect(throws: LibraryIntentError.recoveryPending) {
            try makeContext(allowsLibraryActivity: false).suggestedEntities()
        }
        #expect(throws: LibraryIntentError.setupIncomplete) {
            try makeContext(hasTMDbAPIKey: false).entities(for: [movie.libraryIdentity.rawID])
        }

        try insert(makeLibraryEntry(name: "Movie Copy", tmdbID: 1, daySaved: 2))
        #expect(store.requiresDuplicateRepair)
        #expect(throws: LibraryIntentError.duplicateRepairRequired) {
            try makeContext().setWatchStatus(.watched, forEntryID: movie.libraryIdentity.rawID)
        }
    }

    // MARK: - Tracking rules

    @Test func settingStatusAppliesTheDateSuggestion() throws {
        let movie = makeLibraryEntry(name: "Movie", tmdbID: 1, daySaved: 1)
        try insert(movie)
        let context = makeContext()
        let now = referenceDate(year: 2026, month: 10, day: 14)

        let entity = try context.setWatchStatus(.watching, forEntryID: movie.libraryIdentity.rawID, now: now)

        #expect(entity.status == .watching)
        #expect(movie.dateStarted == now)
        #expect(movie.dateFinished == nil)
    }

    @Test func watchingTheLastEpisodeMarksWatchedWithAFinishDate() throws {
        let (parent, season) = makeSeason(episodeCount: 2)
        season.isRewatching = true
        try insert(parent, season)
        let context = makeContext()
        let id = season.libraryIdentity.rawID
        let now = referenceDate(year: 2026, month: 10, day: 14)

        let first = try context.markNextEpisodeWatched(forEntryID: id, now: now)
        #expect(first.watchedThroughEpisode == 1)
        #expect(!first.markedWatched)

        let last = try context.markNextEpisodeWatched(forEntryID: id, now: now)
        #expect(last.watchedThroughEpisode == 2)
        #expect(last.markedWatched)
        #expect(season.watchStatus == .watched)
        #expect(season.dateFinished == now)
        #expect(season.rewatchCount == 1)

        #expect(throws: LibraryIntentError.allEpisodesWatched) {
            try context.markNextEpisodeWatched(forEntryID: id, now: now)
        }
    }

    @Test func nextEpisodeMovesToTheNextUnfinishedSeasonOfASeries() throws {
        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 200,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Series",
                status: "Ended",
                seasons: [
                    AnimeEntrySeasonSummary(id: 201, seasonNumber: 1, title: "Season 1", episodeCount: 1),
                    AnimeEntrySeasonSummary(id: 202, seasonNumber: 2, title: "Season 2", episodeCount: 3),
                ]
            )
        )
        series.setWatchStatus(.watching)
        try insert(series)
        series.updateEpisodeProgress(seasonNumber: 1, watchedThroughEpisode: 1)

        let outcome = try makeContext().markNextEpisodeWatched(forEntryID: series.libraryIdentity.rawID)

        #expect(outcome.seasonNumber == 2)
        #expect(outcome.watchedThroughEpisode == 1)
        #expect(series.watchStatus == .watching)
    }

    @Test func episodeAndScoreActionsRespectEntryTypeAndSettings() throws {
        let movie = makeLibraryEntry(name: "Movie", tmdbID: 1, daySaved: 1)
        try insert(movie)
        let id = movie.libraryIdentity.rawID
        let context = makeContext()

        #expect(throws: LibraryIntentError.notEpisodic) {
            try context.setEpisodeProgress(3, season: nil, forEntryID: id)
        }

        defaults.set(false, forKey: .episodeProgressTrackingEnabled)
        #expect(throws: LibraryIntentError.episodeTrackingDisabled) {
            try context.markNextEpisodeWatched(forEntryID: id)
        }

        #expect(try context.setScore(4, forEntryID: id).score == 4)
        #expect(try context.setScore(0, forEntryID: id).score == nil)
        defaults.set(false, forKey: .libraryScoringEnabled)
        #expect(throws: LibraryIntentError.scoringDisabled) {
            try context.setScore(3, forEntryID: id)
        }
    }

    // MARK: - Spotlight

    @Test func spotlightPlanReplacesEverythingOnFirstPassThenDiffs() {
        let current = ["a": 1, "b": 2, "c": 3]

        let firstPass = LibrarySpotlightIndexer.plan(current: current, indexed: nil)
        #expect(firstPass.replacesAll)
        #expect(firstPass.idsToIndex == ["a", "b", "c"])

        let diff = LibrarySpotlightIndexer.plan(current: current, indexed: ["a": 1, "b": 9, "d": 4])
        #expect(!diff.replacesAll)
        #expect(diff.idsToIndex == ["b", "c"])
        #expect(diff.idsToDelete == ["d"])

        #expect(LibrarySpotlightIndexer.plan(current: current, indexed: current).isEmpty)
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}
