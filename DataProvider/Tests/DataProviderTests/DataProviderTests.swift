import Foundation
import Testing

@testable import DataProvider

@Test func watchedStatusDoesNotBackfillMissingDates() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = nil
    entry.dateFinished = nil
    entry.setWatchStatus(.watched)

    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == nil)
}

@Test func watchingStatusDoesNotBackfillStartDate() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = nil
    entry.dateFinished = nil
    entry.setWatchStatus(.watching)

    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == nil)
}

@Test func planToWatchPreservesExistingTrackingDates() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.planToWatch)

    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == referenceDate(day: 7))
}

@Test func statusChangesDoNotMutateDatesWhenDateTrackingIsDisabled() async throws {
    let entry = AnimeEntry.template()

    entry.isDateTrackingEnabled = false
    entry.dateStarted = nil
    entry.dateFinished = nil
    entry.setWatchStatus(.watched)

    #expect(entry.watchStatus == .watched)
    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == nil)
}

@Test func statusChangesDoNotMutateExistingDatesWhenDateTrackingIsEnabled() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.planToWatch)

    #expect(entry.watchStatus == .planToWatch)
    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == referenceDate(day: 7))
}

@Test func droppedStatusPreservesStartedDate() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = nil
    entry.setWatchStatus(.dropped)

    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == nil)
}

@Test func droppedStatusPreservesFinishedDateWithoutBackfill() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = nil
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.dropped)

    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == referenceDate(day: 7))
}

@Test func dateTrackingToggleDoesNotNormalizeExistingDates() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = referenceDate(day: 7)

    entry.setDateTrackingEnabled(false)
    #expect(!entry.isDateTrackingEnabled)
    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == referenceDate(day: 7))

    entry.setDateTrackingEnabled(true)
    #expect(entry.isDateTrackingEnabled)
    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == referenceDate(day: 7))
}

@Test func entryDetailOrdersPersistedChildrenByDisplayOrder() async throws {
    let detail = AnimeEntryDetail(
        language: "en-US",
        title: "Detail",
        characters: [
            AnimeEntryCharacter(
                id: 2,
                characterName: "Second",
                actorName: "Actor B",
                displayOrder: 1
            ),
            AnimeEntryCharacter(
                id: 1,
                characterName: "First",
                actorName: "Actor A",
                displayOrder: 0
            )
        ],
        staff: [
            AnimeEntryStaff(
                id: 20,
                name: "Second",
                role: "Director",
                jobs: [
                    AnimeEntryStaffJob(
                        creditID: "20-b",
                        job: "Music",
                        episodeCount: 8,
                        displayOrder: 1
                    ),
                    AnimeEntryStaffJob(
                        creditID: "20-a",
                        job: "Director",
                        episodeCount: 12,
                        displayOrder: 0
                    )
                ],
                displayOrder: 1
            ),
            AnimeEntryStaff(id: 10, name: "First", role: "Writer", displayOrder: 0)
        ],
        episodes: [
            AnimeEntryEpisodeSummary(id: 200, episodeNumber: 2, title: "Second", displayOrder: 1),
            AnimeEntryEpisodeSummary(id: 100, episodeNumber: 1, title: "First", displayOrder: 0)
        ]
    )

    #expect(detail.orderedCharacters.map(\.id) == [1, 2])
    #expect(detail.orderedStaff.map(\.id) == [10, 20])
    #expect(detail.orderedStaff[1].orderedJobs.map(\.creditID) == ["20-a", "20-b"])
    #expect(detail.orderedEpisodes.map(\.id) == [100, 200])
}

@Test func entryDetailApplyPreservesDTOChildOrder() async throws {
    let detail = AnimeEntryDetail(language: "en-US", title: "Old")

    detail.apply(
        dto: AnimeEntryDetailDTO(
            language: "en-US",
            title: "New",
            characters: [
                AnimeEntryCharacterDTO(id: 30, characterName: "Third", actorName: "Actor C"),
                AnimeEntryCharacterDTO(id: 10, characterName: "First", actorName: "Actor A"),
                AnimeEntryCharacterDTO(id: 20, characterName: "Second", actorName: "Actor B")
            ],
            staff: [
                AnimeEntryStaffDTO(
                    id: 200,
                    name: "Second",
                    role: "Director",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "200-b",
                            job: "Music",
                            episodeCount: 8
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "200-a",
                            job: "Director",
                            episodeCount: 12
                        )
                    ]
                ),
                AnimeEntryStaffDTO(id: 100, name: "First", role: "Writer")
            ],
            episodes: [
                AnimeEntryEpisodeSummaryDTO(id: 2, episodeNumber: 2, title: "Second"),
                AnimeEntryEpisodeSummaryDTO(id: 1, episodeNumber: 1, title: "First")
            ]
        )
    )

    #expect(detail.orderedCharacters.map(\.id) == [30, 10, 20])
    #expect(detail.orderedStaff.map(\.id) == [200, 100])
    #expect(detail.orderedStaff[0].orderedJobs.map(\.creditID) == ["200-b", "200-a"])
    #expect(detail.orderedEpisodes.map(\.id) == [2, 1])
}

