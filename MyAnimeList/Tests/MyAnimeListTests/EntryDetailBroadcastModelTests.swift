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
                == eligibleResult(day: 12, basis: .nextEpisode)
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
                == eligibleResult(day: 13, basis: .seriesPremiere)
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
                == eligibleResult(day: 13, basis: .nextEpisode)
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
                == eligibleResult(day: 20, basis: .seasonPremiere)
        )
    }

    @Test func availabilityUsesTVMazeAirstampAndNormalizesAfterMidnightDate() {
        let airing = TVMazeNextEpisodeAiring(
            seasonNumber: 7,
            episodeNumber: 99,
            airStamp: providerDate(day: 17, hour: 0, minute: 30)
        )
        let show = makeBroadcastTestShow(id: 70, nextEpisodeAiring: airing)
        let tmdbEvidence = airingEvidence(day: 17, basis: .nextEpisode)

        let availability = BroadcastAvailability(
            resolvedShow: show,
            tmdbEvidence: tmdbEvidence
        )

        #expect(
            availability
                == .tvMazeNextAiring(
                    show: show,
                    airing: airing,
                    dateAssessment: .agrees
                )
        )
    }

    @Test func availabilityKeepsDisagreeingTVMazeAirstamp() {
        let airing = TVMazeNextEpisodeAiring(
            seasonNumber: 1,
            episodeNumber: 7,
            airStamp: providerDate(day: 14, hour: 23, minute: 30)
        )
        let show = makeBroadcastTestShow(id: 70, nextEpisodeAiring: airing)
        let tmdbEvidence = airingEvidence(day: 21, basis: .nextEpisode)

        let availability = BroadcastAvailability(
            resolvedShow: show,
            tmdbEvidence: tmdbEvidence
        )

        #expect(
            availability
                == .tvMazeNextAiring(
                    show: show,
                    airing: airing,
                    dateAssessment: .disagrees(
                        tvMazeDate: calendarDate(day: 14),
                        tmdbDate: calendarDate(day: 21)
                    )
                )
        )
    }

    @Test func availabilityDoesNotCompareTVMazeAirstampWithPremiereEvidence() {
        let airing = TVMazeNextEpisodeAiring(
            seasonNumber: 1,
            episodeNumber: 1,
            airStamp: providerDate(day: 20, hour: 23, minute: 30)
        )
        let show = makeBroadcastTestShow(id: 70, nextEpisodeAiring: airing)

        let availability = BroadcastAvailability(
            resolvedShow: show,
            tmdbEvidence: airingEvidence(day: 20, basis: .seriesPremiere)
        )

        #expect(
            availability
                == .tvMazeNextAiring(
                    show: show,
                    airing: airing,
                    dateAssessment: .notComparable
                )
        )
    }

    @Test func availabilityFallsBackToTMDbWhenTVMazeAirstampIsMissing() {
        let show = makeBroadcastTestShow(id: 70)
        let tmdbEvidence = airingEvidence(day: 13, basis: .nextEpisode)

        let availability = BroadcastAvailability(
            resolvedShow: show,
            tmdbEvidence: tmdbEvidence
        )

        #expect(availability == .tmdbExpected(tmdbEvidence))

        let replacementAvailability = BroadcastAvailability(
            resolvedShow: show,
            tmdbEvidence: tmdbEvidence,
            allowsTMDbFallback: false
        )

        #expect(replacementAvailability == .unavailable)
    }

    @Test func availabilityIsUnavailableWithoutEitherProviderDate() {
        let availability = BroadcastAvailability(
            resolvedShow: makeBroadcastTestShow(id: 70),
            tmdbEvidence: nil
        )

        #expect(availability == .unavailable)
    }

    @Test @MainActor func eligibleActivationChecksTMDbBeforeResolvingTVMaze() async throws {
        let expectedAiring = TVMazeNextEpisodeAiring(
            seasonNumber: 4,
            episodeNumber: 12,
            airStamp: providerDate(day: 13, hour: 23, minute: 30)
        )
        let expectedShow = makeBroadcastTestShow(
            id: 70,
            nextEpisodeAiring: expectedAiring
        )
        let expectedAvailability = BroadcastAvailability.tvMazeNextAiring(
            show: expectedShow,
            airing: expectedAiring,
            dateAssessment: .agrees
        )
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
        await waitUntil { model.phase == .resolved(expectedAvailability) }

        model.update(
            .init(
                isEnabled: true,
                entryType: .series,
                seriesStatus: "Planned"
            )
        )
        await Task.yield()

        #expect(model.phase == .resolved(expectedAvailability))
        #expect(model.resolvedShow == expectedShow)
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

    @Test @MainActor func titleFallbackRequiresConfirmationBeforeResolvingAndSaving() async throws {
        let candidate = makeBroadcastTestShow(id: 90)
        let probe = BroadcastResolutionProbe(
            titleShowID: candidate.id,
            show: candidate
        )
        let model = EntryDetailBroadcastModel(
            entryType: .season(seasonNumber: 1, parentSeriesID: 42),
            tmdbID: 84,
            eligibilityChecker: makeEligibilityChecker(schedule: eligibleSchedule),
            resolver: makeBroadcastResolver(probe: probe),
            now: { date(day: 12) },
            calendar: broadcastTestCalendar
        )

        model.update(
            .init(
                isEnabled: true,
                entryType: .season(seasonNumber: 1, parentSeriesID: 42),
                seriesStatus: "Returning Series"
            )
        )
        await waitUntil { model.phase == .requiresUserAssistance }

        model.startTitleFallback(named: "Frieren")
        await waitUntil { model.phase == .titleCandidate(candidate) }

        #expect(await probe.searchedTitles == ["Frieren"])
        #expect(await probe.savedMappings.isEmpty)

        model.confirmTitleFallbackCandidate()
        await waitUntil {
            model.phase
                == .resolved(
                    .tmdbExpected(airingEvidence(day: 13, basis: .nextEpisode))
                )
        }

        #expect(await probe.savedMappings == [.init(tmdbSeriesID: 42, showID: 90)])
    }

    @Test @MainActor func replacementSearchKeepsResolvedMappingUntilConfirmation() async throws {
        let resolvedShow = makeBroadcastTestShow(id: 70)
        let replacement = makeBroadcastTestShow(id: 90)
        let expectedAvailability = BroadcastAvailability.tmdbExpected(
            airingEvidence(day: 13, basis: .nextEpisode)
        )
        let probe = BroadcastResolutionProbe(
            mappedShowID: resolvedShow.id,
            titleShowID: replacement.id,
            show: resolvedShow,
            additionalShows: [replacement.id: replacement]
        )
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
        await waitUntil { model.phase == .resolved(expectedAvailability) }

        let results = try await model.searchTitleCandidates(named: "  Replacement  ")
        let selected = try #require(await model.hydrateTitleCandidate(id: replacement.id))

        #expect(results == [replacement])
        #expect(await probe.searchedTitles == ["Replacement"])
        #expect(await probe.savedMappings.isEmpty)
        #expect(model.phase == .resolved(expectedAvailability))
        #expect(model.resolvedShow == resolvedShow)

        model.confirm(candidate: selected)
        await waitUntil { model.phase == .resolved(expectedAvailability) }

        #expect(model.resolvedShow == replacement)
        #expect(await probe.savedMappings == [.init(tmdbSeriesID: 42, showID: 90)])
    }

    @Test @MainActor func detailHostSynchronizationKeepsTheSameBroadcastModel() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(name: "Test Series", type: .series, tmdbID: 42)
        let store = EntryDetailSessionStore(
            broadcastEligibilityChecker: makeEligibilityChecker(schedule: eligibleSchedule),
            broadcastResolver: makeBroadcastResolver(probe: BroadcastResolutionProbe())
        )

        store.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )
        let originalBroadcast = try #require(store.presentedSession?.broadcast)

        store.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
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

