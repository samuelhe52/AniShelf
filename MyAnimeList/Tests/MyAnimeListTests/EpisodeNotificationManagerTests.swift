//
//  EpisodeNotificationManagerTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import DataProvider
import Foundation
import Testing
import UserNotifications

@testable import MyAnimeList

struct EpisodeNotificationManagerTests {
    private let now = Date(timeIntervalSince1970: 1_776_945_600)

    @Test func systemTriggerUsesAbsoluteOneShotDate() throws {
        let fireDate = Date(timeIntervalSince1970: 2_000_000_000)
        let trigger = SystemEpisodeNotificationCenter.calendarTrigger(for: fireDate)

        #expect(!trigger.repeats)
        #expect(try #require(trigger.nextTriggerDate()) == fireDate)
    }

    @Test func systemNotificationContentUsesAnimeTitleAndNumberedEpisodeBody() {
        let request = EpisodeNotificationRequest(
            identifier: "AniShelf.Episode.series-100",
            title: "Reminder Anime",
            body: "S01E06 airs in 15 minutes.",
            subscriptionID: "series:100",
            tvMazeShowID: 70,
            seasonNumber: 1,
            episodeNumber: 6,
            airStamp: now.addingTimeInterval(86_400),
            fireDate: now.addingTimeInterval(85_500)
        )

        let content = SystemEpisodeNotificationCenter.notificationContent(for: request)

        #expect(content.title == "Reminder Anime")
        #expect(content.subtitle.isEmpty)
        #expect(content.body == "S01E06 airs in 15 minutes.")
    }

