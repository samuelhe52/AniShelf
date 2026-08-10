//
//  TVMazeModelsTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/10.
//

import Foundation
import Testing

@testable import MyAnimeList

struct TVMazeModelsTests {
    @Test func lateNightBroadcastProvidesDisplayScheduleAndDateComponents() throws {
        let tokyoTimeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let shanghaiTimeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let show = TVMazeShow(
            id: 1,
            name: "Example",
            language: nil,
            premiered: nil,
            providerLocalSchedule: TVMazeSchedule(
                days: [.thursday],
                time: TVMazeTimeOfDay(hour: 1, minute: 30, context: .provider),
                dayOffsetFromBroadcastDay: 1
            ),
            timeZone: tokyoTimeZone,
            fullImageURL: nil,
            nextEpisodeAiring: nil
        )
        let localizedSchedule = try #require(
            show.providerLocalSchedule.localized(
                from: tokyoTimeZone,
                to: shanghaiTimeZone
            )
        )
        let dateComponents = try #require(show.dateComponents.first)

        #expect(show.providerLocalSchedule.displayTime == "25:30")
        #expect(
            localizedSchedule
                == TVMazeSchedule(
                    days: [.thursday],
                    time: TVMazeTimeOfDay(hour: 0, minute: 30, context: .deviceLocal),
                    dayOffsetFromBroadcastDay: 1
                )
        )
        #expect(localizedSchedule.displayTime == "24:30")
        #expect(TVMazeWeekday.thursday.localizedName(locale: Locale(identifier: "zh-Hans")) == "星期四")
        #expect(show.dateComponents.count == 1)
        #expect(dateComponents.calendar?.identifier == .gregorian)
        #expect(dateComponents.timeZone == tokyoTimeZone)
        #expect(dateComponents.weekday == 6)
        #expect(dateComponents.hour == 1)
        #expect(dateComponents.minute == 30)
    }

    @Test func timezoneLocalizationShiftsBroadcastDayAcrossCalendarBoundary() throws {
        let tokyoTimeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let losAngelesTimeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let summerDate = try #require(
            ISO8601DateFormatter().date(from: "2026-07-02T12:00:00Z")
        )
        let providerSchedule = TVMazeSchedule(
            days: [.thursday],
            time: TVMazeTimeOfDay(hour: 5, minute: 0, context: .provider),
            dayOffsetFromBroadcastDay: 0
        )

        let localizedSchedule = try #require(
            providerSchedule.localized(
                from: tokyoTimeZone,
                to: losAngelesTimeZone,
                at: summerDate
            )
        )

        #expect(
            localizedSchedule
                == TVMazeSchedule(
                    days: [.wednesday],
                    time: TVMazeTimeOfDay(hour: 13, minute: 0, context: .deviceLocal),
                    dayOffsetFromBroadcastDay: 0
                )
        )
        #expect(localizedSchedule.displayTime == "13:00")
    }
}