fileprivate func eligibleResult(
    day: Int,
    basis: TMDbAiringEvidence.Basis
) -> TMDbBroadcastEligibilityResult {
    .eligible(
        externalIDs: broadcastTestExternalIDs,
        airingEvidence: airingEvidence(day: day, basis: basis)
    )
}

fileprivate func airingEvidence(
    day: Int,
    basis: TMDbAiringEvidence.Basis
) -> TMDbAiringEvidence {
    TMDbAiringEvidence(airDate: calendarDate(day: day), basis: basis)
}

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

fileprivate func providerDate(day: Int, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar.date(
        from: DateComponents(
            year: 2026,
            month: 8,
            day: day,
            hour: hour,
            minute: minute
        )
    )!
}

private actor BroadcastResolutionProbe {
    struct Mapping: Equatable, Sendable {
        let tmdbSeriesID: Int
        let showID: Int
    }

    private let mappedShowID: Int?
    private let tvdbShowID: Int?
    private let titleShowID: Int?
    private let shows: [Int: TVMazeShow]
    private let suspendsMappingLoad: Bool

    private(set) var loadedMappingTMDbIDs: [Int] = []
    private(set) var lookedUpTVDBIDs: [Int] = []
    private(set) var searchedTitles: [String] = []
    private(set) var savedMappings: [Mapping] = []
    private(set) var didStartSuspendedLoad = false
    private(set) var didCancelSuspendedLoad = false

    init(
        mappedShowID: Int? = nil,
        tvdbShowID: Int? = nil,
        titleShowID: Int? = nil,
        show: TVMazeShow? = nil,
        additionalShows: [Int: TVMazeShow] = [:],
        suspendsMappingLoad: Bool = false
    ) {
        self.mappedShowID = mappedShowID
        self.tvdbShowID = tvdbShowID
        self.titleShowID = titleShowID
        var shows = additionalShows
        if let show {
            shows[show.id] = show
        }
        self.shows = shows
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
        shows[id]
    }

    func lookupTVDBShowID(tvdbID: Int) -> Int? {
        lookedUpTVDBIDs.append(tvdbID)
        return tvdbShowID
    }

    func searchShows(title: String) -> [TVMazeShow] {
        searchedTitles.append(title)
        guard let titleShowID, let show = shows[titleShowID] else { return [] }
        return [show]
    }

    func saveMapping(tmdbSeriesID: Int, showID: Int) {
        savedMappings.append(.init(tmdbSeriesID: tmdbSeriesID, showID: showID))
    }
}

fileprivate func makeBroadcastResolver(probe: BroadcastResolutionProbe) -> TVMazeResolver {
    TVMazeResolver(
        loadMappedShowID: { try await probe.loadMapping(for: $0) },
        saveMappedShowID: { await probe.saveMapping(tmdbSeriesID: $0, showID: $1) },
        lookupTVDBShowID: { await probe.lookupTVDBShowID(tvdbID: $0) },
        lookupIMDbShowID: { _ in nil },
        searchShows: { await probe.searchShows(title: $0) },
        fetchShow: { await probe.hydratedShow(id: $0) }
    )
}

fileprivate func makeBroadcastTestShow(
    id: Int,
    nextEpisodeAiring: TVMazeNextEpisodeAiring? = nil
) -> TVMazeShow {
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
        nextEpisodeAiring: nextEpisodeAiring
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
