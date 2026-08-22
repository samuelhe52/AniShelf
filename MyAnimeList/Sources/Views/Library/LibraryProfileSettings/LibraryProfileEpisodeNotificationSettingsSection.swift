//
//  LibraryProfileEpisodeNotificationSettingsSection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import SwiftUI

struct LibraryProfileEpisodeNotificationSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    private static let minimumRefreshFeedbackDuration = Duration.milliseconds(650)
    private let notifications = EpisodeNotificationCoordinator.shared

    @State private var showCancelAllConfirmation = false
    @State private var showSubscriptionManagement = false
    @State private var isRefreshFeedbackVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Episode Notifications",
                subtitle: "Schedule one-time reminders from verified TVMaze next-episode airtimes.",
                systemImage: "bell.badge.fill",
                tint: .orange
            )

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Notify")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Menu {
                    Picker("Notify", selection: leadTimeBinding) {
                        ForEach(EpisodeNotificationLeadTime.allCases, id: \.rawValue) { leadTime in
                            Text(leadTime.localizedResource)
                                .tag(leadTime)
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

            subscriptionsManagementButton

            if notifications.snapshot.warning != nil {
                Label(
                    notificationWarningMessage,
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

            HStack(spacing: 10) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    refreshNotifications()
                }
                .buttonStyle(LibraryProfileCommandButtonStyle(tint: .orange, filled: false))
                .disabled(
                    notifications.isRefreshing
                        || isRefreshFeedbackVisible
                        || notifications.snapshot.subscriptions.isEmpty
                        || !notifications.snapshot.authorizationStatus.allowsScheduling
                )

                Button("Cancel All", systemImage: "bell.slash", role: .destructive) {
                    showCancelAllConfirmation = true
                }
                .buttonStyle(LibraryProfileCommandButtonStyle(tint: .red, filled: false))
                .disabled(notifications.snapshot.subscriptions.isEmpty)
            }
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .orange)
        .task { await notifications.reloadState() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await notifications.reloadState() }
        }
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

    private func refreshNotifications() {
        isRefreshFeedbackVisible = true
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Self.minimumRefreshFeedbackDuration)

            _ = await notifications.refreshAll()

            if clock.now < deadline {
                try? await clock.sleep(until: deadline)
            }
            isRefreshFeedbackVisible = false
        }
    }

    private var subscriptionsManagementButton: some View {
        Button {
            showSubscriptionManagement = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                Text("Subscriptions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(notifications.snapshot.subscriptions.count)")
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.orange.opacity(0.12))
                    }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, minHeight: 37, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.orange.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.orange.opacity(0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Manage Subscriptions"))
        .accessibilityValue(Text("\(notifications.snapshot.subscriptions.count)"))
        .popover(isPresented: $showSubscriptionManagement) {
            LibraryProfileEpisodeNotificationManagementPopover()
                .presentationCompactAdaptation(.popover)
        }
    }

    private var leadTimeBinding: Binding<EpisodeNotificationLeadTime> {
        Binding(
            get: { notifications.snapshot.leadTime },
            set: { leadTime in
                Task { await notifications.setLeadTime(leadTime) }
            }
        )
    }

    private var notificationWarningMessage: LocalizedStringResource {
        switch notifications.snapshot.warning {
        case .queueLimit:
            "iOS could not schedule every next-episode reminder. AniShelf kept the reminders with the nearest airtimes."
        case .schedulingFailure:
            "iOS rejected one or more episode reminders. Existing reminders were restored when possible."
        case nil:
            "Some episode reminders could not be scheduled."
        }
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
}