@Test func replaceDetailPersistsAggregateStaffJobs() async throws {
    let entry = AnimeEntry.template()

    let detail = entry.replaceDetail(
        from: AnimeEntryDetailDTO(
            language: "en-US",
            title: "New",
            staff: [
                AnimeEntryStaffDTO(
                    id: 300,
                    name: "Creator",
                    role: "Directing",
                    department: "Directing",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "director",
                            job: "Director",
                            episodeCount: 12
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "music",
                            job: "Music",
                            episodeCount: 8
                        )
                    ]
                )
            ]
        )
    )

    let staff = try #require(detail.orderedStaff.first)
    #expect(detail.orderedStaff.count == 1)
    #expect(staff.role == "Directing")
    #expect(staff.orderedJobs.map(\.creditID) == ["director", "music"])
    #expect(staff.orderedJobs.map(\.job) == ["Director", "Music"])
}

@Test func episodeProgressSetIncrementClearAndClamp() async throws {
    let entry = AnimeEntry(
        name: "Season",
        type: .season(seasonNumber: 1, parentSeriesID: 10),
        tmdbID: 11,
        detail: AnimeEntryDetail(language: "en-US", title: "Season", episodeCount: 12)
    )

    entry.applyEpisodeProgressSnapshot(
        seasonNumber: 1,
        watchedThroughEpisode: 5, updatedAt: referenceDate(day: 1)
    )
    #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 5)

    entry.incrementEpisodeProgress(seasonNumber: 1, by: 20, now: referenceDate(day: 2))
    #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 12)

    entry.incrementEpisodeProgress(seasonNumber: 1, by: -2, now: referenceDate(day: 3))
    #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 10)

    entry.clearEpisodeProgress(seasonNumber: 1)
    #expect(entry.episodeProgresses.isEmpty)
}

@Test func userEntryInfoRoundTripPreservesEpisodeProgress() async throws {
    let series = AnimeEntry(name: "Series", type: .series, tmdbID: 31)
    series.applyEpisodeProgressSnapshot(seasonNumber: 0, watchedThroughEpisode: 1, updatedAt: referenceDate(day: 1))
    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 5, updatedAt: referenceDate(day: 2))

    let userInfo = UserEntryInfo(from: series)
    #expect(userInfo.episodeProgresses.map(\.seasonNumber) == [2])
    #expect(userInfo.episodeProgresses.map(\.watchedThroughEpisode) == [5])

    let encoded = try JSONEncoder().encode(userInfo)
    let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: encoded)
    #expect(decoded == userInfo)

    let restoredSeries = AnimeEntry(name: "Restored", type: .series, tmdbID: 32)
    restoredSeries.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 9, updatedAt: referenceDate(day: 3))
    restoredSeries.updateUserInfo(from: decoded)

    #expect(restoredSeries.orderedEpisodeProgresses.map(\.seasonNumber) == [2])
    #expect(restoredSeries.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 5)
    #expect(restoredSeries.episodeProgressSummary(forSeason: 0).watchedThroughEpisode == 0)
    #expect(restoredSeries.episodeProgress(forSeason: 2)?.updatedAt == referenceDate(day: 2))
    #expect(restoredSeries.episodeProgress(forSeason: 1) == nil)
}

