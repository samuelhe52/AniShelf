//
//  EntryDetailAiringReminderMenu.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import DataProvider
import SwiftUI
import UIKit

struct EntryDetailAiringReminderContext {
    let entryIdentity: LibraryEntryIdentity
    let displayTitle: String
    let seasonNumber: Int?
    let resolvedShow: TVMazeShow?
}

struct EntryDetailAiringReminderMenu: View {
    @Environment(\.openURL) private var openURL
    private let airingReminders = AiringReminderCoordinator.shared

    let context: EntryDetailAiringReminderContext

    private var hasReminder: Bool {
        subscription != nil
    }

    private var subscription: AiringReminderSubscription? {
        airingReminders.snapshot.subscription(
            for: context.entryIdentity.rawID
        )
    }

    private var nextReminder: ScheduledAiringReminder? {
        airingReminders.snapshot.reminders(
            for: context.entryIdentity.rawID
        ).first
    }

    private var notificationPermissionIsDenied: Bool {
        airingReminders.snapshot.authorizationStatus == .denied
    }

    var body: some View {
        Menu {
            subscriptionStatus
            nextEpisodeStatus

            if notificationPermissionIsDenied {
                openNotificationSettingsButton
            }

            Divider()

            if hasReminder {
                removeReminderButton
            } else {
                setReminderButton
            }
        } label: {
            Label(
                EntryDetailL10n.notifications,
                systemImage: hasReminder ? "bell.badge.fill" : "bell"
            )
        }
    }

    private var subscriptionStatus: some View {
        Button(action: {}) {
            Label(
                hasReminder ? EntryDetailL10n.active : EntryDetailL10n.inactive,
                systemImage: hasReminder ? "checkmark.circle.fill" : "circle"
            )
        }
        .tint(hasReminder ? .green : .primary)
        .disabled(!hasReminder)
        .menuActionDismissBehavior(.disabled)
    }

    private var nextEpisodeStatus: some View {
        Button(action: {}) {
            Label(EntryDetailL10n.next, systemImage: "calendar.badge.clock")
            if notificationPermissionIsDenied {
                Text(EntryDetailL10n.notificationsDisabled)
            } else if let nextReminder {
                Text(verbatim: nextReminder.airStamp.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text(EntryDetailL10n.notSet)
            }
        }
        .disabled(!hasReminder)
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

    private var setReminderButton: some View {
        Button {
            guard let resolvedShow = context.resolvedShow else { return }
            Task {
                _ = await airingReminders.enable(
                    entryIdentity: context.entryIdentity,
                    showID: resolvedShow.id,
                    displayTitle: context.displayTitle,
                    seasonNumber: context.seasonNumber
                )
            }
        } label: {
            Label(EntryDetailL10n.enable, systemImage: "bell.badge")
        }
        .disabled(context.resolvedShow == nil || airingReminders.isRefreshing)
        .menuActionDismissBehavior(.disabled)
    }

    private var removeReminderButton: some View {
        Button(
            EntryDetailL10n.disable,
            systemImage: "bell.slash",
            role: .destructive
        ) {
            Task {
                await airingReminders.disable(
                    entryIdentityRawID: context.entryIdentity.rawID
                )
            }
        }
        .tint(.red)
        .disabled(airingReminders.isRefreshing)
        .menuActionDismissBehavior(.disabled)
    }
}
