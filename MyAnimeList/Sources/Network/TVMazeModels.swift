//
//  TVMazeModels.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/10.
//

import Foundation

enum TVMazeWeekday: Equatable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
    case unknown(String)

    init(providerValue: String) {
        switch providerValue {
        case "Monday": self = .monday
        case "Tuesday": self = .tuesday
        case "Wednesday": self = .wednesday
        case "Thursday": self = .thursday
        case "Friday": self = .friday
        case "Saturday": self = .saturday
        case "Sunday": self = .sunday
        default: self = .unknown(providerValue)
        }
    }

    fileprivate var calendarWeekday: Int? {
        // Gregorian weekday components are one-based, with Sunday represented by 1.
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        case .unknown: nil
        }
    }

    fileprivate func shifted(by dayOffset: Int) -> Self {
        guard let calendarWeekday else { return self }
        let shiftedWeekday = ((calendarWeekday - 1 + dayOffset) % 7 + 7) % 7 + 1

        switch shiftedWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }

    var localizedName: String {
        localizedName(locale: .autoupdatingCurrent)
    }

    func localizedName(locale: Locale) -> String {
        guard let calendarWeekday else {
            if case .unknown(let providerValue) = self {
                return providerValue
            }
            return ""
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.weekdaySymbols[calendarWeekday - 1]
    }
}

struct TVMazeTimeOfDay: Equatable, Sendable {
    enum Context: Equatable, Sendable {
        case provider
        case deviceLocal
    }

    let hour: Int
    let minute: Int
    let context: Context

    init?(hour: Int, minute: Int, context: Context) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else {
            return nil
        }
        self.hour = hour
        self.minute = minute
        self.context = context
    }

    init?(providerValue: String) {
        let components = providerValue.split(separator: ":", omittingEmptySubsequences: false)
        guard
            components.count == 2,
            let hour = Int(components[0]),
            let minute = Int(components[1])
        else {
            return nil
        }

        self.init(hour: hour, minute: minute, context: .provider)
    }
}

struct TVMazeSchedule: Equatable, Sendable {
    let days: [TVMazeWeekday]
    let time: TVMazeTimeOfDay?
    let dayOffsetFromBroadcastDay: Int

    var displayTime: String? {
        guard let time else { return nil }
        let displayHour = time.hour + dayOffsetFromBroadcastDay * 24
        return String(format: "%02d:%02d", displayHour, time.minute)
    }

    func localized(
        from providerTimeZone: TimeZone,
        to deviceTimeZone: TimeZone,
        at referenceDate: Date = .now
    ) -> Self? {
        guard let time else { return self }
        guard time.context == .provider else { return self }

        let offsetMinutes =
            (deviceTimeZone.secondsFromGMT(for: referenceDate)
                - providerTimeZone.secondsFromGMT(for: referenceDate)) / 60
        let shiftedMinutes =
            dayOffsetFromBroadcastDay * 24 * 60
            + time.hour * 60
            + time.minute
            + offsetMinutes
        let calendarDayOffset = Int(floor(Double(shiftedMinutes) / Double(24 * 60)))
        let normalizedMinutes = ((shiftedMinutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        let broadcastDayOffset = normalizedMinutes < 5 * 60 ? 1 : 0
        let broadcastDayShift = calendarDayOffset - broadcastDayOffset

        guard
            let localizedTime = TVMazeTimeOfDay(
                hour: normalizedMinutes / 60,
                minute: normalizedMinutes % 60,
                context: .deviceLocal
            )
        else {
            return nil
        }

        return Self(
            days: days.map { $0.shifted(by: broadcastDayShift) },
            time: localizedTime,
            dayOffsetFromBroadcastDay: broadcastDayOffset
        )
    }
}

struct TVMazeNextEpisodeAiring: Equatable, Sendable {
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airStamp: Date
}

struct TVMazeShow: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let language: String?
    let premiered: String?
    let providerLocalSchedule: TVMazeSchedule
    let timeZone: TimeZone?
    let fullImageURL: URL?
    let nextEpisodeAiring: TVMazeNextEpisodeAiring?

    var deviceLocalBroadcastSchedule: TVMazeSchedule? {
        guard let timeZone else { return nil }
        return providerLocalSchedule.localized(
            from: timeZone,
            to: .autoupdatingCurrent
        )
    }

    var dateComponents: [DateComponents] {
        guard
            let timeZone,
            let time = providerLocalSchedule.time
        else {
            return []
        }

        return providerLocalSchedule.days.compactMap { day in
            guard let weekday = day.calendarWeekday else { return nil }

            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = timeZone
            components.weekday =
                ((weekday - 1 + providerLocalSchedule.dayOffsetFromBroadcastDay) % 7 + 7) % 7 + 1
            components.hour = time.hour
            components.minute = time.minute
            return components
        }
    }
}
