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

fileprivate func referenceDate(day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 4, day: day)
    )!
}
