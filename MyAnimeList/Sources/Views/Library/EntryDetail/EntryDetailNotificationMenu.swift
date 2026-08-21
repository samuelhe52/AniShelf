//
//  EntryDetailNotificationMenu.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import DataProvider
import SwiftUI
import UIKit

struct EntryDetailNotificationContext {
    let entryIdentity: LibraryEntryIdentity
    let displayTitle: String
    let seasonNumber: Int?
    let resolvedShow: TVMazeShow?
}

struct EntryDetailNotificationMenu: View {
    @Environment(\.openURL) private var openURL
    private let notifications = EpisodeNotificationCoordinator.shared

    let context: EntryDetailNotificationContext

    private var isSubscribed: Bool {
        subscription != nil
    }

    private var subscription: EpisodeNotificationSubscription? {
        notifications.snapshot.subscription(
            for: context.entryIdentity.rawID
        )
    }

    private var nextReminder: EpisodeScheduledReminder? {
        notifications.snapshot.reminders(
            for: context.entryIdentity.rawID
        ).first
    }

    private var notificationPermissionIsDenied: Bool {
        notifications.snapshot.authorizationStatus == .denied
    }

    var body: some View {
        Menu {
            subscriptionStatus
            nextNotificationStatus

            if notificationPermissionIsDenied {
                openNotificationSettingsButton
            }

            Divider()

            if isSubscribed {
                unsubscribeButton
            } else {
                subscribeButton
            }
        } label: {
            Label(
                EntryDetailL10n.notifications,
                systemImage: isSubscribed ? "bell.badge.fill" : "bell"
            )
        }
    }

    private var subscriptionStatus: some View {
        Button(action: {}) {
            Label(
                isSubscribed ? EntryDetailL10n.subscribed : EntryDetailL10n.notSubscribed,
                systemImage: isSubscribed ? "checkmark.circle.fill" : "circle"
            )
        }
        .tint(isSubscribed ? .green : .primary)
        .disabled(!isSubscribed)
        .menuActionDismissBehavior(.disabled)
    }

    private var nextNotificationStatus: some View {
        Button(action: {}) {
            Label(EntryDetailL10n.nextNotification, systemImage: "calendar.badge.clock")
            if notificationPermissionIsDenied {
                Text(EntryDetailL10n.notificationsDisabled)
            } else if let nextReminder {
                Text(verbatim: nextReminder.fireDate.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text(EntryDetailL10n.noUpcomingNotification)
            }
        }
        .disabled(!isSubscribed)
        .menuActionDismissBehavior(.disabled)
    }

    private var openNotificationSettingsButton: some View {
        Button {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(settingsURL)
        } label: {
            Label(EntryDetailL10n.openNotificationSettings, systemImage: "gear")
        }
    }

    private var subscribeButton: some View {
        Button {
            guard let resolvedShow = context.resolvedShow else { return }
            Task {
                _ = await notifications.enable(
                    entryIdentity: context.entryIdentity,
                    showID: resolvedShow.id,
                    displayTitle: context.displayTitle,
                    seasonNumber: context.seasonNumber
                )
            }
        } label: {
            Label(EntryDetailL10n.subscribe, systemImage: "bell.badge")
        }
        .disabled(context.resolvedShow == nil || notifications.isRefreshing)
        .menuActionDismissBehavior(.disabled)
    }

    private var unsubscribeButton: some View {
        Button(
            EntryDetailL10n.unsubscribe,
            systemImage: "bell.slash",
            role: .destructive
        ) {
            Task {
                await notifications.disable(
                    entryIdentityRawID: context.entryIdentity.rawID
                )
            }
        }
        .tint(.red)
        .disabled(notifications.isRefreshing)
        .menuActionDismissBehavior(.disabled)
    }
}
