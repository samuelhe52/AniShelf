import Testing

@testable import DataProvider

@Test func watchedStatusNormalizesMissingDates() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = nil
    entry.dateFinished = nil
    entry.setWatchStatus(.watched, now: referenceDate(day: 10))

    #expect(entry.dateStarted == referenceDate(day: 10))
    #expect(entry.dateFinished == referenceDate(day: 10))
}

@Test func watchingStatusSetsStartDateWhenDateTrackingIsEnabled() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = nil
    entry.dateFinished = nil
    entry.setWatchStatus(.watching, now: referenceDate(day: 10))

    #expect(entry.dateStarted == referenceDate(day: 10))
    #expect(entry.dateFinished == nil)
}

@Test func planToWatchClearsTrackingDates() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.planToWatch, now: referenceDate(day: 10))

    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == nil)
}

@Test func statusChangesDoNotMutateDatesWhenDateTrackingIsDisabled() async throws {
    let entry = AnimeEntry.template()

    entry.isDateTrackingEnabled = false
    entry.dateStarted = nil
    entry.dateFinished = nil
    entry.setWatchStatus(.watched, now: referenceDate(day: 10))

    #expect(entry.watchStatus == .watched)
    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == nil)
}

@Test func disabledDateTrackingPreservesExistingDatesAcrossStatusChanges() async throws {
    let entry = AnimeEntry.template()

    entry.isDateTrackingEnabled = false
    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.planToWatch, now: referenceDate(day: 10))

    #expect(entry.watchStatus == .planToWatch)
    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == referenceDate(day: 7))
}

@Test func droppedStatusPreservesStartedDate() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = nil
    entry.setWatchStatus(.dropped, now: referenceDate(day: 10))

    #expect(entry.dateStarted == referenceDate(day: 3))
    #expect(entry.dateFinished == nil)
}

@Test func droppedStatusBackfillsMissingStartDateFromFinishedDate() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = nil
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.dropped, now: referenceDate(day: 10))

    #expect(entry.dateStarted == referenceDate(day: 7))
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

fileprivate func referenceDate(day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: day)
    )!
}
