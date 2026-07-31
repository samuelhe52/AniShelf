//
//  EntryDetailViewModelTests+EpisodePresentation.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension EntryDetailViewModelTests {
    @Test func testEpisodePresentationMarksWatchedEpisodesFromContiguousProgress() {
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                3,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                4,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
    }

    @Test func testEpisodePresentationIgnoresNonTrackableProgress() {
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 0,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 0,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 0,
                    watchedThroughEpisode: 3,
                    episodeCount: 12,
                    updatedAt: .distantPast
                )
            )
        )
    }

    @Test func testEpisodePresentationStopsAtWatchedThroughEpisode() {
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                4,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 4,
                    episodeCount: 4,
                    updatedAt: .distantPast
                )
            )
        )
        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                5,
                inSeason: 1,
                watchStatus: .watching,
                summary: AnimeEntryEpisodeProgressSummary(
                    seasonNumber: 1,
                    watchedThroughEpisode: 4,
                    episodeCount: 4,
                    updatedAt: .distantPast
                )
            )
        )
    }

    @Test func testEpisodePresentationMarksProgressForWatchingWatchedAndDroppedStatuses() {
        let summary = AnimeEntryEpisodeProgressSummary(
            seasonNumber: 1,
            watchedThroughEpisode: 4,
            episodeCount: 12,
            updatedAt: .distantPast
        )

        #expect(
            !EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .planToWatch,
                summary: summary
            )
        )
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watching,
                summary: summary
            )
        )
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .watched,
                summary: summary
            )
        )
        #expect(
            EntryDetailEpisodePresentation.isEpisodeWatched(
                1,
                inSeason: 1,
                watchStatus: .dropped,
                summary: summary
            )
        )
    }
}
