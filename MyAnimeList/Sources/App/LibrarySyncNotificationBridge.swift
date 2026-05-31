//
//  LibrarySyncNotificationBridge.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import UIKit

final class LibrarySyncNotificationBridge: NSObject, UIApplicationDelegate {
    var onSyncRequested: (@MainActor () async -> UIBackgroundFetchResult)?

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let onSyncRequested else {
                completionHandler(.noData)
                return
            }
            completionHandler(await onSyncRequested())
        }
    }
}
