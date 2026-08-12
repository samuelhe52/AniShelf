//
//  EntryDetailBroadcastModel.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/12.
//

import DataProvider
import Foundation
import Observation

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
        case resolved(TVMazeShow)
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
    private var resolutionTask: Task<Void, Never>?
    private var resolutionID: UUID?

    private(set) var phase: Phase = .disabled

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
                guard case .eligible(let externalIDs) = eligibility else {
                    self.phase = .ineligible
                    self.finishResolution(resolutionID)
                    return
                }

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
                    self.phase = .resolved(show)
                case .requiresUserAssistance:
                    self.phase = .requiresUserAssistance
                case .ineligible:
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
