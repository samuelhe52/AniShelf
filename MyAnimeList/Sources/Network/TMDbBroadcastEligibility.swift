//
//  TMDbBroadcastEligibility.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/12.
//

import DataProvider
import Foundation

struct TMDbSeriesExternalIDs: Equatable, Sendable {
    let tvdbID: Int?
    let imdbID: String?
}

struct TMDbCalendarDate: Equatable, Sendable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(providerValue: String?) {
        guard let providerValue else { return nil }
        let components = providerValue.split(separator: "-", omittingEmptySubsequences: false)
        guard
            components.count == 3,
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dateComponents = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: dateComponents) else {
            return nil
        }
        let validatedComponents = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            validatedComponents.year == year,
            validatedComponents.month == month,
            validatedComponents.day == day
        else { return nil }

        self.init(year: year, month: month, day: day)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

struct TMDbNextEpisodeSchedule: Equatable, Sendable {
    let seasonNumber: Int
    let airDate: TMDbCalendarDate?
}

struct TMDbSeriesBroadcastSchedule: Equatable, Sendable {
    let firstAirDate: TMDbCalendarDate?
    let nextEpisode: TMDbNextEpisodeSchedule?
    let lastEpisode: TMDbNextEpisodeSchedule?
    let seasonAirDates: [Int: TMDbCalendarDate]

    init(
        firstAirDate: TMDbCalendarDate?,
        nextEpisode: TMDbNextEpisodeSchedule?,
        lastEpisode: TMDbNextEpisodeSchedule? = nil,
        seasonAirDates: [Int: TMDbCalendarDate]
    ) {
        self.firstAirDate = firstAirDate
        self.nextEpisode = nextEpisode
        self.lastEpisode = lastEpisode
        self.seasonAirDates = seasonAirDates
    }
}

struct TMDbSeriesBroadcastDetails: Equatable, Sendable {
    let schedule: TMDbSeriesBroadcastSchedule
    let externalIDs: TMDbSeriesExternalIDs
    let episodeCount: Int?
    let seasonEpisodeCounts: [Int: Int]

    init(
        schedule: TMDbSeriesBroadcastSchedule,
        externalIDs: TMDbSeriesExternalIDs,
        episodeCount: Int? = nil,
        seasonEpisodeCounts: [Int: Int] = [:]
    ) {
        self.schedule = schedule
        self.externalIDs = externalIDs
        self.episodeCount = episodeCount
        self.seasonEpisodeCounts = seasonEpisodeCounts
    }
}

struct TMDbAiringEvidence: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        case nextEpisode
        case seriesPremiere
        case seasonPremiere
        case recentEpisode
    }

    let airDate: TMDbCalendarDate
    let basis: Basis
}

enum TMDbBroadcastEligibilityResult: Equatable, Sendable {
    case eligible(
        externalIDs: TMDbSeriesExternalIDs,
        airingEvidence: TMDbAiringEvidence
    )
    case ineligible
}

struct TMDbBroadcastEligibilityChecker: Sendable {
    /// TMDb can briefly clear `next_episode_to_air` after an episode airs.
    ///
    /// Because its air dates have no time component, round the proposed two-and-a-half-week
    /// grace period up.
    static let recentEpisodeGracePeriodDays = 18

    private let fetchSeriesDetails: @Sendable (Int) async throws -> TMDbSeriesBroadcastDetails
    private let cache: TMDbBroadcastDetailsCache
    private let cacheLifetime: TimeInterval

    init() {
        self.init { tmdbSeriesID in
            try await InfoFetcher().tvSeriesBroadcastDetails(tmdbID: tmdbSeriesID)
        }
    }

    init(infoFetcher: InfoFetcher) {
        self.init { tmdbSeriesID in
            try await infoFetcher.tvSeriesBroadcastDetails(tmdbID: tmdbSeriesID)
        }
    }

    init(
        fetchSeriesDetails:
            @escaping @Sendable (Int) async throws
            -> TMDbSeriesBroadcastDetails,
        cacheLifetime: TimeInterval = 60
    ) {
        self.fetchSeriesDetails = fetchSeriesDetails
        self.cacheLifetime = cacheLifetime
        self.cache = TMDbBroadcastDetailsCache(lifetime: cacheLifetime)
    }

