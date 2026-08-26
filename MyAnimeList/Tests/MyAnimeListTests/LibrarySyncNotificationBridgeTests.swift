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

    @Test func backgroundSyncExecutionEndsAfterOperationCompletes() async throws {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 42)
        var beginCount = 0
        var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
        var operationStarted = false
        var operationContinuation: CheckedContinuation<Void, Never>?
        let controller = LibrarySyncBackgroundExecutionController(
            beginBackgroundTask: { _, _ in
                beginCount += 1
                return identifier
            },
            endBackgroundTask: { endedIdentifiers.append($0) }
        )

        controller.run(
            onExpiration: {},
            operation: {
                operationStarted = true
                await withCheckedContinuation { continuation in
                    operationContinuation = continuation
                }
            }
        )
        while !operationStarted {
            await Task.yield()
        }

        #expect(beginCount == 1)
        #expect(endedIdentifiers.isEmpty)

        operationContinuation?.resume()
        for _ in 0..<10 where endedIdentifiers.isEmpty {
            await Task.yield()
        }

        #expect(endedIdentifiers == [identifier])
    }

    @Test func backgroundSyncExecutionFailedAcquisitionCancelsWithoutRunningOperation() {
        var expirationActionCount = 0
        var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
        var operationStarted = false
        let controller = LibrarySyncBackgroundExecutionController(
            beginBackgroundTask: { _, _ in .invalid },
            endBackgroundTask: { endedIdentifiers.append($0) }
        )

        controller.run(
            onExpiration: {
                expirationActionCount += 1
            },
            operation: {
                operationStarted = true
            }
        )
        #expect(expirationActionCount == 1)
        #expect(!operationStarted)
        #expect(endedIdentifiers.isEmpty)
    }

    @Test func backgroundSyncExecutionExpirationCancelsAndEndsOperation() async throws {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 43)
        var expirationHandler: LibrarySyncBackgroundExecutionController.ExpirationHandler?
        var expirationActionCount = 0
        var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
        var operationStarted = false
        var operationObservedCancellation = false
        let controller = LibrarySyncBackgroundExecutionController(
            beginBackgroundTask: { _, handler in
                expirationHandler = handler
                return identifier
            },
            endBackgroundTask: { endedIdentifiers.append($0) }
        )

        controller.run(
            onExpiration: {
                expirationActionCount += 1
            },
            operation: {
                operationStarted = true
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    operationObservedCancellation = Task.isCancelled
                }
            }
        )
        while !operationStarted {
            await Task.yield()
        }

        expirationHandler?()
        for _ in 0..<100 where !operationObservedCancellation {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(expirationActionCount == 1)
        #expect(operationObservedCancellation)
        #expect(endedIdentifiers == [identifier])
    }
}
