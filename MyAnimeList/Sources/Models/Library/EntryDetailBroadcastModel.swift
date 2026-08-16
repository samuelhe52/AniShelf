//
//  EntryDetailBroadcastModel.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/12.
//

import DataProvider
import Foundation
import Observation

enum BroadcastDateAssessment: Equatable, Sendable {
    case agrees
    case notComparable
    case disagrees(
        tvMazeDate: TMDbCalendarDate,
        tmdbDate: TMDbCalendarDate
    )
}

enum BroadcastAvailability: Equatable, Sendable {
    case tvMazeNextAiring(
        show: TVMazeShow,
        airing: TVMazeNextEpisodeAiring,
        dateAssessment: BroadcastDateAssessment
    )
    case tmdbExpected(TMDbAiringEvidence)
    case unavailable

    /// Builds the availability used by the outer Airtime menu and resolved lifecycle state.
    ///
    /// TVMaze's concrete `airstamp` is always preferred. TMDb's next-episode date validates
    /// that timestamp when both describe the same event. The outer menu may also fall back to
    /// TMDb when TVMaze has no concrete airing; confirmation surfaces disable that fallback.
    init(
        resolvedShow show: TVMazeShow,
        tmdbEvidence: TMDbAiringEvidence?,
        allowsTMDbFallback: Bool = true
    ) {
        guard let airing = show.nextEpisodeAiring else {
            self =
                allowsTMDbFallback
                ? tmdbEvidence.map(Self.tmdbExpected) ?? .unavailable
                : .unavailable
            return
        }

        let dateAssessment: BroadcastDateAssessment
        if tmdbEvidence?.basis != .nextEpisode {
            dateAssessment = .notComparable
        } else if let tmdbDate = tmdbEvidence?.airDate,
            let tvMazeDate = Self.providerLocalDate(
                for: airing.airStamp,
                timeZone: show.timeZone
            )
        {
            dateAssessment =
                tvMazeDate == tmdbDate
                ? .agrees
                : .disagrees(tvMazeDate: tvMazeDate, tmdbDate: tmdbDate)
        } else {
            dateAssessment = .notComparable
        }

        self = .tvMazeNextAiring(
            show: show,
            airing: airing,
            dateAssessment: dateAssessment
        )
    }

    private static func providerLocalDate(
        for date: Date,
        timeZone: TimeZone?
    ) -> TMDbCalendarDate? {
        guard let timeZone else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return nil
        }
        return TMDbCalendarDate(year: year, month: month, day: day)
    }
}

@MainActor
@Observable
final class EntryDetailBroadcastModel {
    struct Activation: Equatable {
        let isEnabled: Bool
        let entryType: AnimeType
        let seriesStatus: String?
    }

    enum Phase: Equatable {
        case disabled
        case ineligible
        case idle
        case checkingEligibility
        case resolving
        case resolved(BroadcastAvailability)
        case requiresUserAssistance
        case titleSearching
        case titleCandidate(TVMazeShow)
        case failed
    }

    private enum PreliminaryGate: Equatable {
        case disabled
        case ineligible
        case eligible
    }

    private static let eligibleSeriesStatuses: Set<String> = [
        "Returning Series",
        "Planned",
        "In Production"
    ]

    private let entryType: AnimeType
    private let tmdbID: Int
    private let eligibilityChecker: TMDbBroadcastEligibilityChecker
    private let resolver: TVMazeResolver
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var gate: PreliminaryGate?
    private var airingEvidence: TMDbAiringEvidence?
    private var resolutionTask: Task<Void, Never>?
    private var resolutionID: UUID?

    private(set) var phase: Phase = .disabled
    private(set) var resolvedShow: TVMazeShow?

    init(
        entryType: AnimeType,
        tmdbID: Int,
        eligibilityChecker: TMDbBroadcastEligibilityChecker = .init(),
        resolver: TVMazeResolver,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.entryType = entryType
        self.tmdbID = tmdbID
        self.eligibilityChecker = eligibilityChecker
        self.resolver = resolver
        self.now = now
        self.calendar = calendar
    }

    isolated deinit {
        resolutionTask?.cancel()
    }

    static func passesPreliminaryGate(entryType: AnimeType, seriesStatus: String?) -> Bool {
        guard entryType != .movie, let seriesStatus else { return false }
        return eligibleSeriesStatuses.contains(seriesStatus)
    }

    func update(_ activation: Activation) {
        let nextGate: PreliminaryGate
        if !activation.isEnabled {
            nextGate = .disabled
        } else if Self.passesPreliminaryGate(
            entryType: activation.entryType,
            seriesStatus: activation.seriesStatus
        ) {
            nextGate = .eligible
        } else {
            nextGate = .ineligible
        }

        guard nextGate != gate else { return }
        gate = nextGate
        cancelResolution()
        airingEvidence = nil
        resolvedShow = nil

        switch nextGate {
        case .disabled:
            phase = .disabled
        case .ineligible:
            phase = .ineligible
        case .eligible:
            phase = .idle
            startEligibilityCheck()
        }
    }

    func cancel() {
        cancelResolution()
    }

