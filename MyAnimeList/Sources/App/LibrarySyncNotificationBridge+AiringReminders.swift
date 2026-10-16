//
//  LibrarySyncNotificationBridge+AiringReminders.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

import UserNotifications

/// Airing-reminder notification handling shared by the iOS and Mac app delegates. Each
/// platform supplies `openAiringReminder(entryIdentityRawID:response:)` to pick the window.
extension LibrarySyncNotificationBridge: UNUserNotificationCenterDelegate {
    nonisolated static func airingReminderRoute(
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> String? {
        guard requestIdentifier.hasPrefix(AiringReminderManager.requestIdentifierPrefix) else {
            return nil
        }
        return userInfo[AiringReminderPayloadKey.subscriptionID] as? String
    }

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
        await openAiringReminder(entryIdentityRawID: entryIdentityRawID, response: response)
    }
}
