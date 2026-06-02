//
//  LibraryEntrySyncTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync

struct LibraryEntrySyncTests {
    @Test func deterministicIdentityUsesEntryShapeAndTMDbIDs() {
        let movie = AnimeEntry(name: "Movie", type: .movie, tmdbID: 11)
        let series = AnimeEntry(name: "Series", type: .series, tmdbID: 22)
        let season = AnimeEntry(
            name: "Season",
            type: .season(seasonNumber: 3, parentSeriesID: 22),
            tmdbID: 33
        )

        #expect(movie.syncIdentity.rawID == "movie:11")
        #expect(series.syncIdentity.rawID == "series:22")
        #expect(season.syncIdentity.rawID == "season:22:3:33")
    }

    @Test func snapshotApplyRoundTripsUserFieldsAndPreservesMetadata() throws {
        let source = AnimeEntry(
            name: "Remote Name",
            overview: "Remote overview",
            type: .series,
            posterURL: URL(string: "https://example.com/custom.jpg"),
            backdropURL: URL(string: "https://example.com/backdrop.jpg"),
            tmdbID: 101,
            dateSaved: referenceDate(year: 2026, month: 5, day: 10),
            score: 5,
            usingCustomPoster: true
        )
        source.setWatchStatus(.watching)
        source.dateStarted = referenceDate(year: 2026, month: 5, day: 11)
        source.favorite = true
        source.notes = "Remote notes"
        source.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 12)
        source.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 12)
        source.applyEpisodeProgressSnapshot(
            seasonNumber: 1,
            watchedThroughEpisode: 7, updatedAt: referenceDate(year: 2026, month: 5, day: 12)
        )

        let snapshot = LibraryEntrySyncSnapshot(entry: source)
        let local = AnimeEntry(
            name: "Local Name",
            overview: "Local overview",
            type: .series,
            posterURL: URL(string: "https://example.com/original.jpg"),
            backdropURL: URL(string: "https://example.com/local-backdrop.jpg"),
            tmdbID: 101,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        local.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 1)
        local.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 1)

        try local.applySyncSnapshot(snapshot, now: referenceDate(year: 2026, month: 5, day: 13))

        #expect(local.name == "Local Name")
        #expect(local.overview == "Local overview")
        #expect(local.backdropURL == URL(string: "https://example.com/local-backdrop.jpg"))
        #expect(local.watchStatus == .watching)
        #expect(local.dateStarted == referenceDate(year: 2026, month: 5, day: 11))
        #expect(local.score == 5)
        #expect(local.favorite)
        #expect(local.notes == "Remote notes")
        #expect(local.usingCustomPoster)
        #expect(local.posterURL == URL(string: "https://example.com/custom.jpg"))
        #expect(local.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 7)
    }

    @Test func snapshotReadsPersistedEntryClocks() {
        let entry = AnimeEntry(name: "Local", type: .series, tmdbID: 151)
        entry.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 3)
        entry.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 4)

        let snapshot = LibraryEntrySyncSnapshot(entry: entry)

        #expect(snapshot.libraryUpdatedAt == referenceDate(year: 2026, month: 5, day: 3))
        #expect(snapshot.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 4))
    }

    @Test func nilClockSnapshotDoesNotOverwriteLocalTrackingFields() throws {
        let local = AnimeEntry(name: "Local", type: .series, tmdbID: 175, score: 7)
        local.setWatchStatus(.watching)
        local.favorite = true
        local.notes = "Keep local"

        let remote = LibraryEntrySyncSnapshot(
            identity: local.syncIdentity,
            tmdbID: local.tmdbID,
            parentSeriesID: nil,
            seasonNumber: nil,
            entryType: .series,
            onDisplay: true,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1),
            watchStatus: .dropped,
            dateStarted: nil,
            dateFinished: nil,
            isDateTrackingEnabled: true,
            score: 1,
            favorite: false,
            notes: "Remote stale",
            usingCustomPoster: false,
            customPosterURL: nil,
            episodeProgresses: [],
            libraryUpdatedAt: nil,
            trackingUpdatedAt: nil
        )

        try local.applySyncSnapshot(remote)

        #expect(local.watchStatus == .watching)
        #expect(local.score == 7)
        #expect(local.favorite)
        #expect(local.notes == "Keep local")
        #expect(local.trackingUpdatedAt == nil)
    }

    @Test func staleFavoriteToggleDoesNotWipeNewerEpisodeProgress() throws {
        var staleFavorite = makeSnapshot(
            tmdbID: 201,
            trackingDay: 3,
            favorite: false,
            progress: []
        )
        staleFavorite.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 3)

        let newerProgress = makeSnapshot(
            tmdbID: 201,
            trackingDay: 2,
            favorite: true,
            progress: [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 8,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 9)
                )
            ]
        )

        let merged = try newerProgress.merged(with: staleFavorite)

        #expect(!merged.favorite)
        #expect(
            merged.episodeProgresses == [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 8,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 9)
                )
            ])
    }

    @Test func duplicateSnapshotsWithSameIdentityConverge() throws {
        let local = makeSnapshot(
            tmdbID: 301,
            trackingDay: 6,
            favorite: true,
            progress: [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 4,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 6)
                )
            ]
        )
        let remote = local

        let localMerged = try local.merged(with: remote)
        let remoteMerged = try remote.merged(with: local)

        #expect(localMerged == remoteMerged)
    }

    @Test func newerTrackingStateWinsOverStaleTrackingState() throws {
        let stale = makeSnapshot(
            tmdbID: 401,
            trackingDay: 5,
            favorite: false,
            notes: "Old",
            score: 2
        )
        let fresh = makeSnapshot(
            tmdbID: 401,
            trackingDay: 8,
            favorite: true,
            notes: "New",
            score: 4
        )

        let merged = try stale.merged(with: fresh)

        #expect(merged.favorite)
        #expect(merged.notes == "New")
        #expect(merged.score == 4)
        #expect(merged.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 8))
    }

    @Test func nonNilClocksBeatNilAndNilTiesKeepLocalTrackingState() throws {
        var local = makeSnapshot(
            tmdbID: 421,
            favorite: true,
            notes: "Local",
            score: 5
        )
        local.libraryUpdatedAt = nil
        local.trackingUpdatedAt = nil

        var remoteNil = makeSnapshot(
            tmdbID: 421,
            favorite: false,
            notes: "Remote nil",
            score: 1
        )
        remoteNil.libraryUpdatedAt = nil
        remoteNil.trackingUpdatedAt = nil

        let nilTieMerged = try local.merged(with: remoteNil)

        #expect(nilTieMerged.favorite)
        #expect(nilTieMerged.notes == "Local")
        #expect(nilTieMerged.score == 5)
        #expect(nilTieMerged.libraryUpdatedAt == nil)
        #expect(nilTieMerged.trackingUpdatedAt == nil)

        var remoteFresh = remoteNil
        remoteFresh.trackingUpdatedAt = referenceDate(year: 2026, month: 5, day: 9)
        remoteFresh.favorite = false
        remoteFresh.notes = "Remote fresh"
        remoteFresh.score = 2

        let freshMerged = try local.merged(with: remoteFresh)

        #expect(!freshMerged.favorite)
        #expect(freshMerged.notes == "Remote fresh")
        #expect(freshMerged.score == 2)
        #expect(freshMerged.trackingUpdatedAt == referenceDate(year: 2026, month: 5, day: 9))
    }

    @Test func decodedSnapshotNormalizesDuplicateEpisodeProgressRows() throws {
        let base = makeSnapshot(tmdbID: 451)
        let encoded = try JSONEncoder().encode(base)
        var payload = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        payload["episodeProgresses"] = [
            [
                "seasonNumber": 1,
                "watchedThroughEpisode": 2,
                "updatedAt": referenceDate(year: 2026, month: 5, day: 3).timeIntervalSinceReferenceDate
            ],
            [
                "seasonNumber": 1,
                "watchedThroughEpisode": 5,
                "updatedAt": referenceDate(year: 2026, month: 5, day: 4).timeIntervalSinceReferenceDate
            ]
        ]

        let decoded = try JSONDecoder().decode(
            LibraryEntrySyncSnapshot.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        #expect(
            decoded.episodeProgresses == [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 5,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 4)
                )
            ])
    }

    @Test func episodeProgressMergesPerSeason() throws {
        let local = makeSnapshot(
            tmdbID: 501,
            progress: [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 7)
                ),
                .init(
                    seasonNumber: 2,
                    watchedThroughEpisode: 2,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 4)
                )
            ]
        )
        let remote = makeSnapshot(
            tmdbID: 501,
            progress: [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 5,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 7)
                ),
                .init(
                    seasonNumber: 3,
                    watchedThroughEpisode: 1,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 6)
                )
            ]
        )

        let merged = try local.merged(with: remote)

        #expect(merged.episodeProgresses.map(\.seasonNumber) == [1, 2, 3])
        #expect(merged.episodeProgresses.first { $0.seasonNumber == 1 }?.watchedThroughEpisode == 5)
        #expect(merged.episodeProgresses.first { $0.seasonNumber == 2 }?.watchedThroughEpisode == 2)
        #expect(merged.episodeProgresses.first { $0.seasonNumber == 3 }?.watchedThroughEpisode == 1)
    }

    @Test func tombstoneAppliesOnlyWhenNewerThanLocalClocks() throws {
        let local = AnimeEntry(
            name: "Local",
            type: .series,
            tmdbID: 601,
            dateSaved: referenceDate(year: 2026, month: 5, day: 10)
        )
        local.applyEpisodeProgressSnapshot(
            seasonNumber: 1,
            watchedThroughEpisode: 4, updatedAt: referenceDate(year: 2026, month: 5, day: 11)
        )
        local.libraryUpdatedAt = referenceDate(year: 2026, month: 5, day: 10)

        let staleTombstone = LibraryEntrySyncTombstone(
            entry: local,
            deletedAt: referenceDate(year: 2026, month: 5, day: 9)
        )
        try local.applySyncTombstone(staleTombstone)
        #expect(local.onDisplay)

        let freshTombstone = LibraryEntrySyncTombstone(
            entry: local,
            deletedAt: referenceDate(year: 2026, month: 5, day: 12)
        )
        try local.applySyncTombstone(freshTombstone)
        #expect(!local.onDisplay)
    }

    @Test func tombstoneWithNilLocalClocksStillRespectsDateSaved() throws {
        let local = AnimeEntry(
            name: "Migrated Local",
            type: .series,
            tmdbID: 625,
            dateSaved: referenceDate(year: 2026, month: 5, day: 10)
        )

        let staleTombstone = LibraryEntrySyncTombstone(
            entry: local,
            deletedAt: referenceDate(year: 2026, month: 5, day: 9)
        )
        try local.applySyncTombstone(staleTombstone)
        #expect(local.onDisplay)

        let freshTombstone = LibraryEntrySyncTombstone(
            entry: local,
            deletedAt: referenceDate(year: 2026, month: 5, day: 11)
        )
        try local.applySyncTombstone(freshTombstone)
        #expect(!local.onDisplay)
    }

    @Test func disablingCustomPosterClearsStaleCustomPosterURL() throws {
        let local = AnimeEntry(
            name: "Local",
            type: .series,
            posterURL: URL(string: "https://example.com/custom.jpg"),
            tmdbID: 650,
            dateSaved: referenceDate(year: 2026, month: 5, day: 10),
            usingCustomPoster: true
        )

        let snapshot = LibraryEntrySyncSnapshot(
            identity: local.syncIdentity,
            tmdbID: local.tmdbID,
            parentSeriesID: nil,
            seasonNumber: nil,
            entryType: .series,
            onDisplay: true,
            dateSaved: local.dateSaved,
            watchStatus: local.watchStatus,
            dateStarted: local.dateStarted,
            dateFinished: local.dateFinished,
            isDateTrackingEnabled: local.isDateTrackingEnabled,
            score: local.score,
            favorite: local.favorite,
            notes: local.notes,
            usingCustomPoster: false,
            customPosterURL: nil,
            episodeProgresses: [],
            libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: 10),
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 12)
        )

        try local.applySyncSnapshot(snapshot)

        #expect(!local.usingCustomPoster)
        #expect(local.posterURL == nil)
    }

    @Test func identityMismatchRejectsMergeAndApply() throws {
        let local = makeSnapshot(tmdbID: 701)
        let remote = makeSnapshot(tmdbID: 702)
        #expect(throws: LibraryEntrySyncSnapshot.MergeError.self) {
            _ = try local.merged(with: remote)
        }

        let entry = AnimeEntry(name: "Local", type: .movie, tmdbID: 701)
        #expect(throws: LibraryEntrySyncSnapshot.MergeError.self) {
            try entry.applySyncSnapshot(remote)
        }
    }

    private func makeSnapshot(
        tmdbID: Int,
        libraryDay: Int = 1,
        trackingDay: Int = 1,
        favorite: Bool = false,
        notes: String = "",
        score: Int? = nil,
        progress: [LibraryEntrySyncSnapshot.EpisodeProgress] = []
    ) -> LibraryEntrySyncSnapshot {
        LibraryEntrySyncSnapshot(
            identity: LibraryEntrySyncIdentity(entryType: .series, tmdbID: tmdbID),
            tmdbID: tmdbID,
            parentSeriesID: nil,
            seasonNumber: nil,
            entryType: .series,
            onDisplay: true,
            dateSaved: referenceDate(year: 2026, month: 5, day: libraryDay),
            watchStatus: .watching,
            dateStarted: nil,
            dateFinished: nil,
            isDateTrackingEnabled: true,
            score: score,
            favorite: favorite,
            notes: notes,
            usingCustomPoster: false,
            customPosterURL: nil,
            episodeProgresses: progress,
            libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: libraryDay),
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: trackingDay)
        )
    }
}

fileprivate func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}
