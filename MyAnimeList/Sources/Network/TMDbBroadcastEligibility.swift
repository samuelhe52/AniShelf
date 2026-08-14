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
    let seasonAirDates: [Int: TMDbCalendarDate]
}

struct TMDbSeriesBroadcastDetails: Equatable, Sendable {
    let schedule: TMDbSeriesBroadcastSchedule
    let externalIDs: TMDbSeriesExternalIDs
}

struct TMDbAiringEvidence: Equatable, Sendable {
    enum Basis: Equatable, Sendable {
        case nextEpisode
        case seriesPremiere
        case seasonPremiere
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
    private let fetchSeriesDetails: @Sendable (Int) async throws -> TMDbSeriesBroadcastDetails

    init(infoFetcher: InfoFetcher = InfoFetcher()) {
        self.init { tmdbSeriesID in
            try await infoFetcher.tvSeriesBroadcastDetails(tmdbID: tmdbSeriesID)
        }
    }

    init(
        fetchSeriesDetails:
            @escaping @Sendable (Int) async throws
            -> TMDbSeriesBroadcastDetails
    ) {
        self.fetchSeriesDetails = fetchSeriesDetails
    }

    func check(
        entryType: AnimeType,
        tmdbSeriesID: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> TMDbBroadcastEligibilityResult {
        guard entryType != .movie else { return .ineligible }

        let details = try await fetchSeriesDetails(tmdbSeriesID)
        let schedule = details.schedule
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        guard
            let year = todayComponents.year,
            let month = todayComponents.month,
            let day = todayComponents.day
        else {
            return .ineligible
        }
        let today = TMDbCalendarDate(year: year, month: month, day: day)
        let isTodayOrLater: (TMDbCalendarDate?) -> Bool = { date in
            date.map { $0 >= today } ?? false
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
            } else {
                airingEvidence = nil
            }
        case .movie:
            airingEvidence = nil
        }

        guard let airingEvidence else { return .ineligible }
        return .eligible(
            externalIDs: details.externalIDs,
            airingEvidence: airingEvidence
        )
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
    let seasons: [TMDbSeasonScheduleResponse]
    let externalIDs: TMDbSeriesExternalIDsResponse?

    private enum CodingKeys: String, CodingKey {
        case firstAirDate = "first_air_date"
        case nextEpisodeToAir = "next_episode_to_air"
        case seasons
        case externalIDs = "external_ids"
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

    private enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case airDate = "air_date"
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
