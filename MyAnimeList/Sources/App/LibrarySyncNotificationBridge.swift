//
//  LibrarySyncNotificationBridge.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import BackgroundTasks
import UIKit
import UserNotifications
import os

@MainActor
fileprivate enum LibrarySyncNotificationRouting {
    static var onSyncRequested: (() async -> UIBackgroundFetchResult)?
}

fileprivate let librarySyncNotificationLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibrarySync.NotificationBridge"
)

/// Bridges CloudKit remote notifications into the async library sync trigger.
@MainActor
final class LibrarySyncNotificationBridge: NSObject, UIApplicationDelegate {
    static let airingReminderRefreshTaskIdentifier =
        "com.samuelhe.MyAnimeList.airing-reminder-refresh"

    var onSyncRequested: (() async -> UIBackgroundFetchResult)? {
        get { LibrarySyncNotificationRouting.onSyncRequested }
        set { LibrarySyncNotificationRouting.onSyncRequested = newValue }
    }

    static func configureSyncHandler(
        _ handler: @escaping @MainActor () async -> UIBackgroundFetchResult
    ) {
        LibrarySyncNotificationRouting.onSyncRequested = handler
    }

    static func updateAiringReminderBackgroundRefresh(hasSubscriptions: Bool) {
        let scheduler = BGTaskScheduler.shared
        scheduler.cancel(taskRequestWithIdentifier: airingReminderRefreshTaskIdentifier)
        guard hasSubscriptions else { return }

        let request = BGAppRefreshTaskRequest(
            identifier: airingReminderRefreshTaskIdentifier
        )
        request.earliestBeginDate = nextAiringReminderRefreshDate()
        do {
            try scheduler.submit(request)
        } catch {
            librarySyncNotificationLogger.error(
                "Failed to schedule airing reminder refresh: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    nonisolated static func nextAiringReminderRefreshDate(
        now: Date = .now
    ) -> Date {
        now.addingTimeInterval(6 * 60 * 60)
    }

    nonisolated static func airingReminderRoute(
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> String? {
        guard requestIdentifier.hasPrefix(AiringReminderManager.requestIdentifierPrefix) else {
            return nil
        }
        return userInfo[AiringReminderPayloadKey.subscriptionID] as? String
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerAiringReminderBackgroundRefresh()
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        librarySyncNotificationLogger.info(
            "Registered for remote notifications with APNs."
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        librarySyncNotificationLogger.error(
            "Failed to register for remote notifications with APNs: \(error.localizedDescription, privacy: .public)"
        )
    }

    /// Forwards a silent push notification to the async sync handler.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        librarySyncNotificationLogger.info(
            "Received remote notification for iCloud library sync."
        )
        Task { @MainActor in
            guard let onSyncRequested else {
                librarySyncNotificationLogger.warning(
                    "Dropped remote notification because no sync handler was configured."
                )
                completionHandler(.noData)
                return
            }
            completionHandler(await onSyncRequested())
        }
    }

    private func registerAiringReminderBackgroundRefresh() {
        // This callback inherits MainActor isolation from the app delegate. Request the main
        // queue explicitly because nil makes BackgroundTasks invoke it on a background queue.
        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.airingReminderRefreshTaskIdentifier,
            using: .main
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                Self.updateAiringReminderBackgroundRefresh(hasSubscriptions: true)
                let operation = Task { @MainActor in
                    await AiringReminderCoordinator.shared.refreshAll()
                }
                refreshTask.expirationHandler = { @Sendable in
                    operation.cancel()
                }
                refreshTask.setTaskCompleted(success: await operation.value)
            }
        }
        if !didRegister {
            librarySyncNotificationLogger.error(
                "Failed to register airing reminder background refresh handler."
            )
        }
    }
}

extension LibrarySyncNotificationBridge: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard
            notification.request.identifier.hasPrefix(
                AiringReminderManager.requestIdentifierPrefix
            )
        else {
            return []
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let entryIdentityRawID = Self.airingReminderRoute(
                requestIdentifier: response.notification.request.identifier,
                userInfo: response.notification.request.content.userInfo
            )
        else {
            return
        }
        await MainActor.run {
            AiringReminderCoordinator.shared.receiveNotificationRoute(
                entryIdentityRawID: entryIdentityRawID
            )
        }
    }
}
