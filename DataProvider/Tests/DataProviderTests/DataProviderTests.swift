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

@Test func planToWatchClearsTrackingDates() async throws {
    let entry = AnimeEntry.template()

    entry.dateStarted = referenceDate(day: 3)
    entry.dateFinished = referenceDate(day: 7)
    entry.setWatchStatus(.planToWatch, now: referenceDate(day: 10))

    #expect(entry.dateStarted == nil)
    #expect(entry.dateFinished == nil)
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
            AnimeEntryStaff(id: 20, name: "Second", role: "Director", displayOrder: 1),
            AnimeEntryStaff(id: 10, name: "First", role: "Writer", displayOrder: 0)
        ],
        episodes: [
            AnimeEntryEpisodeSummary(id: 200, episodeNumber: 2, title: "Second", displayOrder: 1),
            AnimeEntryEpisodeSummary(id: 100, episodeNumber: 1, title: "First", displayOrder: 0)
        ]
    )

    #expect(detail.orderedCharacters.map(\.id) == [1, 2])
    #expect(detail.orderedStaff.map(\.id) == [10, 20])
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
                AnimeEntryStaffDTO(id: 200, name: "Second", role: "Director"),
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
    #expect(detail.orderedEpisodes.map(\.id) == [2, 1])
}

fileprivate func referenceDate(day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: day)
    )!
}
