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
    static var onEpisodeNotificationRefreshRequested: (() async -> Bool)?
    static var onEpisodeNotificationResponse: ((String) -> Void)?
}

fileprivate let librarySyncNotificationLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibrarySync.NotificationBridge"
)

/// Bridges CloudKit remote notifications into the async library sync trigger.
@MainActor
final class LibrarySyncNotificationBridge: NSObject, UIApplicationDelegate {
    static let episodeNotificationRefreshTaskIdentifier =
        "com.samuelhe.MyAnimeList.episode-notification-refresh"

    var onSyncRequested: (() async -> UIBackgroundFetchResult)? {
        get { LibrarySyncNotificationRouting.onSyncRequested }
        set { LibrarySyncNotificationRouting.onSyncRequested = newValue }
    }

    static func configureSyncHandler(
        _ handler: @escaping @MainActor () async -> UIBackgroundFetchResult
    ) {
        LibrarySyncNotificationRouting.onSyncRequested = handler
    }

    static func configureEpisodeNotificationHandlers(
        refresh: @escaping @MainActor () async -> Bool,
        response: @escaping @MainActor (String) -> Void
    ) {
        LibrarySyncNotificationRouting.onEpisodeNotificationRefreshRequested = refresh
        LibrarySyncNotificationRouting.onEpisodeNotificationResponse = response
    }

    static func updateEpisodeNotificationBackgroundRefresh(hasSubscriptions: Bool) {
        let scheduler = BGTaskScheduler.shared
        scheduler.cancel(taskRequestWithIdentifier: episodeNotificationRefreshTaskIdentifier)
        guard hasSubscriptions else { return }

        let request = BGAppRefreshTaskRequest(
            identifier: episodeNotificationRefreshTaskIdentifier
        )
        request.earliestBeginDate = nextEpisodeNotificationRefreshDate()
        do {
            try scheduler.submit(request)
        } catch {
            librarySyncNotificationLogger.error(
                "Failed to schedule episode notification refresh: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    nonisolated static func nextEpisodeNotificationRefreshDate(
        now: Date = .now
    ) -> Date {
        now.addingTimeInterval(6 * 60 * 60)
    }

    nonisolated static func episodeNotificationRoute(
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> String? {
        guard requestIdentifier.hasPrefix(EpisodeNotificationManager.requestIdentifierPrefix) else {
            return nil
        }
        return userInfo[EpisodeNotificationPayloadKey.subscriptionID] as? String
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerEpisodeNotificationBackgroundRefresh()
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

    private func registerEpisodeNotificationBackgroundRefresh() {
        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.episodeNotificationRefreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                Self.updateEpisodeNotificationBackgroundRefresh(hasSubscriptions: true)
                let operation = Task { @MainActor in
                    guard let handler = LibrarySyncNotificationRouting.onEpisodeNotificationRefreshRequested else {
                        return false
                    }
                    return await handler()
                }
                refreshTask.expirationHandler = {
                    operation.cancel()
                }
                refreshTask.setTaskCompleted(success: await operation.value)
            }
        }
        if !didRegister {
            librarySyncNotificationLogger.error(
                "Failed to register episode notification background refresh handler."
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
                EpisodeNotificationManager.requestIdentifierPrefix
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
            let entryIdentityRawID = Self.episodeNotificationRoute(
                requestIdentifier: response.notification.request.identifier,
                userInfo: response.notification.request.content.userInfo
            )
        else {
            return
        }
        await MainActor.run {
            LibrarySyncNotificationRouting.onEpisodeNotificationResponse?(entryIdentityRawID)
        }
    }
}
