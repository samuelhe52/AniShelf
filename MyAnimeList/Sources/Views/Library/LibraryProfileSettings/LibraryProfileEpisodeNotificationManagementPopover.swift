//
//  LibraryProfileEpisodeNotificationManagementPopover.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import SwiftUI

struct EpisodeNotificationManagementItem: Equatable, Identifiable, Sendable {
    let subscription: EpisodeNotificationSubscription
    let nextReminder: EpisodeScheduledReminder?

    var id: String { subscription.id }
}

extension EpisodeNotificationSnapshot {
    var managementItems: [EpisodeNotificationManagementItem] {
        subscriptions.map { subscription in
            EpisodeNotificationManagementItem(
                subscription: subscription,
                nextReminder: reminders(for: subscription.id).first
            )
        }
    }
}

struct LibraryProfileEpisodeNotificationManagementPopover: View {
    private let notifications = EpisodeNotificationCoordinator.shared

    @State private var isUnsubscribing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Label("Manage Subscriptions", systemImage: "bell.badge")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Divider()

            content
        }
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 420)
        .task { await notifications.reloadState() }
    }

    private var content: some View {
        let items = notifications.snapshot.managementItems

        return ZStack {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Episode Subscriptions",
                    systemImage: "bell.slash"
                )
                .transition(.opacity)
            } else {
                List(items) { item in
                    subscriptionRow(item)
                        .transition(.opacity)
                }
                .listStyle(.plain)
                .transition(.opacity)
            }
        }
        // Keep the presented popover from resizing while rows transition out.
        .frame(height: 360)
        .animation(.default, value: items)
    }

    private func subscriptionRow(_ item: EpisodeNotificationManagementItem) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.subscription.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let seasonNumber = item.subscription.seasonNumber {
                    Text("Season \(seasonNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.orange.opacity(0.10))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Reminder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let nextReminder = item.nextReminder {
                            Text(
                                verbatim: nextReminder.fireDate.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(.footnote)
                            .lineLimit(1)
                        } else {
                            Text("No Upcoming Notification")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                unsubscribe(item.subscription)
            } label: {
                Image(systemName: "bell.slash")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Unsubscribe from \(item.subscription.displayTitle)"))
            .accessibilityHint(Text("Removes this subscription and its pending reminder."))
        }
    }

    private func unsubscribe(_ subscription: EpisodeNotificationSubscription) {
        guard !isUnsubscribing else { return }
        isUnsubscribing = true
        Task {
            await notifications.disable(entryIdentityRawID: subscription.id)
            isUnsubscribing = false
        }
    }
}
