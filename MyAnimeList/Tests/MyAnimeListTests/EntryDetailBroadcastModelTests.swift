//
//  EntryDetailBroadcastModelTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/12.
//

import DataProvider
import Foundation
import Testing

@testable import MyAnimeList

struct EntryDetailBroadcastModelTests {
    @Test @MainActor func persistedStatusIsOnlyAPreliminaryGate() {
        for status in ["Returning Series", "Planned", "In Production"] {
            #expect(
                EntryDetailBroadcastModel.passesPreliminaryGate(
                    entryType: .series,
                    seriesStatus: status
                )
            )
            #expect(
                EntryDetailBroadcastModel.passesPreliminaryGate(
                    entryType: .season(seasonNumber: 0, parentSeriesID: 0),
                    seriesStatus: status
                )
            )
        }

        for status in [nil, "Ended", "Canceled", "Pilot", "Unknown"] {
            #expect(
                !EntryDetailBroadcastModel.passesPreliminaryGate(
                    entryType: .series,
                    seriesStatus: status
                )
            )
        }

        #expect(
            !EntryDetailBroadcastModel.passesPreliminaryGate(
                entryType: .movie,
                seriesStatus: "Returning Series"
            )
        )
    }

    @Test func liveEligibilityUsesSeriesSchedulingData() async throws {
        let nextEpisodeChecker = makeEligibilityChecker(
            schedule: .init(
                firstAirDate: calendarDate(day: 1),
                nextEpisode: .init(seasonNumber: 2, airDate: calendarDate(day: 12)),
                seasonAirDates: [:]
            )
        )
        #expect(
            try await nextEpisodeChecker.check(
                entryType: .series,
                tmdbSeriesID: 42,
                now: date(day: 12),
                calendar: broadcastTestCalendar
            )
                == .eligible(externalIDs: broadcastTestExternalIDs)
        )

        let futurePremiereChecker = makeEligibilityChecker(
            schedule: .init(
                firstAirDate: calendarDate(day: 13),
                nextEpisode: nil,
                seasonAirDates: [:]
            )
        )
        #expect(
            try await futurePremiereChecker.check(
                entryType: .series,
                tmdbSeriesID: 42,
                now: date(day: 12),
                calendar: broadcastTestCalendar
            )
                == .eligible(externalIDs: broadcastTestExternalIDs)
        )

        let unscheduledChecker = makeEligibilityChecker(schedule: ineligibleSchedule)
        #expect(
            try await unscheduledChecker.check(
                entryType: .series,
                tmdbSeriesID: 42,
                now: date(day: 12),
                calendar: broadcastTestCalendar
            )
                == .ineligible
        )
    }

    @Test func liveSeasonEligibilityRequiresItsOwnScheduledEpisodeOrFutureAirDate() async throws {
        let matchingEpisodeChecker = makeEligibilityChecker(
            schedule: .init(
                firstAirDate: calendarDate(day: 1),
                nextEpisode: .init(seasonNumber: 2, airDate: calendarDate(day: 13)),
                seasonAirDates: [1: calendarDate(day: 1), 2: calendarDate(day: 1)]
            )
        )
        #expect(
            try await matchingEpisodeChecker.check(
                entryType: .season(seasonNumber: 2, parentSeriesID: 42),
                tmdbSeriesID: 42,
                now: date(day: 12),
                calendar: broadcastTestCalendar
            )
                == .eligible(externalIDs: broadcastTestExternalIDs)
        )
        #expect(
            try await matchingEpisodeChecker.check(
                entryType: .season(seasonNumber: 1, parentSeriesID: 42),
                tmdbSeriesID: 42,
                now: date(day: 12),
                calendar: broadcastTestCalendar
            )
                == .ineligible
        )

        let futureSeasonChecker = makeEligibilityChecker(
            schedule: .init(
                firstAirDate: calendarDate(day: 1),
                nextEpisode: nil,
                seasonAirDates: [3: calendarDate(day: 20)]
            )
        )
        #expect(
            try await futureSeasonChecker.check(
                entryType: .season(seasonNumber: 3, parentSeriesID: 42),
                tmdbSeriesID: 42,
                now: date(day: 12),
                calendar: broadcastTestCalendar
            )
                == .eligible(externalIDs: broadcastTestExternalIDs)
        )
    }

    @Test @MainActor func eligibleActivationChecksTMDbBeforeResolvingTVMaze() async throws {
        let expectedShow = makeBroadcastTestShow(id: 70)
        let probe = BroadcastResolutionProbe(tvdbShowID: expectedShow.id, show: expectedShow)
        let model = EntryDetailBroadcastModel(
            entryType: .series,
            tmdbID: 42,
            eligibilityChecker: makeEligibilityChecker(schedule: eligibleSchedule),
            resolver: makeBroadcastResolver(probe: probe),
            now: { date(day: 12) },
            calendar: broadcastTestCalendar
        )

        model.update(
            .init(
                isEnabled: true,
                entryType: .series,
                seriesStatus: "Returning Series"
            )
        )
        await waitUntil { model.phase == .resolved(expectedShow) }

        model.update(
            .init(
                isEnabled: true,
                entryType: .series,
                seriesStatus: "Planned"
            )
        )
        await Task.yield()

        #expect(model.phase == .resolved(expectedShow))
        #expect(await probe.loadedMappingTMDbIDs == [42])
        #expect(await probe.lookedUpTVDBIDs == [424_536])
    }

    @Test @MainActor func returningSeriesWithoutLiveScheduleNeverCallsTVMaze() async {
        let probe = BroadcastResolutionProbe()
        let model = EntryDetailBroadcastModel(
            entryType: .series,
            tmdbID: 42,
            eligibilityChecker: makeEligibilityChecker(schedule: ineligibleSchedule),
            resolver: makeBroadcastResolver(probe: probe),
            now: { date(day: 12) },
            calendar: broadcastTestCalendar
        )

        model.update(
            .init(
                isEnabled: true,
                entryType: .series,
                seriesStatus: "Returning Series"
            )
        )
        await waitUntil { model.phase == .ineligible }

        #expect(await probe.loadedMappingTMDbIDs.isEmpty)
    }

    @Test @MainActor func disablingCancelsResolutionAndKeepsDisabledPhase() async throws {
        let probe = BroadcastResolutionProbe(suspendsMappingLoad: true)
        let model = EntryDetailBroadcastModel(
            entryType: .series,
            tmdbID: 42,
            eligibilityChecker: makeEligibilityChecker(schedule: eligibleSchedule),
            resolver: makeBroadcastResolver(probe: probe),
            now: { date(day: 12) },
            calendar: broadcastTestCalendar
        )

        model.update(
            .init(
                isEnabled: true,
                entryType: .series,
                seriesStatus: "In Production"
            )
        )
        await waitUntil { await probe.didStartSuspendedLoad }

        model.update(
            .init(
                isEnabled: false,
                entryType: .series,
                seriesStatus: "In Production"
            )
        )
        await waitUntil { await probe.didCancelSuspendedLoad }

        #expect(model.phase == .disabled)
    }

    @Test @MainActor func detailHostSynchronizationKeepsTheSameBroadcastModel() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(name: "Test Series", type: .series, tmdbID: 42)
        let store = EntryDetailSessionStore(
            broadcastEligibilityChecker: makeEligibilityChecker(schedule: eligibleSchedule),
            broadcastResolver: makeBroadcastResolver(probe: BroadcastResolutionProbe())
        )

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let originalBroadcast = try #require(store.presentedSession?.broadcast)

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )

        #expect(store.presentedSession?.broadcast === originalBroadcast)
    }
}

