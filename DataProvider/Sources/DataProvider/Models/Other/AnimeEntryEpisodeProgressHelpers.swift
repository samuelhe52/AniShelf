//
//  AnimeEntryEpisodeProgressHelpers.swift
//  DataProvider
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import Foundation

public enum AnimeEntryEpisodeProgressCompletionPrompt: String, Equatable, Identifiable {
    case seasonWatched
    case seriesWatched

    public var id: String { rawValue }
}

public struct AnimeEntryEpisodeProgressSummary: Equatable {
    public let seasonNumber: Int
    public let watchedThroughEpisode: Int
    public let episodeCount: Int?
    public let updatedAt: Date

    public var seasonTitle: String {
        seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"
    }

    public func compactDisplayText(includingSeasonLabel: Bool) -> String {
        let countText: String
        if let episodeCount {
            countText = "\(watchedThroughEpisode)/\(episodeCount)"
        } else {
            countText = "\(watchedThroughEpisode)"
        }

        guard includingSeasonLabel else { return countText }
        if seasonNumber == 0 {
            return "Specials E\(countText)"
        }
        return "S\(seasonNumber) E\(countText)"
    }
}

extension AnimeEntry {
    public var orderedEpisodeProgresses: [AnimeEntryEpisodeProgress] {
        episodeProgresses
            .filter { isTrackableEpisodeProgressSeason($0.seasonNumber) }
            .sorted { lhs, rhs in
                if lhs.seasonNumber == rhs.seasonNumber {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return Self.episodeProgressSeasonSortKey(lhs.seasonNumber)
                    < Self.episodeProgressSeasonSortKey(rhs.seasonNumber)
            }
    }

    public var episodeProgressSummaries: [AnimeEntryEpisodeProgressSummary] {
        orderedEpisodeProgresses.compactMap { progress in
            guard progress.watchedThroughEpisode > 0 else { return nil }
            return AnimeEntryEpisodeProgressSummary(
                seasonNumber: progress.seasonNumber,
                watchedThroughEpisode: progress.watchedThroughEpisode,
                episodeCount: episodeProgressLimit(forSeason: progress.seasonNumber),
                updatedAt: progress.updatedAt
            )
        }
    }

    public var latestEpisodeProgressSummary: AnimeEntryEpisodeProgressSummary? {
        episodeProgressSummaries.max { $0.updatedAt < $1.updatedAt }
    }

    public var areAllNumberedEpisodeProgressSeasonsComplete: Bool {
        let numberedSeasons = episodeProgressSeasonOptions.filter { $0 > 0 }
        guard !numberedSeasons.isEmpty else { return false }

        return numberedSeasons.allSatisfy { seasonNumber in
            let summary = episodeProgressSummary(forSeason: seasonNumber)
            guard let episodeCount = summary.episodeCount, episodeCount > 0 else { return false }
            return summary.watchedThroughEpisode >= episodeCount
        }
    }

    public var episodeProgressSeasonOptions: [Int] {
        switch type {
        case .movie:
            return []
        case .season(let seasonNumber, _):
            return seasonNumber > 0 ? [seasonNumber] : []
        case .series:
            let detailSeasons = detail?.seasons.map(\.seasonNumber) ?? []
            let savedSeasons = episodeProgresses.map(\.seasonNumber)
            let childSeasons = childSeasonEntries.compactMap(\.seasonNumber)
            let seasons = Set(detailSeasons + savedSeasons + childSeasons)
                .filter { $0 > 0 }
            return seasons.sorted { lhs, rhs in
                Self.episodeProgressSeasonSortKey(lhs) < Self.episodeProgressSeasonSortKey(rhs)
            }
        }
    }

    public func episodeProgressSummary(forSeason seasonNumber: Int) -> AnimeEntryEpisodeProgressSummary {
        let watchedThroughEpisode = episodeProgress(forSeason: seasonNumber)?.watchedThroughEpisode ?? 0
        return AnimeEntryEpisodeProgressSummary(
            seasonNumber: seasonNumber,
            watchedThroughEpisode: watchedThroughEpisode,
            episodeCount: episodeProgressLimit(forSeason: seasonNumber),
            updatedAt: episodeProgress(forSeason: seasonNumber)?.updatedAt ?? .distantPast
        )
    }

    public func episodeProgress(forSeason seasonNumber: Int) -> AnimeEntryEpisodeProgress? {
        guard isTrackableEpisodeProgressSeason(normalizedEpisodeProgressSeason(seasonNumber)) else {
            return nil
        }
        return episodeProgresses.first {
            $0.seasonNumber == normalizedEpisodeProgressSeason(seasonNumber)
        }
    }

    /// Applies one persisted or remote progress value without changing the
    /// entry's top-level tracking clock.
    ///
    /// Use this for replay-style flows such as sync import, restore, or
    /// rebuilding an entry from a `UserEntryInfo` snapshot that already carries
    /// its own clock semantics. For user actions, prefer
    /// `updateEpisodeProgress(seasonNumber:watchedThroughEpisode:at:)` so
    /// `trackingUpdatedAt` advances with the change.
    public func applyEpisodeProgressSnapshot(
        seasonNumber requestedSeasonNumber: Int,
        watchedThroughEpisode requestedEpisode: Int,
        updatedAt: Date = .now
    ) {
        guard let seasonNumber = progressWritableSeasonNumber(requestedSeasonNumber) else { return }
        let episode = clampedEpisodeProgress(requestedEpisode, seasonNumber: seasonNumber)

        if episode <= 0 {
            for progress in episodeProgresses where progress.seasonNumber == seasonNumber {
                modelContext?.delete(progress)
            }
            episodeProgresses.removeAll { $0.seasonNumber == seasonNumber }
            return
        }

        if let progress = episodeProgress(forSeason: seasonNumber) {
            progress.watchedThroughEpisode = episode
            progress.updatedAt = updatedAt
        } else {
            let progress = AnimeEntryEpisodeProgress(
                seasonNumber: seasonNumber,
                watchedThroughEpisode: episode,
                updatedAt: updatedAt
            )
            progress.entry = self
            episodeProgresses.append(progress)
        }
    }

    @discardableResult
    public func updateEpisodeProgress(
        seasonNumber requestedSeasonNumber: Int,
        watchedThroughEpisode requestedEpisode: Int,
        at date: Date = .now
    ) -> Bool {
        guard let seasonNumber = progressWritableSeasonNumber(requestedSeasonNumber) else { return false }
        let episode = clampedEpisodeProgress(requestedEpisode, seasonNumber: seasonNumber)
        let currentEpisode = episodeProgress(forSeason: seasonNumber)?.watchedThroughEpisode ?? 0
        guard currentEpisode != episode else { return false }

        applyEpisodeProgressSnapshot(
            seasonNumber: seasonNumber,
            watchedThroughEpisode: episode,
            updatedAt: date
        )
        markTrackingModified(at: date)
        return true
    }

    /// Low-level convenience for replay-style progress mutation.
    ///
    /// This does not advance `trackingUpdatedAt`. User-facing changes should go
    /// through `updateEpisodeProgress(seasonNumber:watchedThroughEpisode:at:)`.
    public func incrementEpisodeProgress(seasonNumber: Int, by amount: Int = 1, now: Date = .now) {
        let current = episodeProgress(forSeason: seasonNumber)?.watchedThroughEpisode ?? 0
        applyEpisodeProgressSnapshot(
            seasonNumber: seasonNumber,
            watchedThroughEpisode: current + amount,
            updatedAt: now
        )
    }

    /// Low-level convenience for replay-style progress mutation.
    ///
    /// This does not advance `trackingUpdatedAt`. User-facing changes should go
    /// through `updateEpisodeProgress(seasonNumber:watchedThroughEpisode:at:)`.
    public func clearEpisodeProgress(seasonNumber: Int) {
        applyEpisodeProgressSnapshot(seasonNumber: seasonNumber, watchedThroughEpisode: 0)
    }

    public func episodeProgressCompletionPrompt(
        forSeason seasonNumber: Int,
        previousWatchedThroughEpisode: Int
    ) -> AnimeEntryEpisodeProgressCompletionPrompt? {
        guard watchStatus == .watching else { return nil }

        let summary = episodeProgressSummary(forSeason: seasonNumber)
        guard
            let episodeCount = summary.episodeCount,
            episodeCount > 0,
            previousWatchedThroughEpisode < episodeCount,
            summary.watchedThroughEpisode >= episodeCount
        else {
            return nil
        }

        switch type {
        case .movie:
            return nil
        case .season(let entrySeasonNumber, _):
            guard entrySeasonNumber == seasonNumber else { return nil }
            return .seasonWatched
        case .series:
            return areAllNumberedEpisodeProgressSeasonsComplete ? .seriesWatched : nil
        }
    }

    public func episodeProgressLimit(forSeason requestedSeasonNumber: Int) -> Int? {
        let seasonNumber = normalizedEpisodeProgressSeason(requestedSeasonNumber)
        guard isTrackableEpisodeProgressSeason(seasonNumber) else { return nil }
        switch type {
        case .movie:
            return nil
        case .season(let entrySeasonNumber, _):
            guard seasonNumber == entrySeasonNumber else { return nil }
            return detail?.knownEpisodeProgressLimit
        case .series:
            guard seasonNumber != 0 else { return nil }
            if let seasonLimit = detail?.seasons.first(where: { $0.seasonNumber == seasonNumber })?
                .episodeCount,
                seasonLimit > 0
            {
                return seasonLimit
            }

            if let childSeasonLimit =
                childSeasonEntries
                .first(where: { $0.seasonNumber == seasonNumber })?
                .detail?
                .knownEpisodeProgressLimit
            {
                return childSeasonLimit
            }

            let numberedSeasons = detail?.seasons.filter { $0.seasonNumber != 0 } ?? []
            if numberedSeasons.count == 1, numberedSeasons.first?.seasonNumber == seasonNumber {
                return detail?.knownEpisodeProgressLimit
            }
            return nil
        }
    }

    private func progressWritableSeasonNumber(_ requestedSeasonNumber: Int) -> Int? {
        switch type {
        case .movie:
            return nil
        case .series:
            return requestedSeasonNumber > 0 ? requestedSeasonNumber : nil
        case .season(let seasonNumber, _):
            return seasonNumber > 0 ? seasonNumber : nil
        }
    }

    private func normalizedEpisodeProgressSeason(_ requestedSeasonNumber: Int) -> Int {
        switch type {
        case .season(let seasonNumber, _):
            return seasonNumber
        default:
            return requestedSeasonNumber
        }
    }

    private func clampedEpisodeProgress(_ episode: Int, seasonNumber: Int) -> Int {
        let lowerBounded = max(0, episode)
        guard let limit = episodeProgressLimit(forSeason: seasonNumber) else { return lowerBounded }
        return min(lowerBounded, max(0, limit))
    }

    private func isTrackableEpisodeProgressSeason(_ seasonNumber: Int) -> Bool {
        switch type {
        case .movie:
            false
        case .series:
            seasonNumber > 0
        case .season(let entrySeasonNumber, _):
            seasonNumber > 0 && seasonNumber == entrySeasonNumber
        }
    }

    private static func episodeProgressSeasonSortKey(_ seasonNumber: Int) -> Int {
        seasonNumber == 0 ? Int.max : seasonNumber
    }
}

extension AnimeEntryDetail {
    fileprivate var knownEpisodeProgressLimit: Int? {
        if let episodeCount, episodeCount > 0 {
            return episodeCount
        }

        let listedEpisodeCount = episodes.count
        return listedEpisodeCount > 0 ? listedEpisodeCount : nil
    }
}