    private func startEligibilityCheck() {
        let resolutionID = UUID()
        let eligibilityChecker = eligibilityChecker
        let resolver = resolver
        let entryType = entryType
        let tmdbID = tmdbID
        let tmdbSeriesID = Self.seriesTMDbID(entryType: entryType, tmdbID: tmdbID)
        let now = now()
        let calendar = calendar
        self.resolutionID = resolutionID
        phase = .checkingEligibility

        resolutionTask = Task { [weak self] in
            do {
                guard let tmdbSeriesID else {
                    self?.phase = .ineligible
                    self?.finishResolution(resolutionID)
                    return
                }
                let eligibility = try await eligibilityChecker.check(
                    entryType: entryType,
                    tmdbSeriesID: tmdbSeriesID,
                    now: now,
                    calendar: calendar
                )
                try Task.checkCancellation()
                guard let self, self.resolutionID == resolutionID else { return }
                guard case .eligible(let externalIDs, let airingEvidence) = eligibility else {
                    self.phase = .ineligible
                    self.finishResolution(resolutionID)
                    return
                }

                self.airingEvidence = airingEvidence
                self.phase = .resolving
                let result = try await resolver.resolve(
                    entryType: entryType,
                    tmdbID: tmdbID,
                    externalIDs: externalIDs
                )
                try Task.checkCancellation()
                guard self.resolutionID == resolutionID else { return }

                switch result {
                case .resolved(let show):
                    self.resolvedShow = show
                    self.phase = .resolved(
                        BroadcastAvailability(
                            resolvedShow: show,
                            tmdbEvidence: airingEvidence
                        )
                    )
                case .requiresUserAssistance:
                    self.resolvedShow = nil
                    self.phase = .requiresUserAssistance
                case .ineligible:
                    self.resolvedShow = nil
                    self.phase = .ineligible
                }
                self.finishResolution(resolutionID)
            } catch {
                guard !Self.isCancellation(error) else { return }
                guard let self, self.resolutionID == resolutionID else { return }
                self.phase = .failed
                self.finishResolution(resolutionID)
            }
        }
    }

    func startTitleFallback(named title: String) {
        guard case .requiresUserAssistance = phase else { return }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            phase = .failed
            return
        }

        let resolutionID = UUID()
        let resolver = resolver
        self.resolutionID = resolutionID
        phase = .titleSearching

        resolutionTask = Task { [weak self] in
            do {
                let candidate = try await resolver.resolveTitleFallback(named: normalizedTitle)
                try Task.checkCancellation()
                guard let self, self.resolutionID == resolutionID else { return }

                self.phase = candidate.map(Phase.titleCandidate) ?? .failed
                self.finishResolution(resolutionID)
            } catch {
                guard !Self.isCancellation(error) else { return }
                guard let self, self.resolutionID == resolutionID else { return }
                self.phase = .failed
                self.finishResolution(resolutionID)
            }
        }
    }

    func retryTitleFallback(named title: String) {
        guard case .failed = phase else { return }
        phase = .requiresUserAssistance
        startTitleFallback(named: title)
    }

    func confirmTitleFallbackCandidate() {
        guard case .titleCandidate(let candidate) = phase else { return }
        confirm(candidate: candidate)
    }

    func confirm(candidate: TVMazeShow) {
        guard gate == .eligible else { return }

        let resolutionID = UUID()
        let resolver = resolver
        let entryType = entryType
        let tmdbID = tmdbID
        let airingEvidence = airingEvidence
        self.resolutionID = resolutionID
        phase = .titleSearching

        resolutionTask = Task { [weak self] in
            do {
                let didConfirm = try await resolver.confirmTitleFallbackCandidate(
                    candidate,
                    entryType: entryType,
                    tmdbID: tmdbID
                )
                try Task.checkCancellation()
                guard let self, self.resolutionID == resolutionID else { return }
                guard didConfirm else {
                    self.phase = .failed
                    self.finishResolution(resolutionID)
                    return
                }

                self.resolvedShow = candidate
                self.phase = .resolved(
                    BroadcastAvailability(
                        resolvedShow: candidate,
                        tmdbEvidence: airingEvidence
                    )
                )
                self.finishResolution(resolutionID)
            } catch {
                guard !Self.isCancellation(error) else { return }
                guard let self, self.resolutionID == resolutionID else { return }
                self.phase = .failed
                self.finishResolution(resolutionID)
            }
        }
    }

    func rejectTitleFallbackCandidate() {
        guard case .titleCandidate = phase else { return }
        cancelResolution()
        phase = .requiresUserAssistance
    }

    func retryAutomaticResolution() {
        guard gate == .eligible, case .failed = phase else { return }
        airingEvidence = nil
        startEligibilityCheck()
    }

    /// Availability for confirmation and review sheets.
    ///
    /// These sheets display only a concrete TVMaze `airstamp`. TMDb evidence remains available
    /// solely to validate a comparable next-episode date and explain conflicts; it must never
    /// become the displayed airtime when TVMaze has no concrete next episode. The outer menu
    /// continues to use the resolved phase's availability, where TMDb fallback remains enabled.
    func confirmationAvailability(for candidate: TVMazeShow) -> BroadcastAvailability {
        BroadcastAvailability(
            resolvedShow: candidate,
            tmdbEvidence: airingEvidence,
            allowsTMDbFallback: false
        )
    }

    func searchTitleCandidates(named title: String) async throws -> [TVMazeShow] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return [] }
        return try await resolver.searchTitleCandidates(named: normalizedTitle)
    }

    func hydrateTitleCandidate(id: Int) async throws -> TVMazeShow? {
        try await resolver.hydrateTitleCandidate(id: id)
    }

    private func cancelResolution() {
        resolutionID = nil
        resolutionTask?.cancel()
        resolutionTask = nil
    }

    private func finishResolution(_ resolutionID: UUID) {
        guard self.resolutionID == resolutionID else { return }
        self.resolutionID = nil
        resolutionTask = nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func seriesTMDbID(entryType: AnimeType, tmdbID: Int) -> Int? {
        switch entryType {
        case .series:
            tmdbID
        case .season(_, let parentSeriesID):
            parentSeriesID
        case .movie:
            nil
        }
    }
}