    @Test func enablingRequestsPermissionPersistsIntentAndSchedulesExactLeadTime() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(
            authorizationStatus: .notDetermined,
            authorizationAfterRequest: .authorized
        )
        let airStamp = now.addingTimeInterval(7 * 24 * 60 * 60)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(season: 1, number: 6, airStamp: airStamp)
        }
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 100)

        let result = try await manager.enable(
            entryIdentity: identity,
            showID: 70,
            displayTitle: "Reminder Anime",
            seasonNumber: nil
        )
        let requests = await center.allRequests()
        let request = try #require(requests.first)
        let snapshot = await manager.snapshot()

        #expect(result == .enabled)
        #expect(await center.authorizationRequestCount() == 1)
        #expect(snapshot.leadTime == .fifteenMinutes)
        #expect(snapshot.subscriptions.map(\.id) == [identity.rawID])
        #expect(request.identifier == "AniShelf.Episode.series-100")
        #expect(request.fireDate == airStamp.addingTimeInterval(-15 * 60))
        #expect(request.airStamp == airStamp)
        #expect(request.seasonNumber == 1)
        #expect(request.episodeNumber == 6)
    }

    @Test func deniedPermissionDoesNotCreateSubscription() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(
            authorizationStatus: .notDetermined,
            authorizationAfterRequest: .denied
        )
        let manager = makeManager(defaults: defaults, center: center) { _ in nil }

        let result = try await manager.enable(
            entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
            showID: 70,
            displayTitle: "Denied Anime",
            seasonNumber: nil
        )

        #expect(result == .denied)
        #expect((await manager.snapshot()).subscriptions.isEmpty)
        #expect(await center.allRequests().isEmpty)
    }

    @Test func authorizationRequestFailureDoesNotCreateSubscription() async {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(
            authorizationStatus: .notDetermined,
            authorizationRequestFails: true
        )
        let manager = makeManager(defaults: defaults, center: center) { _ in nil }

        await #expect(throws: EpisodeNotificationCenterProbe.Failure.self) {
            try await manager.enable(
                entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
                showID: 70,
                displayTitle: "Unavailable Permission",
                seasonNumber: nil
            )
        }
        #expect((await manager.snapshot()).subscriptions.isEmpty)
    }

    @Test(
        arguments: [
            EpisodeNotificationAuthorizationStatus.authorized,
            .provisional,
            .ephemeral
        ]
    )
    func everyAllowedAuthorizationSchedulesWithoutPrompt(
        authorizationStatus: EpisodeNotificationAuthorizationStatus
    ) async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: authorizationStatus)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(season: 1, number: 1, airStamp: now.addingTimeInterval(86_400))
        }

        let result = try await manager.enable(
            entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
            showID: 70,
            displayTitle: "Allowed Anime",
            seasonNumber: nil
        )

        #expect(result == .enabled)
        #expect(await center.authorizationRequestCount() == 0)
        #expect(await center.allRequests().count == 1)
    }

    @Test func seasonSubscriptionFiltersNextEpisodeAndChangingLeadTimeRebuildsPendingRequest() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let seasonTwoAirStamp = now.addingTimeInterval(6 * 24 * 60 * 60)
        let provider = EpisodeProviderProbe(
            nextEpisode: makeEpisode(season: 1, number: 12, airStamp: seasonTwoAirStamp)
        )
        let manager = makeManager(defaults: defaults, center: center) { showID in
            try await provider.nextEpisode(showID: showID)
        }
        let identity = LibraryEntryIdentity(
            entryType: .season(seasonNumber: 2, parentSeriesID: 100),
            tmdbID: 200
        )

        _ = try await manager.enable(
            entryIdentity: identity,
            showID: 70,
            displayTitle: "Season Two",
            seasonNumber: 2
        )
        #expect(await center.allRequests().isEmpty)

        await provider.setNextEpisode(
            makeEpisode(season: 2, number: 1, airStamp: seasonTwoAirStamp)
        )
        _ = try await manager.refreshAll()
        try await manager.setLeadTime(.oneHour)
        let requests = await center.allRequests()

        #expect(requests.first?.fireDate == seasonTwoAirStamp.addingTimeInterval(-60 * 60))
        #expect((await manager.snapshot()).leadTime == .oneHour)
    }

    @Test func failedRefreshPreservesExistingRequestsAndDisableCancelsOnlyItsSubscription() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let provider = EpisodeProviderProbe(
            nextEpisode: makeEpisode(
                season: 1,
                number: 6,
                airStamp: now.addingTimeInterval(86_400)
            )
        )
        let manager = makeManager(defaults: defaults, center: center) { showID in
            try await provider.nextEpisode(showID: showID)
        }
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 100)

        _ = try await manager.enable(
            entryIdentity: identity,
            showID: 70,
            displayTitle: "Reminder Anime",
            seasonNumber: nil
        )
        let original = await center.allRequests()
        await provider.setFails(true)
        let refreshResult = try await manager.refreshAll()

        #expect(refreshResult.failedSubscriptionCount == 1)
        #expect(await center.allRequests() == original)

        await manager.disable(entryIdentityRawID: identity.rawID)
        #expect(await center.allRequests().isEmpty)
        #expect((await manager.snapshot()).subscriptions.isEmpty)
    }

    @Test func nextEpisodeOnlySchedulingRespectsCapacityAndWarnsAboutOverflow() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let subscriptions = (1...70).map { index in
            EpisodeNotificationSubscription(
                entryIdentityRawID: "series:\(index)",
                tvMazeShowID: index,
                displayTitle: "Anime \(index)",
                seasonNumber: nil
            )
        }
        defaults.set(
            try JSONEncoder().encode(subscriptions),
            forKey: .episodeNotificationSubscriptions
        )
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let manager = makeManager(defaults: defaults, center: center) { showID in
            makeEpisode(
                season: 1,
                number: 1,
                airStamp: now.addingTimeInterval(86_400 + TimeInterval(showID))
            )
        }

        let result = try await manager.refreshAll()
        let requests = await center.allRequests()
        let grouped = Dictionary(grouping: requests, by: \.subscriptionID)

        #expect(requests.count == EpisodeNotificationManager.maximumPendingRequestCount)
        #expect(grouped.count == EpisodeNotificationManager.maximumPendingRequestCount)
        #expect(grouped.values.allSatisfy { $0.count == 1 })
        #expect(result.warning == .queueLimit)
        #expect((await manager.snapshot()).warning == .queueLimit)
    }

    @Test func schedulingFailureRestoresPreviousPendingRequests() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let provider = EpisodeProviderProbe(
            nextEpisode: makeEpisode(
                season: 1,
                number: 1,
                airStamp: now.addingTimeInterval(86_400)
            )
        )
        let manager = makeManager(defaults: defaults, center: center) { showID in
            try await provider.nextEpisode(showID: showID)
        }

        _ = try await manager.enable(
            entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
            showID: 70,
            displayTitle: "Rollback Anime",
            seasonNumber: nil
        )
        let previousRequests = await center.allRequests()
        await provider.setNextEpisode(
            makeEpisode(season: 1, number: 2, airStamp: now.addingTimeInterval(172_800))
        )
        await center.failNextAdds(1)

        await #expect(throws: EpisodeNotificationManagerError.self) {
            try await manager.refreshAll()
        }

        #expect(await center.allRequests() == previousRequests)
        #expect((await manager.snapshot()).warning == .schedulingFailure)
    }

    @Test func cancelAllClearsSubscriptionsRequestsAndWarning() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(season: 1, number: 1, airStamp: now.addingTimeInterval(86_400))
        }

        _ = try await manager.enable(
            entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
            showID: 70,
            displayTitle: "Cancelable Anime",
            seasonNumber: nil
        )
        defaults.set(EpisodeNotificationWarning.queueLimit.rawValue, forKey: .episodeNotificationWarning)

        await manager.cancelAll()
        let snapshot = await manager.snapshot()

        #expect(snapshot.subscriptions.isEmpty)
        #expect(snapshot.scheduledReminders.isEmpty)
        #expect(snapshot.warning == nil)
    }

    private func makeManager(
        defaults: UserDefaults,
        center: EpisodeNotificationCenterProbe,
        fetchNextEpisode: @escaping @Sendable (Int) async throws -> TVMazeNextEpisodeAiring?
    ) -> EpisodeNotificationManager {
        EpisodeNotificationManager(
            defaults: defaults,
            notificationCenter: center,
            now: { now },
            fetchNextEpisode: fetchNextEpisode
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "EpisodeNotificationManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "EpisodeNotificationManagerTests.SuiteName")
        return defaults
    }

    private func removeDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "EpisodeNotificationManagerTests.SuiteName") else {
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private actor EpisodeNotificationCenterProbe: EpisodeNotificationCenter {
    enum Failure: Error {
        case unavailable
    }

    private var status: EpisodeNotificationAuthorizationStatus
    private let authorizationAfterRequest: EpisodeNotificationAuthorizationStatus
    private let authorizationRequestFails: Bool
    private var requests: [String: EpisodeNotificationRequest] = [:]
    private var requestCount = 0
    private var addFailuresRemaining = 0

    init(
        authorizationStatus: EpisodeNotificationAuthorizationStatus,
        authorizationAfterRequest: EpisodeNotificationAuthorizationStatus? = nil,
        authorizationRequestFails: Bool = false
    ) {
        status = authorizationStatus
        self.authorizationAfterRequest = authorizationAfterRequest ?? authorizationStatus
        self.authorizationRequestFails = authorizationRequestFails
    }

    func authorizationStatus() -> EpisodeNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() throws -> Bool {
        requestCount += 1
        if authorizationRequestFails { throw Failure.unavailable }
        status = authorizationAfterRequest
        return status.allowsScheduling
    }

    func pendingRequests() -> [EpisodeNotificationRequest] {
        requests.values.sorted { $0.fireDate < $1.fireDate }
    }

    func add(_ request: EpisodeNotificationRequest) throws {
        if addFailuresRemaining > 0 {
            addFailuresRemaining -= 1
            throw Failure.unavailable
        }
        requests[request.identifier] = request
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers {
            requests.removeValue(forKey: identifier)
        }
    }

    func allRequests() -> [EpisodeNotificationRequest] {
        requests.values.sorted { $0.fireDate < $1.fireDate }
    }

    func authorizationRequestCount() -> Int {
        requestCount
    }

    func failNextAdds(_ count: Int) {
        addFailuresRemaining = count
    }
}

private actor EpisodeProviderProbe {
    enum Failure: Error {
        case unavailable
    }

    private var storedNextEpisode: TVMazeNextEpisodeAiring?
    private var fails = false

    init(nextEpisode: TVMazeNextEpisodeAiring?) {
        storedNextEpisode = nextEpisode
    }

    func setFails(_ newValue: Bool) {
        fails = newValue
    }

    func setNextEpisode(_ newValue: TVMazeNextEpisodeAiring?) {
        storedNextEpisode = newValue
    }

    func nextEpisode(showID: Int) throws -> TVMazeNextEpisodeAiring? {
        guard !fails else { throw Failure.unavailable }
        return storedNextEpisode
    }
}

fileprivate func makeEpisode(
    season: Int?,
    number: Int?,
    airStamp: Date
) -> TVMazeNextEpisodeAiring {
    TVMazeNextEpisodeAiring(
        seasonNumber: season,
        episodeNumber: number,
        airStamp: airStamp
    )
}
