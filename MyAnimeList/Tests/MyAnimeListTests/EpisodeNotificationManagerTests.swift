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

    @Test func managementItemsRepresentSeriesAndSeasonSubscriptionsWithNextReminders() throws {
        let series = EpisodeNotificationSubscription(
            entryIdentityRawID: "series:100",
            tvMazeShowID: 70,
            displayTitle: "Alpha Anime",
            seasonNumber: nil
        )
        let season = EpisodeNotificationSubscription(
            entryIdentityRawID: "season:200:2:100",
            tvMazeShowID: 71,
            displayTitle: "Beta Anime",
            seasonNumber: 2
        )
        let reminder = EpisodeScheduledReminder(
            id: "AniShelf.Episode.season-200",
            subscriptionID: season.id,
            seasonNumber: 2,
            episodeNumber: 1,
            airStamp: now.addingTimeInterval(86_400),
            fireDate: now.addingTimeInterval(85_500)
        )
        let snapshot = EpisodeNotificationSnapshot(
            subscriptions: [series, season],
            scheduledReminders: [reminder]
        )

        let items = snapshot.managementItems

        #expect(items.map(\.subscription) == [series, season])
        #expect(try #require(items.first).nextReminder == nil)
        #expect(try #require(items.last).nextReminder == reminder)
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

    @Test func seasonSubscriptionUsesProviderEpisodeAndChangingLeadTimeRebuildsPendingRequest() async throws {
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
        try await manager.setLeadTime(.oneHour)
        let requests = await center.allRequests()

        #expect(requests.first?.seasonNumber == 1)
        #expect(requests.first?.episodeNumber == 12)
        #expect(requests.first?.fireDate == seasonTwoAirStamp.addingTimeInterval(-60 * 60))
        #expect((await manager.snapshot()).leadTime == .oneHour)
    }

    @Test func failedLeadTimeRebuildPreservesPreviousLeadTimeAndPendingRequest() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        defaults.set(
            EpisodeNotificationLeadTime.fiveMinutes.rawValue,
            forKey: .episodeNotificationLeadTimeMinutes
        )
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let airStamp = now.addingTimeInterval(86_400)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(season: 1, number: 1, airStamp: airStamp)
        }

        _ = try await manager.enable(
            entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
            showID: 70,
            displayTitle: "Rollback Anime",
            seasonNumber: nil
        )
        let previousRequests = await center.allRequests()
        await center.failNextAdds(1)

        await #expect(throws: EpisodeNotificationManagerError.self) {
            try await manager.setLeadTime(.oneHour)
        }

        #expect(await center.allRequests() == previousRequests)
        #expect((await manager.snapshot()).leadTime == .fiveMinutes)
        #expect(
            defaults.integer(forKey: .episodeNotificationLeadTimeMinutes)
                == EpisodeNotificationLeadTime.fiveMinutes.rawValue
        )
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
        let otherIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 101)

        _ = try await manager.enable(
            entryIdentity: identity,
            showID: 70,
            displayTitle: "Reminder Anime",
            seasonNumber: nil
        )
        _ = try await manager.enable(
            entryIdentity: otherIdentity,
            showID: 71,
            displayTitle: "Other Anime",
            seasonNumber: nil
        )
        let original = await center.allRequests()
        await provider.setFails(true)
        let refreshResult = try await manager.refreshAll()
        let preserved = await center.allRequests()

        #expect(refreshResult.failedSubscriptionCount == 2)
        #expect(
            preserved.sorted { $0.subscriptionID < $1.subscriptionID }
                == original.sorted { $0.subscriptionID < $1.subscriptionID }
        )

        await manager.disable(entryIdentityRawID: identity.rawID)
        #expect(await center.allRequests().map(\.subscriptionID) == [otherIdentity.rawID])
        #expect((await manager.snapshot()).subscriptions.map(\.id) == [otherIdentity.rawID])

        await manager.disable(entryIdentityRawID: otherIdentity.rawID)
        #expect(await center.allRequests().isEmpty)
        #expect((await manager.snapshot()).subscriptions.isEmpty)
    }

    @Test func remappedSeriesDisablesOnlySubscriptionsUsingPreviousShow() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(
                season: 2,
                number: 1,
                airStamp: now.addingTimeInterval(86_400)
            )
        }
        let series = LibraryEntryIdentity(entryType: .series, tmdbID: 100)
        let seasonOne = LibraryEntryIdentity(
            entryType: .season(seasonNumber: 1, parentSeriesID: 100),
            tmdbID: 200
        )
        let seasonTwo = LibraryEntryIdentity(
            entryType: .season(seasonNumber: 2, parentSeriesID: 100),
            tmdbID: 201
        )
        let currentSeason = LibraryEntryIdentity(
            entryType: .season(seasonNumber: 3, parentSeriesID: 100),
            tmdbID: 202
        )
        let unrelatedSeries = LibraryEntryIdentity(entryType: .series, tmdbID: 101)

        for (identity, showID, title, seasonNumber) in [
            (series, 70, "Series", nil),
            (seasonOne, 70, "Season One", 1),
            (seasonTwo, 70, "Season Two", 2),
            (currentSeason, 90, "Current Season", 3),
            (unrelatedSeries, 70, "Unrelated Series", nil)
        ] {
            _ = try await manager.enable(
                entryIdentity: identity,
                showID: showID,
                displayTitle: title,
                seasonNumber: seasonNumber
            )
        }

        let didDisable = await manager.disableSubscriptions(
            forSeriesTMDbID: 100,
            matchingTVMazeShowID: 70
        )

        #expect(didDisable)
        #expect(
            Set((await manager.snapshot()).subscriptions.map(\.id))
                == Set([currentSeason.rawID, unrelatedSeries.rawID])
        )
        #expect(
            Set(await center.allRequests().map(\.subscriptionID))
                == Set([currentSeason.rawID, unrelatedSeries.rawID])
        )
    }

    @Test @MainActor func disablingMissingSubscriptionDoesNotRefreshExistingSubscriptions() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let existingSubscription = EpisodeNotificationSubscription(
            entryIdentityRawID: "series:100",
            tvMazeShowID: 70,
            displayTitle: "Existing Anime",
            seasonNumber: nil
        )
        defaults.set(
            try JSONEncoder().encode([existingSubscription]),
            forKey: .episodeNotificationSubscriptions
        )
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
        let coordinator = EpisodeNotificationCoordinator.makeForTesting(manager: manager)

        await coordinator.disable(entryIdentityRawID: "series:200")

        #expect(await provider.requestCount() == 0)
        #expect((await manager.snapshot()).subscriptions == [existingSubscription])
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
        #expect(requests.map(\.tvMazeShowID) == Array(1...64))
        #expect(result.warning == .queueLimit)
        #expect((await manager.snapshot()).warning == .queueLimit)
    }

    @Test func refreshBoundsConcurrentProviderRequests() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let subscriptions = (1...12).map { index in
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
        let provider = ConcurrentEpisodeProviderProbe(now: now)
        let manager = makeManager(defaults: defaults, center: center) { showID in
            try await provider.nextEpisode(showID: showID)
        }

        let result = try await manager.refreshAll()

        #expect(result.refreshedSubscriptionCount == subscriptions.count)
        #expect(
            await provider.maximumConcurrentRequestCount()
                == EpisodeNotificationManager.maximumConcurrentProviderRequestCount
        )
    }

    @Test func cancellationKeepsCompletedSubscriptionRefreshes() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let fastSubscription = EpisodeNotificationSubscription(
            entryIdentityRawID: "series:100",
            tvMazeShowID: 70,
            displayTitle: "Fast Anime",
            seasonNumber: nil
        )
        let slowSubscription = EpisodeNotificationSubscription(
            entryIdentityRawID: "series:101",
            tvMazeShowID: 71,
            displayTitle: "Slow Anime",
            seasonNumber: nil
        )
        defaults.set(
            try JSONEncoder().encode([fastSubscription, slowSubscription]),
            forKey: .episodeNotificationSubscriptions
        )
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        try await center.add(
            makeRequest(
                for: fastSubscription,
                episode: makeEpisode(
                    season: 1,
                    number: 1,
                    airStamp: now.addingTimeInterval(86_400)
                )
            )
        )
        try await center.add(
            makeRequest(
                for: slowSubscription,
                episode: makeEpisode(
                    season: 1,
                    number: 1,
                    airStamp: now.addingTimeInterval(86_400)
                )
            )
        )
        let manager = makeManager(defaults: defaults, center: center) { showID in
            if showID == fastSubscription.tvMazeShowID {
                return makeEpisode(
                    season: 1,
                    number: 2,
                    airStamp: now.addingTimeInterval(172_800)
                )
            }
            try await Task.sleep(for: .seconds(60))
            return makeEpisode(
                season: 1,
                number: 2,
                airStamp: now.addingTimeInterval(172_800)
            )
        }

        let refresh = Task {
            try await manager.refreshAll()
        }
        let didCommitFastRefresh = await waitUntil {
            await center.allRequests().contains {
                $0.subscriptionID == fastSubscription.id && $0.episodeNumber == 2
            }
        }
        #expect(didCommitFastRefresh)

        refresh.cancel()
        do {
            _ = try await refresh.value
            Issue.record("Expected the refresh to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let requests = await center.allRequests()
        #expect(requests.first { $0.subscriptionID == fastSubscription.id }?.episodeNumber == 2)
        #expect(requests.first { $0.subscriptionID == slowSubscription.id }?.episodeNumber == 1)
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

    @Test func refreshRemovesRequestsOrphanedByInterruptedUnsubscribe() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 100)
        let airStamp = now.addingTimeInterval(86_400)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(season: 1, number: 1, airStamp: airStamp)
        }

        _ = try await manager.enable(
            entryIdentity: identity,
            showID: 70,
            displayTitle: "Interrupted Unsubscribe",
            seasonNumber: nil
        )
        defaults.set(
            try JSONEncoder().encode([EpisodeNotificationSubscription]()),
            forKey: .episodeNotificationSubscriptions
        )
        let restoredManager = makeManager(defaults: defaults, center: center) { _ in nil }

        let result = try await restoredManager.refreshAll()

        #expect(result.refreshedSubscriptionCount == 0)
        #expect(await center.allRequests().isEmpty)
    }

    @Test func cancelAllDuringRefreshDoesNotRestoreCapturedReminder() async throws {
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
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 100)

        _ = try await manager.enable(
            entryIdentity: identity,
            showID: 70,
            displayTitle: "Cancelable Anime",
            seasonNumber: nil
        )
        await provider.setNextEpisode(
            makeEpisode(season: 1, number: 2, airStamp: now.addingTimeInterval(172_800))
        )
        await center.pauseNextAdd()

        let refresh = Task {
            try await manager.refreshAll()
        }
        await center.waitForPausedAdd()
        await manager.cancelAll()
        await center.resumePausedAdd()
        _ = try await refresh.value

        #expect((await manager.snapshot()).subscriptions.isEmpty)
        #expect(await center.allRequests().isEmpty)
    }

    @Test @MainActor func coordinatorPrunesSubscriptionsMissingFromVisibleLibrary() async throws {
        let defaults = makeDefaults()
        defer { removeDefaults(defaults) }
        let center = EpisodeNotificationCenterProbe(authorizationStatus: .authorized)
        let manager = makeManager(defaults: defaults, center: center) { _ in
            makeEpisode(
                season: 1,
                number: 1,
                airStamp: now.addingTimeInterval(86_400)
            )
        }
        let coordinator = EpisodeNotificationCoordinator.makeForTesting(manager: manager)
        let retainedIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 100)
        let missingIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 200)

        for (identity, showID, title) in [
            (retainedIdentity, 70, "Retained Anime"),
            (missingIdentity, 80, "Missing Anime")
        ] {
            _ = try await manager.enable(
                entryIdentity: identity,
                showID: showID,
                displayTitle: title,
                seasonNumber: nil
            )
        }

        await coordinator.pruneSubscriptions(
            validEntryIdentityRawIDs: Set([retainedIdentity.rawID])
        )

        #expect(Set((await manager.snapshot()).subscriptions.map(\.id)) == Set([retainedIdentity.rawID]))
        #expect(Set(await center.allRequests().map(\.subscriptionID)) == Set([retainedIdentity.rawID]))
    }

    @Test @MainActor func coordinatorCancelAllClearsRefreshFailure() async throws {
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
        let coordinator = EpisodeNotificationCoordinator.makeForTesting(manager: manager)

        _ = try await manager.enable(
            entryIdentity: LibraryEntryIdentity(entryType: .series, tmdbID: 100),
            showID: 70,
            displayTitle: "Cancelable Anime",
            seasonNumber: nil
        )
        await provider.setFails(true)

        #expect(!(await coordinator.refreshAll()))
        #expect(coordinator.lastRefreshFailed)

        await coordinator.cancelAll()

        #expect(!coordinator.lastRefreshFailed)
        #expect(coordinator.snapshot.subscriptions.isEmpty)
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

    private func makeRequest(
        for subscription: EpisodeNotificationSubscription,
        episode: TVMazeNextEpisodeAiring
    ) -> EpisodeNotificationRequest {
        EpisodeNotificationRequest(
            identifier: "AniShelf.Episode.\(subscription.id.replacingOccurrences(of: ":", with: "-"))",
            title: subscription.displayTitle,
            body: "Test reminder",
            subscriptionID: subscription.id,
            tvMazeShowID: subscription.tvMazeShowID,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
            airStamp: episode.airStamp,
            fireDate: episode.airStamp.addingTimeInterval(-15 * 60)
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<500 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
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
    private var pausesNextAdd = false
    private var isAddPaused = false
    private var pausedAddWaiter: CheckedContinuation<Void, Never>?
    private var pausedAddContinuation: CheckedContinuation<Void, Never>?

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

    func add(_ request: EpisodeNotificationRequest) async throws {
        if pausesNextAdd {
            pausesNextAdd = false
            isAddPaused = true
            pausedAddWaiter?.resume()
            pausedAddWaiter = nil
            await withCheckedContinuation { continuation in
                pausedAddContinuation = continuation
            }
            isAddPaused = false
        }
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

    func pauseNextAdd() {
        pausesNextAdd = true
    }

    func waitForPausedAdd() async {
        guard !isAddPaused else { return }
        await withCheckedContinuation { continuation in
            pausedAddWaiter = continuation
        }
    }

    func resumePausedAdd() {
        pausedAddContinuation?.resume()
        pausedAddContinuation = nil
    }
}

private actor EpisodeProviderProbe {
    enum Failure: Error {
        case unavailable
    }

    private var storedNextEpisode: TVMazeNextEpisodeAiring?
    private var fails = false
    private var requests = 0

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
        requests += 1
        guard !fails else { throw Failure.unavailable }
        return storedNextEpisode
    }

    func requestCount() -> Int {
        requests
    }
}

private actor ConcurrentEpisodeProviderProbe {
    private let now: Date
    private var activeRequestCount = 0
    private var maximumActiveRequestCount = 0

    init(now: Date) {
        self.now = now
    }

    func nextEpisode(showID: Int) async throws -> TVMazeNextEpisodeAiring? {
        activeRequestCount += 1
        maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestCount)
        defer { activeRequestCount -= 1 }

        try await Task.sleep(for: .milliseconds(50))
        return makeEpisode(
            season: 1,
            number: 1,
            airStamp: now.addingTimeInterval(86_400 + TimeInterval(showID))
        )
    }

    func maximumConcurrentRequestCount() -> Int {
        maximumActiveRequestCount
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