    func forDetailSession() -> Self {
        Self(fetchSeriesDetails: fetchSeriesDetails, cacheLifetime: cacheLifetime)
    }

    func check(
        entryType: AnimeType,
        tmdbSeriesID: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> TMDbBroadcastEligibilityResult {
        try await checkWithDetails(
            entryType: entryType,
            tmdbSeriesID: tmdbSeriesID,
            now: now,
            calendar: calendar
        ).result
    }

    func checkWithDetails(
        entryType: AnimeType,
        tmdbSeriesID: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> (result: TMDbBroadcastEligibilityResult, details: TMDbSeriesBroadcastDetails?) {
        guard entryType != .movie else { return (.ineligible, nil) }

        let details = try await cache.details(for: tmdbSeriesID, fetch: fetchSeriesDetails)
        let schedule = details.schedule
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        guard
            let year = todayComponents.year,
            let month = todayComponents.month,
            let day = todayComponents.day
        else {
            return (.ineligible, details)
        }
        let today = TMDbCalendarDate(year: year, month: month, day: day)
        let isTodayOrLater: (TMDbCalendarDate?) -> Bool = { date in
            date.map { $0 >= today } ?? false
        }
        let recentEpisodeCutoff = calendar.date(
            byAdding: .day,
            value: -Self.recentEpisodeGracePeriodDays,
            to: now
        ).flatMap { cutoff -> TMDbCalendarDate? in
            let components = calendar.dateComponents([.year, .month, .day], from: cutoff)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else { return nil }
            return TMDbCalendarDate(year: year, month: month, day: day)
        }
        let isRecent: (TMDbCalendarDate?) -> Bool = { date in
            guard let date, let recentEpisodeCutoff else { return false }
            return date >= recentEpisodeCutoff && date <= today
        }

        let airingEvidence: TMDbAiringEvidence?
        switch entryType {
        case .series:
            if let airDate = schedule.nextEpisode?.airDate, isTodayOrLater(airDate) {
                airingEvidence = TMDbAiringEvidence(
                    airDate: airDate,
                    basis: .nextEpisode
                )
            } else if let airDate = schedule.firstAirDate, isTodayOrLater(airDate) {
                airingEvidence = TMDbAiringEvidence(
                    airDate: airDate,
                    basis: .seriesPremiere
                )
            } else if let airDate = schedule.lastEpisode?.airDate, isRecent(airDate) {
                airingEvidence = TMDbAiringEvidence(
                    airDate: airDate,
                    basis: .recentEpisode
                )
            } else {
                airingEvidence = nil
            }
        case .season(let seasonNumber, _):
            if schedule.nextEpisode?.seasonNumber == seasonNumber,
                let airDate = schedule.nextEpisode?.airDate,
                isTodayOrLater(airDate)
            {
                airingEvidence = TMDbAiringEvidence(
                    airDate: airDate,
                    basis: .nextEpisode
                )
            } else if let airDate = schedule.seasonAirDates[seasonNumber],
                isTodayOrLater(airDate)
            {
                airingEvidence = TMDbAiringEvidence(
                    airDate: airDate,
                    basis: .seasonPremiere
                )
            } else if schedule.lastEpisode?.seasonNumber == seasonNumber,
                let airDate = schedule.lastEpisode?.airDate,
                isRecent(airDate)
            {
                airingEvidence = TMDbAiringEvidence(
                    airDate: airDate,
                    basis: .recentEpisode
                )
            } else {
                airingEvidence = nil
            }
        case .movie:
            airingEvidence = nil
        }

        guard let airingEvidence else { return (.ineligible, details) }
        return (
            .eligible(externalIDs: details.externalIDs, airingEvidence: airingEvidence),
            details
        )
    }
}

private actor TMDbBroadcastDetailsCache {
    private struct InFlight {
        let id: UUID
        let task: Task<TMDbSeriesBroadcastDetails, Error>
    }

    private let lifetime: TimeInterval
    private var cached: [Int: (details: TMDbSeriesBroadcastDetails, fetchedAt: Date)] = [:]
    private var inFlight: [Int: InFlight] = [:]

    init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    func details(
        for tmdbSeriesID: Int,
        fetch: @escaping @Sendable (Int) async throws -> TMDbSeriesBroadcastDetails
    ) async throws -> TMDbSeriesBroadcastDetails {
        if let cached = cached[tmdbSeriesID],
            Date().timeIntervalSince(cached.fetchedAt) < lifetime
        {
            return cached.details
        }

        let request: InFlight
        if let existing = inFlight[tmdbSeriesID] {
            request = existing
        } else {
            request = InFlight(id: UUID(), task: Task { try await fetch(tmdbSeriesID) })
            inFlight[tmdbSeriesID] = request
        }
        do {
            let details = try await request.task.value
            if inFlight[tmdbSeriesID]?.id == request.id {
                inFlight[tmdbSeriesID] = nil
                cached[tmdbSeriesID] = (details, Date())
            }
            return details
        } catch {
            if inFlight[tmdbSeriesID]?.id == request.id {
                inFlight[tmdbSeriesID] = nil
            }
            throw error
        }
    }
}

extension InfoFetcher {
    func tvSeriesBroadcastDetails(tmdbID: Int) async throws -> TMDbSeriesBroadcastDetails {
        let data = try await tmdbResponseData(
            path: "/tv/\(tmdbID)",
            queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids")]
        )
        return try JSONDecoder().decode(TMDbSeriesBroadcastResponse.self, from: data).value
    }
}

fileprivate struct TMDbSeriesBroadcastResponse: Decodable {
    let firstAirDate: String?
    let nextEpisodeToAir: TMDbNextEpisodeResponse?
    let lastEpisodeToAir: TMDbNextEpisodeResponse?
    let seasons: [TMDbSeasonScheduleResponse]
    let externalIDs: TMDbSeriesExternalIDsResponse?
    let episodeCount: Int?

    private enum CodingKeys: String, CodingKey {
        case firstAirDate = "first_air_date"
        case nextEpisodeToAir = "next_episode_to_air"
        case lastEpisodeToAir = "last_episode_to_air"
        case seasons
        case externalIDs = "external_ids"
        case episodeCount = "number_of_episodes"
    }

    var value: TMDbSeriesBroadcastDetails {
        TMDbSeriesBroadcastDetails(
            schedule: TMDbSeriesBroadcastSchedule(
                firstAirDate: TMDbCalendarDate(providerValue: firstAirDate),
                nextEpisode: nextEpisodeToAir.map {
                    TMDbNextEpisodeSchedule(
                        seasonNumber: $0.seasonNumber,
                        airDate: TMDbCalendarDate(providerValue: $0.airDate)
                    )
                },
                lastEpisode: lastEpisodeToAir.map {
                    TMDbNextEpisodeSchedule(
                        seasonNumber: $0.seasonNumber,
                        airDate: TMDbCalendarDate(providerValue: $0.airDate)
                    )
                },
                seasonAirDates: Dictionary(
                    uniqueKeysWithValues: seasons.compactMap { season in
                        TMDbCalendarDate(providerValue: season.airDate).map {
                            (season.seasonNumber, $0)
                        }
                    }
                )
            ),
            externalIDs: TMDbSeriesExternalIDs(
                tvdbID: externalIDs?.tvdbID,
                imdbID: externalIDs?.imdbID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            ),
            episodeCount: episodeCount,
            seasonEpisodeCounts: Dictionary(
                uniqueKeysWithValues: seasons.compactMap { season in
                    season.episodeCount.map { (season.seasonNumber, $0) }
                }
            )
        )
    }

}

fileprivate struct TMDbNextEpisodeResponse: Decodable {
    let seasonNumber: Int
    let airDate: String?

    private enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case airDate = "air_date"
    }
}

fileprivate struct TMDbSeasonScheduleResponse: Decodable {
    let seasonNumber: Int
    let airDate: String?
    let episodeCount: Int?

    private enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case airDate = "air_date"
        case episodeCount = "episode_count"
    }
}

fileprivate struct TMDbSeriesExternalIDsResponse: Decodable {
    let tvdbID: Int?
    let imdbID: String?

    private enum CodingKeys: String, CodingKey {
        case tvdbID = "tvdb_id"
        case imdbID = "imdb_id"
    }
}