@Test func userEntryInfoRestoreFiltersEpisodeProgressForSeasonEntries() async throws {
    let sourceSeries = AnimeEntry(name: "Series", type: .series, tmdbID: 41)
    sourceSeries.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 3, updatedAt: referenceDate(day: 1))
    sourceSeries.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 7, updatedAt: referenceDate(day: 2))
    sourceSeries.applyEpisodeProgressSnapshot(seasonNumber: 0, watchedThroughEpisode: 1, updatedAt: referenceDate(day: 3))

    let seasonEntry = AnimeEntry(
        name: "Season 2",
        type: .season(seasonNumber: 2, parentSeriesID: 41),
        tmdbID: 42
    )
    seasonEntry.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 1, updatedAt: referenceDate(day: 4))

    seasonEntry.updateUserInfo(from: UserEntryInfo(from: sourceSeries))

    #expect(seasonEntry.orderedEpisodeProgresses.map(\.seasonNumber) == [2])
    #expect(seasonEntry.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 7)
    #expect(seasonEntry.episodeProgress(forSeason: 2)?.updatedAt == referenceDate(day: 2))
}

@Test func userEntryInfoDecodingDefaultsMissingEpisodeProgressesToEmpty() throws {
    let entry = AnimeEntry.template(id: 51)
    var payload = try #require(
        JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(UserEntryInfo(from: entry))
        ) as? [String: Any]
    )
    payload.removeValue(forKey: "episodeProgresses")

    let decoded = try JSONDecoder().decode(
        UserEntryInfo.self,
        from: JSONSerialization.data(withJSONObject: payload)
    )

    #expect(decoded.episodeProgresses.isEmpty)
}

@Test func episodeProgressIgnoresSpecials() async throws {
    let entry = AnimeEntry(name: "Series", type: .series, tmdbID: 21)

    entry.applyEpisodeProgressSnapshot(seasonNumber: 0, watchedThroughEpisode: 1)
    entry.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 4)
    entry.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 3)

    #expect(entry.orderedEpisodeProgresses.map(\.seasonNumber) == [1, 2])
    #expect(entry.episodeProgressSeasonOptions == [1, 2])
    #expect(entry.episodeProgressSummary(forSeason: 0).watchedThroughEpisode == 0)
}

@Test func movieEpisodeProgressIsIgnored() async throws {
    let movie = AnimeEntry.template()

    movie.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 3)

    #expect(movie.episodeProgresses.isEmpty)
    #expect(movie.episodeProgressSeasonOptions.isEmpty)
    #expect(movie.latestEpisodeProgressSummary == nil)
}

@Test func specialsSeasonEpisodeProgressIsIgnored() async throws {
    let specials = AnimeEntry(
        name: "Specials",
        type: .season(seasonNumber: 0, parentSeriesID: 99),
        tmdbID: 100
    )

    specials.applyEpisodeProgressSnapshot(seasonNumber: 0, watchedThroughEpisode: 3)

    #expect(specials.episodeProgresses.isEmpty)
    #expect(specials.episodeProgressSeasonOptions.isEmpty)
    #expect(specials.latestEpisodeProgressSummary == nil)
}

@Test func episodeProgressDoesNotSynchronizeWatchStatus() async throws {
    let entry = AnimeEntry(
        name: "Season",
        type: .season(seasonNumber: 1, parentSeriesID: 31),
        tmdbID: 32,
        detail: AnimeEntryDetail(language: "en-US", title: "Season", episodeCount: 3)
    )

    entry.setWatchStatus(.planToWatch)
    entry.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 3)
    #expect(entry.watchStatus == .planToWatch)

    entry.setWatchStatus(.watched)
    #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 3)
}

@Test func episodeProgressCompletionPromptRequiresWatchingAndKnownCompletion() async throws {
    let season = AnimeEntry(
        name: "Season",
        type: .season(seasonNumber: 1, parentSeriesID: 61),
        tmdbID: 62,
        detail: AnimeEntryDetail(language: "en-US", title: "Season", episodeCount: 3)
    )

    season.setWatchStatus(.watching)
    season.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 3)
    #expect(
        season.episodeProgressCompletionPrompt(forSeason: 1, previousWatchedThroughEpisode: 2)
            == .seasonWatched
    )

    season.setWatchStatus(.planToWatch)
    #expect(
        season.episodeProgressCompletionPrompt(forSeason: 1, previousWatchedThroughEpisode: 2)
            == nil
    )

    let unknownCountSeries = AnimeEntry(name: "Series", type: .series, tmdbID: 63)
    unknownCountSeries.setWatchStatus(.watching)
    unknownCountSeries.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 5)
    #expect(
        unknownCountSeries.episodeProgressCompletionPrompt(
            forSeason: 1,
            previousWatchedThroughEpisode: 4
        ) == nil
    )
}

