//
//  LibraryProfileAiringReminderSettingsSection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/21.
//

import SwiftUI

struct LibraryProfileAiringReminderSettingsSection: View {
    private static let minimumRefreshFeedbackDuration = Duration.milliseconds(600)
    private let airingReminders = AiringReminderCoordinator.shared

    @State private var showRemoveAllConfirmation = false
    @State private var showReminderManagement = false
    @State private var isRefreshFeedbackVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Airing Reminders",
                subtitle: "Get reminders for upcoming episodes.",
                systemImage: "bell.badge.fill",
                tint: LibraryProfileSettingsDestination.reminders.tint
            )

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Default Timing")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Menu {
                    Picker("Default Timing", selection: defaultTimingBinding) {
                        Section {
                            ForEach(AiringReminderTimingPreset.allCases.filter { $0.offsetMinutes < 0 }, id: \.rawValue)
                            {
                                defaultTiming in
                                Text(defaultTiming.localizedResource).tag(defaultTiming)
                            }
                        }
                        Section {
                            Text(AiringReminderTimingPreset.atAirtime.localizedResource)
                                .tag(AiringReminderTimingPreset.atAirtime)
                        }
                        Section {
                            ForEach(AiringReminderTimingPreset.allCases.filter { $0.offsetMinutes > 0 }, id: \.rawValue)
                            {
                                defaultTiming in
                                Text(defaultTiming.localizedResource).tag(defaultTiming)
                            }
                        }
                    }
                } label: {
                    LibraryProfileSelectionCapsule(
                        title: airingReminders.snapshot.defaultTiming.localizedResource,
                        tint: LibraryProfileSettingsDestination.reminders.tint
                    )
                }
                .customLabeledMenu()
                .disabled(airingReminders.isRefreshing)
            }

            remindersManagementButton

            if let warning = airingReminders.snapshot.warning {
                Label(
                    warning.localizedMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if airingReminders.lastRefreshFailed {
                Label("Some reminders could not be refreshed.", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    refreshAiringReminders()
                }
                .buttonStyle(
                    LibraryProfileCommandButtonStyle(
                        tint: LibraryProfileSettingsDestination.reminders.tint, filled: false)
                )
                .disabled(
                    airingReminders.isRefreshing
                        || isRefreshFeedbackVisible
                        || airingReminders.snapshot.subscriptions.isEmpty
                        || !airingReminders.snapshot.authorizationStatus.allowsScheduling
                )

                Button("Remove All", systemImage: "bell.slash", role: .destructive) {
                    showRemoveAllConfirmation = true
                }
                .buttonStyle(
                    LibraryProfileCommandButtonStyle(tint: LibraryProfileSettingsPalette.destructive, filled: false)
                )
                .disabled(airingReminders.snapshot.subscriptions.isEmpty)
            }
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileSettingsDestination.reminders.tint)
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
    }

    private func refreshAiringReminders() {
        isRefreshFeedbackVisible = true
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Self.minimumRefreshFeedbackDuration)

            _ = await airingReminders.refreshAll()

            if clock.now < deadline {
                try? await clock.sleep(until: deadline)
            }
            isRefreshFeedbackVisible = false
        }
    }

    private var remindersManagementButton: some View {
        Button {
            showReminderManagement = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                Text("Reminders")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(airingReminders.snapshot.subscriptions.count)")
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
        .accessibilityLabel(Text("Manage Reminders"))
        .accessibilityValue(Text("\(airingReminders.snapshot.subscriptions.count)"))
        .popover(isPresented: $showReminderManagement) {
            LibraryProfileAiringReminderManagementPopover()
                .presentationCompactAdaptation(.popover)
        }
    }

    private var defaultTimingBinding: Binding<AiringReminderTimingPreset> {
        Binding(
            get: { airingReminders.snapshot.defaultTiming },
            set: { defaultTiming in
                Task { await airingReminders.setDefaultTiming(defaultTiming) }
            }
        )
    }
}
