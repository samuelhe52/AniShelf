//
//  LibraryProfileEpisodeNotificationSettingsSection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import SwiftUI
import UIKit

struct LibraryProfileEpisodeNotificationSettingsSection: View {
    @Environment(EpisodeNotificationCoordinator.self) private var notifications
    @State private var showCancelAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Episode Notifications",
                subtitle: "Schedule one-time reminders from verified TVMaze next-episode airtimes.",
                systemImage: "bell.badge.fill",
                tint: .orange
            )

            LabeledContent("Permission", value: authorizationTitle)
                .font(.subheadline)

            LabeledContent("Subscriptions", value: "\(notifications.snapshot.subscriptions.count)")
                .font(.subheadline)

            LabeledContent("Pending Reminders", value: "\(notifications.snapshot.scheduledReminders.count)")
                .font(.subheadline)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Notify")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Menu {
                    ForEach(EpisodeNotificationLeadTime.allCases, id: \.rawValue) { leadTime in
                        Button {
                            Task { await notifications.setLeadTime(leadTime) }
                        } label: {
                            if leadTime == notifications.snapshot.leadTime {
                                Label(leadTime.localizedTitle, systemImage: "checkmark")
                            } else {
                                Text(leadTime.localizedTitle)
                            }
                        }
                    }
                } label: {
                    LibraryProfileSelectionCapsule(
                        title: notifications.snapshot.leadTime.localizedResource,
                        tint: .orange
                    )
                }
                .disabled(notifications.isRefreshing)
            }

            if notifications.snapshot.authorizationStatus == .denied {
                Button("Open Notification Settings", systemImage: "gear") {
                    openSystemSettings()
                }
                .font(.subheadline.weight(.semibold))
            }

            if notifications.snapshot.warning != nil {
                Label(
                    "iOS could not schedule every next-episode reminder. AniShelf kept the reminders with the nearest airtimes.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if notifications.lastRefreshFailed {
                Label("Some subscriptions could not be refreshed.", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { _ = await notifications.refreshAll() }
                }
                .disabled(
                    notifications.isRefreshing
                        || notifications.snapshot.subscriptions.isEmpty
                        || !notifications.snapshot.authorizationStatus.allowsScheduling
                )

                Spacer()

                Button("Cancel All", systemImage: "bell.slash", role: .destructive) {
                    showCancelAllConfirmation = true
                }
                .disabled(notifications.snapshot.subscriptions.isEmpty)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .orange)
        .task { await notifications.reloadState() }
        .confirmationDialog(
            "Cancel All Episode Notifications?",
            isPresented: $showCancelAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel All", role: .destructive) {
                Task { await notifications.cancelAll() }
            }
            Button("Keep Notifications", role: .cancel) {}
        } message: {
            Text("Every episode subscription and pending reminder on this device will be removed.")
        }
    }

    private var authorizationTitle: String {
        switch notifications.snapshot.authorizationStatus {
        case .notDetermined:
            String(localized: "Not Requested")
        case .denied:
            String(localized: "Blocked")
        case .authorized:
            String(localized: "Allowed")
        case .provisional:
            String(localized: "Delivered Quietly")
        case .ephemeral:
            String(localized: "Temporarily Allowed")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension EpisodeNotificationLeadTime {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .atAirtime:
            "At airtime"
        case .fiveMinutes:
            "5 minutes before"
        case .fifteenMinutes:
            "15 minutes before"
        case .thirtyMinutes:
            "30 minutes before"
        case .oneHour:
            "1 hour before"
        }
    }

    var localizedTitle: String {
        String(localized: localizedResource)
    }
}