fileprivate let broadcastTestCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

fileprivate let eligibleSchedule = TMDbSeriesBroadcastSchedule(
    firstAirDate: calendarDate(day: 1),
    nextEpisode: TMDbNextEpisodeSchedule(seasonNumber: 1, airDate: calendarDate(day: 13)),
    seasonAirDates: [1: calendarDate(day: 1)]
)

fileprivate let ineligibleSchedule = TMDbSeriesBroadcastSchedule(
    firstAirDate: calendarDate(day: 1),
    nextEpisode: nil,
    seasonAirDates: [1: calendarDate(day: 1)]
)

fileprivate let broadcastTestExternalIDs = TMDbSeriesExternalIDs(
    tvdbID: 424_536,
    imdbID: "tt22248376"
)

fileprivate func makeEligibilityChecker(
    schedule: TMDbSeriesBroadcastSchedule,
    externalIDs: TMDbSeriesExternalIDs = broadcastTestExternalIDs
) -> TMDbBroadcastEligibilityChecker {
    TMDbBroadcastEligibilityChecker { _ in
        TMDbSeriesBroadcastDetails(schedule: schedule, externalIDs: externalIDs)
    }
}

fileprivate func date(day: Int) -> Date {
    broadcastTestCalendar.date(from: DateComponents(year: 2026, month: 8, day: day))!
}

