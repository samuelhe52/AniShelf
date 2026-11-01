//
//  MacAiringReminderSettings.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/16.
//

#if os(macOS)
    import SwiftUI

    /// The Airing Reminders settings as form sections.
    ///
    /// The reminder list sits inline,
    /// where iOS opens it in a popover from a summary row, and each reminder's timing is
    /// a pop-up menu with the presets, keeping the timing sheet for custom offsets.
    struct MacAiringReminderSettings: View {
        private let airingReminders = AiringReminderCoordinator.shared

        @State private var showRemoveAllConfirmation = false
        @State private var editingSubscription: AiringReminderSubscription?
        @State private var removingReminderID: String?

        var body: some View {
            let items = airingReminders.snapshot.managementItems

            Section {
                Picker("Default Timing", selection: defaultTimingBinding) {
                    ForEach(AiringReminderTimingPreset.allCases, id: \.rawValue) { timing in
                        Text(timing.localizedResource).tag(timing)
                    }
                }
                .pickerStyle(.menu)
                .disabled(airingReminders.isRefreshing)

                if let warning = airingReminders.snapshot.warning {
                    Label(warning.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if airingReminders.lastRefreshFailed {
                    Label("Some reminders could not be refreshed.", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Airing Reminders")
            } footer: {
                Text("Get reminders for upcoming episodes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                if items.isEmpty {
                    Text("No Reminders Set")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(items) { item in
                        reminderRow(item)
                    }
                }
            } header: {
                HStack {
                    Text("Reminders")
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { _ = await airingReminders.refreshAll() }
                    }
                    .disabled(
                        airingReminders.isRefreshing
                            || items.isEmpty
                            || !airingReminders.snapshot.authorizationStatus.allowsScheduling
                    )
                    Button("Remove All", role: .destructive) {
                        showRemoveAllConfirmation = true
                    }
                    .disabled(items.isEmpty)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .animation(.default, value: items)
            .task { await airingReminders.reloadState() }
            .confirmationDialog(
                "Remove All Airing Reminders?",
                isPresented: $showRemoveAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove All", role: .destructive) {
                    Task { await airingReminders.cancelAll() }
                }
                Button("Keep Reminders", role: .cancel) {}
            } message: {
                Text("Every reminder on this device will be removed.")
            }
            .sheet(item: $editingSubscription) { subscription in
                MacAiringReminderTimingSheet(
                    subscription: subscription,
                    defaultTiming: airingReminders.snapshot.defaultTiming
                )
            }
        }

        private func reminderRow(_ item: AiringReminderManagementItem) -> some View {
            let subscription = item.subscription
            return HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.displayTitle)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        if let seasonNumber = subscription.seasonNumber {
                            Text("Season \(seasonNumber)")
                            Text(verbatim: "·")
                        }
                        if let nextReminder = item.nextReminder {
                            Text(
                                nextReminder.fireDate,
                                format: .dateTime.month(.abbreviated).day().hour().minute()
                            )
                        } else {
                            Text("No Reminder")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                timingPicker(subscription)

                Button {
                    remove(subscription)
                } label: {
                    Image(systemName: "bell.slash")
                }
                .buttonStyle(.borderless)
                .disabled(removingReminderID != nil)
                .help(Text("Remove reminder for \(subscription.displayTitle)"))
                .accessibilityLabel(Text("Remove reminder for \(subscription.displayTitle)"))
            }
        }

        private enum TimingChoice: Hashable {
            case useDefault
            case offset(Int)
            case customEditor
        }

        private func timingPicker(_ subscription: AiringReminderSubscription) -> some View {
            Picker(
                "Reminder Timing",
                selection: Binding<TimingChoice>(
                    get: { subscription.timingOffsetMinutes.map(TimingChoice.offset) ?? .useDefault },
                    set: { choice in
                        switch choice {
                        case .useDefault: setTiming(nil, for: subscription)
                        case .offset(let minutes): setTiming(minutes, for: subscription)
                        case .customEditor: editingSubscription = subscription
                        }
                    }
                )
            ) {
                Text("Use Default").tag(TimingChoice.useDefault)
                ForEach(AiringReminderTimingPreset.allCases, id: \.rawValue) { timing in
                    Text(timing.localizedResource).tag(TimingChoice.offset(timing.offsetMinutes))
                }
                if let offset = subscription.timingOffsetMinutes,
                    !AiringReminderTimingPreset.allCases.contains(where: { $0.offsetMinutes == offset })
                {
                    Text(subscription.timingLabel).tag(TimingChoice.offset(offset))
                }
                Divider()
                Text("Custom…").tag(TimingChoice.customEditor)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(airingReminders.isRefreshing)
            .accessibilityLabel(Text("Reminder Timing"))
            .accessibilityValue(Text(subscription.timingLabel))
        }

        private func setTiming(_ minutes: Int?, for subscription: AiringReminderSubscription) {
            Task { _ = await airingReminders.setTimingOffset(minutes, entryIdentityRawID: subscription.id) }
        }

        private func remove(_ subscription: AiringReminderSubscription) {
            removingReminderID = subscription.id
            Task {
                await airingReminders.disable(entryIdentityRawID: subscription.id)
                removingReminderID = nil
            }
        }

        private var defaultTimingBinding: Binding<AiringReminderTimingPreset> {
            Binding(
                get: { airingReminders.snapshot.defaultTiming },
                set: { timing in Task { await airingReminders.setDefaultTiming(timing) } }
            )
        }
    }
#endif
