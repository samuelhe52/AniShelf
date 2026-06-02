//
//  LibrarySyncNotificationBridge.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import UIKit
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
    var onSyncRequested: (() async -> UIBackgroundFetchResult)? {
        get { LibrarySyncNotificationRouting.onSyncRequested }
        set { LibrarySyncNotificationRouting.onSyncRequested = newValue }
    }

    static func configureSyncHandler(
        _ handler: @escaping @MainActor () async -> UIBackgroundFetchResult
    ) {
        LibrarySyncNotificationRouting.onSyncRequested = handler
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
}
