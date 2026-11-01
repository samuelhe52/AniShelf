//
//  EpisodeNoteTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/26.
//

import DataProvider
import Foundation
import LibrarySync
import Testing

struct EpisodeNoteTests {
    private let first = EpisodeNoteAnchor(seasonNumber: 1, episodeNumber: 4)
    private let special = EpisodeNoteAnchor(seasonNumber: 0, episodeNumber: 99)

    @Test func independentEditsAndDeletionConvergeWithoutChangingOverallNotes() throws {
        let local = AnimeEntry(name: "Series", type: .series, tmdbID: 1)
        local.updateNotes("Overall", at: Date(timeIntervalSince1970: 10))
        local.updateEpisodeNote(at: first, text: "First", date: Date(timeIntervalSince1970: 20))
        let stale = LibraryEntrySyncSnapshot(entry: local)
        let remote = AnimeEntry(name: "Series", type: .series, tmdbID: 1)
        try remote.applyInitialSyncSnapshot(stale)
        remote.updateEpisodeNote(at: special, text: "Offline special", date: Date(timeIntervalSince1970: 30))
        local.updateEpisodeNote(at: first, text: "", date: Date(timeIntervalSince1970: 40))
        let lhs = LibraryEntrySyncSnapshot(entry: local)
        let rhs = LibraryEntrySyncSnapshot(entry: remote)
        let merged = try lhs.merged(with: rhs)
        #expect(try merged == rhs.merged(with: lhs))
        #expect(merged.notes == "Overall")
        #expect(merged.episodeNotes.count == 2)
        #expect(merged.episodeNotes.first { $0.anchor == first }?.isEmpty == true)
        #expect(merged.episodeNotes.first { $0.anchor == special }?.text == "Offline special")
        #expect(merged.latestSyncClock == Date(timeIntervalSince1970: 40))
        try local.applySyncSnapshot(rhs)
        #expect(local.episodeNote(at: first)?.isEmpty == true)
        #expect(local.episodeNote(at: special)?.text == "Offline special")
        #expect(try merged.merged(with: stale).episodeNotes == merged.episodeNotes)
    }

    @Test func equalClockDeletionWinsAndInvalidAnchorsAreDropped() {
        let date = Date(timeIntervalSince1970: 10)
        let text = EpisodeNote(anchor: first, text: "Text", updatedAt: date)
        let deleted = EpisodeNote(anchor: first, text: "", updatedAt: date)
        let invalid = EpisodeNote(anchor: .init(seasonNumber: -1, episodeNumber: 2), text: "Invalid", updatedAt: date)
        #expect(EpisodeNote.merged([text, invalid], [deleted]) == [deleted])
        #expect(EpisodeNote.merged([deleted], [text]) == [deleted])
    }

    @Test func seasonSnapshotsRestoreOnlyTheirSeasonAndKeepNotesAcrossRewatch() throws {
        let parent = AnimeEntry(name: "Series", type: .series, tmdbID: 1)
        let season = AnimeEntry(name: "Season", type: .season(seasonNumber: 1, parentSeriesID: 1), tmdbID: 2)
        #expect(!season.updateEpisodeNote(at: first, text: "No owner"))
        season.parentSeriesEntry = parent
        season.updateEpisodeNote(at: first, text: "Original")
        parent.updateEpisodeNote(at: special, text: "Special")
        let original = UserEntryInfo(from: season)
        season.updateEpisodeNote(at: first, text: "Changed")
        let rewriteClock = try #require(parent.episodeNote(at: first)?.updatedAt)
        season.updateUserInfo(from: original)
        #expect(parent.episodeNote(at: first)?.text == "Original")
        #expect(try #require(parent.episodeNote(at: first)?.updatedAt) > rewriteClock)
        #expect(parent.episodeNote(at: special)?.text == "Special")
        #expect(season.storedEpisodeNotes.isEmpty)
        #expect(!UserEntryInfo(from: season).isEmpty)
        #expect(UserEntryInfo(from: season).isSemanticallyEquivalent(to: original))
        season.updateWatchStatus(.watching)
        season.startRewatch()
        #expect(season.episodeNote(at: first)?.text == "Original")
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: JSONEncoder().encode(original))
        #expect(decoded.episodeNotes == original.episodeNotes)
    }

    @Test func sharedParentNotesProtectParentButDoNotBlockSeasonDeletion() throws {
        let parent = AnimeEntry(name: "Series", type: .series, tmdbID: 1, dateSaved: Date(timeIntervalSince1970: 10))
        let season = AnimeEntry(
            name: "Season", type: .season(seasonNumber: 1, parentSeriesID: 1), tmdbID: 2,
            dateSaved: Date(timeIntervalSince1970: 10))
        season.parentSeriesEntry = parent
        season.updateEpisodeNote(at: first, text: "Retain on parent", date: Date(timeIntervalSince1970: 20))
        try season.applySyncTombstone(.init(entry: season, deletedAt: Date(timeIntervalSince1970: 15)))
        try parent.applySyncTombstone(.init(entry: parent, deletedAt: Date(timeIntervalSince1970: 15)))
        #expect(!season.onDisplay)
        #expect(parent.onDisplay)
        #expect(parent.episodeNote(at: first)?.text == "Retain on parent")
    }

    @Test func cloudPayloadRoundTripsNotesAndRejectsCorruption() throws {
        let entry = AnimeEntry(name: "Series", type: .series, tmdbID: 1)
        entry.updateEpisodeNote(at: special, text: "Special")
        let snapshot = LibraryEntrySyncSnapshot(entry: entry)
        let client = CloudLibrarySyncClient()
        let record = try client.record(from: snapshot)
        #expect(try client.snapshot(from: record).episodeNotes == snapshot.episodeNotes)
        record["episodeNotes"] = Data("broken".utf8)
        #expect(throws: CloudLibrarySyncDecodeError.corruptEpisodeNotesPayload) { try client.snapshot(from: record) }
        record["episodeNotes"] = nil
        record["schemaVersion"] = 3
        #expect(try client.snapshot(from: record).episodeNotes.isEmpty)
    }
}