fileprivate func calendarDate(day: Int) -> TMDbCalendarDate {
    TMDbCalendarDate(year: 2026, month: 8, day: day)
}

private actor BroadcastResolutionProbe {
    private let mappedShowID: Int?
    private let tvdbShowID: Int?
    private let show: TVMazeShow?
    private let suspendsMappingLoad: Bool

    private(set) var loadedMappingTMDbIDs: [Int] = []
    private(set) var lookedUpTVDBIDs: [Int] = []
    private(set) var didStartSuspendedLoad = false
    private(set) var didCancelSuspendedLoad = false

    init(
        mappedShowID: Int? = nil,
        tvdbShowID: Int? = nil,
        show: TVMazeShow? = nil,
        suspendsMappingLoad: Bool = false
    ) {
        self.mappedShowID = mappedShowID
        self.tvdbShowID = tvdbShowID
        self.show = show
        self.suspendsMappingLoad = suspendsMappingLoad
    }

    func loadMapping(for tmdbSeriesID: Int) async throws -> Int? {
        loadedMappingTMDbIDs.append(tmdbSeriesID)
        guard suspendsMappingLoad else { return mappedShowID }

        didStartSuspendedLoad = true
        do {
            try await Task.sleep(for: .seconds(60))
            return nil
        } catch {
            didCancelSuspendedLoad = true
            throw error
        }
    }

    func hydratedShow(id: Int) -> TVMazeShow? {
        guard show?.id == id else { return nil }
        return show
    }

    func lookupTVDBShowID(tvdbID: Int) -> Int? {
        lookedUpTVDBIDs.append(tvdbID)
        return tvdbShowID
    }
}

fileprivate func makeBroadcastResolver(probe: BroadcastResolutionProbe) -> TVMazeResolver {
    TVMazeResolver(
        loadMappedShowID: { try await probe.loadMapping(for: $0) },
        saveMappedShowID: { _, _ in },
        lookupTVDBShowID: { await probe.lookupTVDBShowID(tvdbID: $0) },
        lookupIMDbShowID: { _ in nil },
        searchShowID: { _ in nil },
        fetchShow: { await probe.hydratedShow(id: $0) }
    )
}

fileprivate func makeBroadcastTestShow(id: Int) -> TVMazeShow {
    TVMazeShow(
        id: id,
        name: "Test Show",
        language: "Japanese",
        premiered: "2026-01-01",
        providerLocalSchedule: TVMazeSchedule(
            days: [.friday],
            time: TVMazeTimeOfDay(hour: 1, minute: 30, context: .provider),
            dayOffsetFromBroadcastDay: 1
        ),
        timeZone: TimeZone(identifier: "Asia/Tokyo"),
        fullImageURL: nil,
        nextEpisodeAiring: nil
    )
}

@MainActor
fileprivate func waitUntil(
    _ condition: @escaping @MainActor () async -> Bool
) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for broadcast state")
}
