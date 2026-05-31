//
//  LibrarySyncNotificationBridge.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import UIKit

final class LibrarySyncNotificationBridge: NSObject, UIApplicationDelegate {
    var onSyncRequested: (@MainActor () -> Void)?

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        onSyncRequested?()
        completionHandler(.newData)
    }
}
