//
//  LibraryProfileAiringReminderManagementPopover.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import SwiftUI

struct AiringReminderManagementItem: Equatable, Identifiable, Sendable {
    let subscription: AiringReminderSubscription
    let nextReminder: ScheduledAiringReminder?

    var id: String { subscription.id }
}

extension AiringReminderSnapshot {
    var managementItems: [AiringReminderManagementItem] {
        subscriptions.map { subscription in
            AiringReminderManagementItem(
                subscription: subscription,
                nextReminder: reminders(for: subscription.id).first
            )
        }
    }
}

struct LibraryProfileAiringReminderManagementPopover: View {
    private let airingReminders = AiringReminderCoordinator.shared

    @State private var isRemovingReminder: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Label("Manage Reminders", systemImage: "bell.badge")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Divider()

            content
        }
        .frame(minWidth: 320, idealWidth: 420, maxWidth: 420)
        .task { await airingReminders.reloadState() }
    }

    private var content: some View {
        let items = airingReminders.snapshot.managementItems

        return ZStack {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Reminders Set",
                    systemImage: "bell.slash"
                )
                .transition(.opacity)
            } else {
                List(items) { item in
                    reminderRow(item)
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

    private func reminderRow(_ item: AiringReminderManagementItem) -> some View {
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
                        Text("Next Episode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if let nextReminder = item.nextReminder {
                            Text(
                                verbatim: nextReminder.airStamp.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(.footnote)
                            .lineLimit(1)
                        } else {
                            Text("No Reminder")
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
                removeReminder(item.subscription)
            } label: {
                Image(systemName: "bell.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(.red.opacity(0.10))
                    }
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove reminder for \(item.subscription.displayTitle)"))
            .accessibilityHint(Text("Removes this reminder."))
        }
    }

    private func removeReminder(_ subscription: AiringReminderSubscription) {
        guard !isRemovingReminder else { return }
        isRemovingReminder = true
        Task {
            await airingReminders.disable(entryIdentityRawID: subscription.id)
            isRemovingReminder = false
        }
    }
}
