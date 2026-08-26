//
//  EntryDetailBroadcastFormatting.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/16.
//

import Foundation

enum EntryDetailBroadcastFormatting {
    private static let languageCodeByEnglishName: [String: String] = {
        let englishLocale = Locale(identifier: "en")
        var result: [String: String] = [:]
        for code in Locale.LanguageCode.isoLanguageCodes {
            guard let name = englishLocale.localizedString(forLanguageCode: code.identifier) else {
                continue
            }
            result[name.lowercased()] = code.identifier
        }
        return result
    }()

    static func menuHeader(for availability: BroadcastAvailability) -> String {
        switch availability {
        case .tvMazeNextAiring(_, let airing, let assessment):
            var components: [String] = []
            if let episode = episodeSummary(airing) {
                components.append(episode)
            }
            components.append(compactDateTime(airing.airStamp))
            if case .disagrees = assessment {
                components.append("⚠︎ " + String(localized: EntryDetailL10n.uncertainAirtime))
            }
            return components.joined(separator: " · ")
        case .tmdbExpected(let evidence):
            return [
                String(localized: EntryDetailL10n.expected),
                compactCalendarDate(evidence.airDate)
            ]
            .joined(separator: " · ")
        case .unavailable:
            return String(localized: EntryDetailL10n.airtimeUnavailable)
        }
    }

    static func nextAiringDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func expectedDate(_ tmdbDate: TMDbCalendarDate) -> String {
        calendarDate(tmdbDate)
    }

    static func scheduleSummary(_ show: TVMazeShow) -> String? {
        let schedule = show.providerLocalSchedule
        let days = schedule.days.map(\.localizedName).filter { !$0.isEmpty }
        guard !days.isEmpty || schedule.displayTime != nil else { return nil }

        var components: [String] = []
        if !days.isEmpty {
            components.append(days.joined(separator: ", "))
        }
        if let displayTime = schedule.displayTime {
            components.append(displayTime)
        }
        if let timeZone = show.timeZone {
            let referenceDate = show.nextEpisodeAiring?.airStamp ?? .now
            let compactTimeZoneName =
                timeZone.abbreviation(for: referenceDate)
                ?? timeZone.localizedName(
                    for: .shortGeneric,
                    locale: .autoupdatingCurrent
                )
            if let compactTimeZoneName {
                components.append(compactTimeZoneName)
            }
        }
        return components.joined(separator: " · ")
    }

    static func localizedLanguageName(
        _ providerValue: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let normalizedValue =
            providerValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let languageCode = languageCodeByEnglishName[normalizedValue] else {
            return providerValue
        }
        return locale.localizedString(forLanguageCode: languageCode) ?? providerValue
    }

    static func episodeSummary(_ airing: TVMazeNextEpisodeAiring) -> String? {
        switch (airing.seasonNumber, airing.episodeNumber) {
        case (.some(let season), .some(let episode)):
            String(format: "S%02dE%02d", season, episode)
        case (.some(let season), nil):
            String(format: "S%02d", season)
        case (nil, .some(let episode)):
            String(format: "E%02d", episode)
        case (nil, nil):
            nil
        }
    }

    private static func compactDateTime(_ date: Date) -> String {
        let currentYear = Calendar.autoupdatingCurrent.component(.year, from: .now)
        let airingYear = Calendar.autoupdatingCurrent.component(.year, from: date)
        return localizedDate(
            date,
            template: currentYear == airingYear ? "Mdjmm" : "yMdjmm"
        )
    }

    private static func compactCalendarDate(_ tmdbDate: TMDbCalendarDate) -> String {
        let components = DateComponents(
            year: tmdbDate.year,
            month: tmdbDate.month,
            day: tmdbDate.day
        )
        guard let date = Calendar.autoupdatingCurrent.date(from: components) else {
            return String(format: "%04d-%02d-%02d", tmdbDate.year, tmdbDate.month, tmdbDate.day)
        }

        let currentYear = Calendar.autoupdatingCurrent.component(.year, from: .now)
        return localizedDate(
            date,
            template: currentYear == tmdbDate.year ? "Md" : "yMd"
        )
    }

    private static func localizedDate(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func calendarDate(_ tmdbDate: TMDbCalendarDate) -> String {
        let components = DateComponents(
            year: tmdbDate.year,
            month: tmdbDate.month,
            day: tmdbDate.day
        )
        guard let date = Calendar.autoupdatingCurrent.date(from: components) else {
            return String(format: "%04d-%02d-%02d", tmdbDate.year, tmdbDate.month, tmdbDate.day)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
