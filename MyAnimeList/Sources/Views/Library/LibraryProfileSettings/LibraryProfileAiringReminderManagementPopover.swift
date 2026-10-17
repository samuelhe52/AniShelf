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

#if !os(macOS)
    struct LibraryProfileAiringReminderManagementPopover: View {
        private let airingReminders = AiringReminderCoordinator.shared

        @State private var isRemovingReminder: Bool = false
        @State private var editingSubscription: AiringReminderSubscription?

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
            .sheet(item: $editingSubscription) { subscription in
                AiringReminderTimingSheet(
                    subscription: subscription,
                    defaultTiming: airingReminders.snapshot.defaultTiming
                )
            }
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.subscription.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let seasonNumber = item.subscription.seasonNumber {
                        Text("Season \(seasonNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    nextReminderLabel(item)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 10) {
                    Button(role: .destructive) {
                        removeReminder(item.subscription)
                    } label: {
                        Image(systemName: "bell.slash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.78))
                            .frame(width: 34, height: 34)
                            .background(.red.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove reminder for \(item.subscription.displayTitle)"))
                    .accessibilityHint(Text("Removes this reminder."))

                    timingButton(item.subscription)
                }
            }
        }

        private func nextReminderLabel(_ item: AiringReminderManagementItem) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text("Next Reminder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextReminder = item.nextReminder {
                    Text(nextReminder.fireDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No Reminder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func timingButton(_ subscription: AiringReminderSubscription) -> some View {
            Button {
                editingSubscription = subscription
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text(subscription.timingLabel)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.orange.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(airingReminders.isRefreshing)
            .accessibilityLabel(Text("Reminder Timing"))
            .accessibilityValue(Text(subscription.timingLabel))
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
#endif