@Test func seriesEpisodeProgressCompletionPromptRequiresAllNumberedSeasons() async throws {
    let series = AnimeEntry(
        name: "Series",
        type: .series,
        tmdbID: 71,
        detail: AnimeEntryDetail(
            language: "en-US",
            title: "Series",
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 72,
                    seasonNumber: 1,
                    title: "Season 1",
                    episodeCount: 12
                ),
                AnimeEntrySeasonSummary(
                    id: 73,
                    seasonNumber: 2,
                    title: "Season 2",
                    episodeCount: 10
                )
            ]
        )
    )
    series.setWatchStatus(.watching)

    series.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 12)
    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 9)
    #expect(!series.areAllNumberedEpisodeProgressSeasonsComplete)
    #expect(
        series.episodeProgressCompletionPrompt(forSeason: 1, previousWatchedThroughEpisode: 11)
            == nil
    )

    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 10)
    #expect(series.areAllNumberedEpisodeProgressSeasonsComplete)
    #expect(
        series.episodeProgressCompletionPrompt(forSeason: 2, previousWatchedThroughEpisode: 9)
            == .seriesWatched
    )
}

@Test func episodeProgressUsesParentSeriesSeasonCountsForSeriesLimits() async throws {
    let series = AnimeEntry(
        name: "Series",
        type: .series,
        tmdbID: 41,
        detail: AnimeEntryDetail(
            language: "en-US",
            title: "Series",
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 42,
                    seasonNumber: 0,
                    title: "Specials",
                    episodeCount: 2
                ),
                AnimeEntrySeasonSummary(
                    id: 43,
                    seasonNumber: 2,
                    title: "Season 2",
                    episodeCount: 12
                )
            ]
        )
    )

    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 50)

    #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 12)
    #expect(series.episodeProgressSummary(forSeason: 2).episodeCount == 12)
    #expect(series.episodeProgressLimit(forSeason: 0) == nil)
}

@Test func episodeProgressFallsBackToParentSeriesEpisodeCountForSingleSeasonDetail() async throws {
    let series = AnimeEntry(
        name: "Series",
        type: .series,
        tmdbID: 44,
        detail: AnimeEntryDetail(
            language: "en-US",
            title: "Series",
            episodeCount: 12,
            seasons: [AnimeEntrySeasonSummary(id: 45, seasonNumber: 2, title: "Season 2")]
        )
    )

    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 50)

    #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 12)
    #expect(series.episodeProgressSummary(forSeason: 2).episodeCount == 12)
}

@Test func episodeProgressUsesChildSeasonLimitsWhenParentSeriesCountsAreMissing() async throws {
    let series = AnimeEntry(name: "Series", type: .series, tmdbID: 41)
    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 50)
    #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 50)
    #expect(series.episodeProgressSummary(forSeason: 2).episodeCount == nil)

    let childSeason = AnimeEntry(
        name: "Season 2",
        type: .season(seasonNumber: 2, parentSeriesID: 41),
        tmdbID: 42,
        detail: AnimeEntryDetail(language: "en-US", title: "Season 2", episodeCount: 12)
    )
    childSeason.parentSeriesEntry = series
    series.childSeasonEntries = [childSeason]

    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 50)
    #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 12)
    #expect(series.episodeProgressSummary(forSeason: 2).episodeCount == 12)

    series.detail = AnimeEntryDetail(
        language: "en-US",
        title: "Series",
        seasons: [AnimeEntrySeasonSummary(id: 43, seasonNumber: 2, title: "Season 2", episodeCount: 12)]
    )
    series.applyEpisodeProgressSnapshot(seasonNumber: 2, watchedThroughEpisode: 50)
    #expect(series.episodeProgressSummary(forSeason: 2).watchedThroughEpisode == 12)
    #expect(series.episodeProgressSummary(forSeason: 2).episodeCount == 12)
}

@Test func episodeProgressClampsToListedEpisodesWhenEpisodeCountIsMissing() async throws {
    let entry = AnimeEntry(
        name: "Season",
        type: .season(seasonNumber: 1, parentSeriesID: 51),
        tmdbID: 52,
        detail: AnimeEntryDetail(
            language: "en-US",
            title: "Season",
            episodes: (1...5).map {
                AnimeEntryEpisodeSummary(id: $0, episodeNumber: $0, title: "Episode \($0)")
            }
        )
    )

    entry.applyEpisodeProgressSnapshot(seasonNumber: 1, watchedThroughEpisode: 12)

    #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 5)
    #expect(entry.episodeProgressSummary(forSeason: 1).episodeCount == 5)
}

fileprivate func referenceDate(day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: day)
    )!
}
