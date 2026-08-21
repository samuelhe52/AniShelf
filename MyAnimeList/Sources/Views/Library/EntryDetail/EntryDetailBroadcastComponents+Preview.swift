//
//  EntryDetailBroadcastComponents+Preview.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/15.
//

import DataProvider
import SwiftUI

fileprivate struct EntryDetailBroadcastPolicyPreview: View {
    private let cases = BroadcastPolicyPreviewCase.fixtures

    var body: some View {
        NavigationStack {
            List(cases) { previewCase in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(previewCase.entry.name)
                            .font(.headline)
                        Text(previewCase.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Menu {
                        let broadcastContent = EntryDetailBroadcastMenuContent(
                            phase: .resolved(previewCase.availability),
                            notificationContext: EntryDetailNotificationContext(
                                entryIdentity: previewCase.entry.libraryIdentity,
                                displayTitle: previewCase.entry.name,
                                seasonNumber: previewCase.entry.type.seasonNumber,
                                resolvedShow: previewCase.resolvedShow
                            ),
                            hasNotificationSubscription: false,
                            onPresentValidation: {},
                            onRetry: {}
                        )
                        broadcastContent

                        if broadcastContent.isVisible {
                            Divider()
                        }

                        Button("Following menu action", systemImage: "photo.on.rectangle") {}
                    } label: {
                        Label("Open airtime menu", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("Broadcast Policy")
        }
    }
}

@MainActor
fileprivate struct EntryDetailBroadcastConfirmationPreview: View {
    @State private var isPresented = false
    @State private var model: EntryDetailBroadcastModel

    private let searchTitle = "You and I Are Polar Opposites"
    private let displayTitle = "正反対な君と僕"

    init() {
        let candidate = BroadcastPolicyPreviewCase.confirmationCandidate
        let details = BroadcastPolicyPreviewCase.confirmationDetails
        let now = BroadcastPolicyPreviewCase.tokyoDate(
            year: 2026,
            month: 8,
            day: 15,
            hour: 12,
            minute: 0
        )
        let eligibilityChecker = TMDbBroadcastEligibilityChecker { _ in details }
        let resolver = TVMazeResolver(
            loadMappedShowID: { _ in nil },
            saveMappedShowID: { _, _ in },
            lookupTVDBShowID: { _ in nil },
            lookupIMDbShowID: { _ in nil },
            searchShows: { _ in [candidate] },
            fetchShow: { showID in showID == candidate.id ? candidate : nil }
        )
        _model = State(
            initialValue: EntryDetailBroadcastModel(
                entryType: .series,
                tmdbID: 10_002,
                eligibilityChecker: eligibilityChecker,
                resolver: resolver,
                now: { now }
            )
        )
    }

    var body: some View {
        NavigationStack {
            Button {
                isPresented = true
            } label: {
                Text(verbatim: "Show confirmation sheet")
            }
            .buttonStyle(.borderedProminent)
            .navigationTitle(Text(verbatim: "Confirmation Preview"))
        }
        .sheet(isPresented: $isPresented) {
            EntryDetailBroadcastValidationSheet(
                model: model,
                searchTitle: searchTitle,
                displayTitle: displayTitle,
                onConfirmedMappingChange: {}
            )
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .task {
            model.update(
                .init(
                    isEnabled: true,
                    entryType: .series,
                    seriesStatus: "Returning Series"
                )
            )

            for _ in 0..<100 {
                if case .requiresUserAssistance = model.phase {
                    isPresented = true
                    return
                }
                await Task.yield()
            }
        }
    }
}

@MainActor
fileprivate struct BroadcastPolicyPreviewCase: Identifiable {
    let id: String
    let entry: AnimeEntry
    let explanation: String
    let availability: BroadcastAvailability

    var resolvedShow: TVMazeShow? {
        guard case .tvMazeNextAiring(let show, _, _) = availability else { return nil }
        return show
    }

    static let fixtures: [Self] = [
        agreeingAirstamp,
        conflictingAirstamp,
        afterMidnightAirstamp,
        expectedTMDbDate,
        unavailable
    ]

    static let confirmationCandidate = show(
        id: 89_103,
        name: "You and I Are Polar Opposites",
        scheduleDays: [.sunday],
        scheduleHour: 17,
        scheduleMinute: 0,
        fullImageURL: URL(
            string: "https://static.tvmaze.com/uploads/images/original_untouched/631/1578230.jpg"
        ),
        nextEpisodeAiring: TVMazeNextEpisodeAiring(
            seasonNumber: 2,
            episodeNumber: 7,
            airStamp: tokyoDate(
                year: 2026,
                month: 8,
                day: 16,
                hour: 17,
                minute: 0
            )
        )
    )

    static let confirmationDetails = TMDbSeriesBroadcastDetails(
        schedule: TMDbSeriesBroadcastSchedule(
            firstAirDate: TMDbCalendarDate(year: 2026, month: 7, day: 5),
            nextEpisode: TMDbNextEpisodeSchedule(
                seasonNumber: 1,
                airDate: TMDbCalendarDate(year: 2026, month: 8, day: 16)
            ),
            seasonAirDates: [:]
        ),
        externalIDs: TMDbSeriesExternalIDs(tvdbID: nil, imdbID: nil)
    )

    private static let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo")!

    private static let agreeingAirstamp = Self(
        id: "agreeing-airstamp",
        entry: entry(
            named: "正反対な君と僕",
            type: .season(seasonNumber: 1, parentSeriesID: 10_001),
            tmdbID: 10_002
        ),
        explanation: "TVMaze date agrees; its S02E07 numbering remains authoritative for display.",
        availability: availability(
            showName: "正反対な君と僕",
            scheduleDays: [.thursday],
            scheduleHour: 17,
            scheduleMinute: 0,
            seasonNumber: 2,
            episodeNumber: 7,
            airingDate: tokyoDate(year: 2026, month: 8, day: 16, hour: 17, minute: 0),
            tmdbDate: TMDbCalendarDate(year: 2026, month: 8, day: 16)
        )
    )

    private static let conflictingAirstamp = Self(
        id: "conflicting-airstamp",
        entry: entry(named: "これ描いて死ね", type: .series, tmdbID: 10_003),
        explanation: "TVMaze stays visible but its airtime is marked uncertain because TMDb expects August 21.",
        availability: availability(
            showName: "これ描いて死ね",
            scheduleDays: [.friday],
            scheduleHour: 23,
            scheduleMinute: 30,
            seasonNumber: 1,
            episodeNumber: 7,
            airingDate: tokyoDate(year: 2026, month: 8, day: 14, hour: 23, minute: 30),
            tmdbDate: TMDbCalendarDate(year: 2026, month: 8, day: 21)
        )
    )

    private static let afterMidnightAirstamp = Self(
        id: "after-midnight-airstamp",
        entry: entry(named: "さよならララ", type: .series, tmdbID: 10_004),
        explanation: "The absolute August 17 airstamp agrees despite previous-day broadcast notation.",
        availability: availability(
            showName: "さよならララ",
            scheduleDays: [.sunday],
            scheduleHour: 0,
            scheduleMinute: 30,
            scheduleDayOffset: 1,
            seasonNumber: 1,
            episodeNumber: 7,
            airingDate: tokyoDate(year: 2026, month: 8, day: 17, hour: 0, minute: 30),
            tmdbDate: TMDbCalendarDate(year: 2026, month: 8, day: 17)
        )
    )

    private static let expectedTMDbDate = Self(
        id: "expected-tmdb-date",
        entry: entry(named: "薬屋のひとりごと", type: .series, tmdbID: 10_005),
        explanation: "TVMaze has a recurring schedule but no airstamp, so only TMDb's date is expected.",
        availability: BroadcastAvailability(
            resolvedShow: show(
                id: 20_004,
                name: "薬屋のひとりごと",
                scheduleDays: [.friday, .saturday],
                scheduleHour: 22,
                scheduleMinute: 30,
                nextEpisodeAiring: nil
            ),
            tmdbEvidence: TMDbAiringEvidence(
                airDate: TMDbCalendarDate(year: 2026, month: 10, day: 1),
                basis: .nextEpisode
            )
        )
    )

    private static let unavailable = Self(
        id: "unavailable",
        entry: entry(
            named: "葬送のフリーレン Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 20_986),
            tmdbID: 10_006
        ),
        explanation: "Neither provider supplies usable future airing evidence.",
        availability: BroadcastAvailability(
            resolvedShow: show(
                id: 20_005,
                name: "葬送のフリーレン",
                scheduleDays: [],
                scheduleHour: nil,
                scheduleMinute: nil,
                nextEpisodeAiring: nil
            ),
            tmdbEvidence: nil
        )
    )

    private static func entry(
        named name: String,
        type: AnimeType,
        tmdbID: Int
    ) -> AnimeEntry {
        AnimeEntry(
            name: name,
            type: type,
            tmdbID: tmdbID,
            originalLanguageCode: "ja"
        )
    }

    private static func availability(
        showName: String,
        scheduleDays: [TVMazeWeekday],
        scheduleHour: Int,
        scheduleMinute: Int,
        scheduleDayOffset: Int = 0,
        seasonNumber: Int,
        episodeNumber: Int,
        airingDate: Date,
        tmdbDate: TMDbCalendarDate
    ) -> BroadcastAvailability {
        BroadcastAvailability(
            resolvedShow: show(
                id: 20_000 + seasonNumber * 100 + episodeNumber,
                name: showName,
                scheduleDays: scheduleDays,
                scheduleHour: scheduleHour,
                scheduleMinute: scheduleMinute,
                scheduleDayOffset: scheduleDayOffset,
                nextEpisodeAiring: TVMazeNextEpisodeAiring(
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    airStamp: airingDate
                )
            ),
            tmdbEvidence: TMDbAiringEvidence(
                airDate: tmdbDate,
                basis: .nextEpisode
            )
        )
    }

    private static func show(
        id: Int,
        name: String,
        scheduleDays: [TVMazeWeekday],
        scheduleHour: Int?,
        scheduleMinute: Int?,
        scheduleDayOffset: Int = 0,
        fullImageURL: URL? = nil,
        nextEpisodeAiring: TVMazeNextEpisodeAiring?
    ) -> TVMazeShow {
        let scheduleTime: TVMazeTimeOfDay?
        if let scheduleHour, let scheduleMinute {
            scheduleTime = TVMazeTimeOfDay(
                hour: scheduleHour,
                minute: scheduleMinute,
                context: .provider
            )
        } else {
            scheduleTime = nil
        }

        return TVMazeShow(
            id: id,
            name: name,
            language: "Japanese",
            premiered: "2026",
            providerLocalSchedule: TVMazeSchedule(
                days: scheduleDays,
                time: scheduleTime,
                dayOffsetFromBroadcastDay: scheduleDayOffset
            ),
            timeZone: tokyoTimeZone,
            fullImageURL: fullImageURL,
            nextEpisodeAiring: nextEpisodeAiring
        )
    }

    static func tokyoDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyoTimeZone
        guard
            let date = calendar.date(
                from: DateComponents(
                    timeZone: tokyoTimeZone,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        else {
            preconditionFailure("Invalid broadcast policy preview date")
        }
        return date
    }
}

#Preview("Broadcast Availability Policy") {
    EntryDetailBroadcastPolicyPreview()
        .environment(EpisodeNotificationCoordinator())
}

#Preview("Broadcast Confirmation Sheet") {
    EntryDetailBroadcastConfirmationPreview()
}
