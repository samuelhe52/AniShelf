//
//  LibrarySyncNotificationBridgeTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import Testing
import UIKit

@testable import MyAnimeList

@Suite(.serialized)
@MainActor
struct LibrarySyncNotificationBridgeTests {
    @Test func remoteNotificationWaitsForAsyncSyncResult() async throws {
        let bridge = LibrarySyncNotificationBridge()
        defer { bridge.onSyncRequested = nil }
        var syncContinuation: CheckedContinuation<UIBackgroundFetchResult, Never>?
        var syncStarted = false
        var completionResult: UIBackgroundFetchResult?

        bridge.onSyncRequested = {
            syncStarted = true
            return await withCheckedContinuation { continuation in
                syncContinuation = continuation
            }
        }

        bridge.application(
            UIApplication.shared,
            didReceiveRemoteNotification: [:],
            fetchCompletionHandler: { result in
                completionResult = result
            }
        )

        for _ in 0..<10 where !syncStarted {
            await Task.yield()
        }

        #expect(syncStarted)
        #expect(completionResult == nil)

        let continuation = try #require(syncContinuation)
        continuation.resume(returning: .failed)

        for _ in 0..<10 where completionResult == nil {
            await Task.yield()
        }

        #expect(completionResult == .failed)
    }

    @Test func remoteNotificationWithoutSyncHandlerReportsNoData() async {
        let bridge = LibrarySyncNotificationBridge()
        bridge.onSyncRequested = nil
        var completionResult: UIBackgroundFetchResult?

        bridge.application(
            UIApplication.shared,
            didReceiveRemoteNotification: [:],
            fetchCompletionHandler: { result in
                completionResult = result
            }
        )

        for _ in 0..<10 where completionResult == nil {
            await Task.yield()
        }

        #expect(completionResult == .noData)
    }

    @Test func airingReminderRouteAcceptsOnlyAniShelfAiringReminderRequests() {
        let payload: [AnyHashable: Any] = [
            AiringReminderPayloadKey.subscriptionID: "season:100:2:200"
        ]

        #expect(
            LibrarySyncNotificationBridge.airingReminderRoute(
                requestIdentifier: "AniShelf.AiringReminder.season-100-2-200.501",
                userInfo: payload
            ) == "season:100:2:200"
        )
        #expect(
            LibrarySyncNotificationBridge.airingReminderRoute(
                requestIdentifier: "CloudKit.Remote",
                userInfo: payload
            ) == nil
        )
        #expect(
            LibrarySyncNotificationBridge.airingReminderRoute(
                requestIdentifier: "AniShelf.AiringReminder.series-100.501",
                userInfo: [:]
            ) == nil
        )
    }

    @Test func airingReminderBackgroundRefreshRequestsSixHourWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(
            LibrarySyncNotificationBridge.nextAiringReminderRefreshDate(now: now)
                == now.addingTimeInterval(6 * 60 * 60)
        )
    }
}
