//
//  AiringReminderTimingSheet.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/9/6.
//

import SwiftUI

/// The offset as "N min before/after airtime", shared by both timing sheets.
struct AiringReminderOffsetSummary: View {
    let offset: Int

    var body: some View {
        if offset == 0 {
            Text("At airtime")
        } else if offset > 0 {
            Text("\(offset) min after")
        } else {
            Text("\(-offset) min before")
        }
    }
}

#if !os(macOS)
    struct AiringReminderTimingSheet: View {
        @Environment(\.dismiss) private var dismiss
        private let airingReminders = AiringReminderCoordinator.shared

        let subscription: AiringReminderSubscription
        @State private var useDefault: Bool
        @State private var isAfter: Bool
        @State private var hours: Int
        @State private var minutes: Int
        @State private var saveFailed = false

        init(subscription: AiringReminderSubscription, defaultTiming: AiringReminderTimingPreset) {
            self.subscription = subscription
            let offset = subscription.effectiveTimingOffsetMinutes(defaultTiming: defaultTiming)
            _useDefault = State(initialValue: subscription.timingOffsetMinutes == nil)
            _isAfter = State(initialValue: offset > 0)
            _hours = State(initialValue: abs(offset) / 60)
            _minutes = State(initialValue: abs(offset) % 60)
        }

        private var offset: Int { (hours * 60 + minutes) * (isAfter ? 1 : -1) }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 42, height: 42)
                                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                            Text(subscription.displayTitle)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Toggle(isOn: $useDefault) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Use Default")
                                    .font(.subheadline.weight(.semibold))
                                Text(airingReminders.snapshot.defaultTiming.localizedResource)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.orange)
                        .padding(16)

                        customTimingControls
                            .frame(height: useDefault ? 0 : nil, alignment: .top)
                            .opacity(useDefault ? 0 : 1)
                            .clipped()
                            .allowsHitTesting(!useDefault)
                            .accessibilityHidden(useDefault)

                        if saveFailed {
                            Text("Reminder timing could not be fully updated. Please try again.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: useDefault)
                    .padding(20)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .preferredNavigationBarScrollEdgeEffect()
                .navigationTitle("Reminder Timing")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            SheetCloseLabel(title: "Cancel")
                        }
                        .accessibilityLabel(Text("Cancel"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveTiming(useDefault: useDefault)
                        }
                        .disabled(airingReminders.isRefreshing)
                    }
                }
                .disabled(airingReminders.isRefreshing)
                .interactiveDismissDisabled(airingReminders.isRefreshing)
            }
            .presentationDetents([.fraction(0.80), .large])
            .presentationSizing(.form)
            .presentationDragIndicator(.visible)
        }

        private var customTimingControls: some View {
            VStack(spacing: 12) {
                Picker("Reminder Timing", selection: $isAfter) {
                    Text("Before Airtime").tag(false)
                    Text("After Airtime").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 0) {
                    Picker("Hours", selection: $hours) {
                        ForEach(0..<24) { Text("\($0) hr").tag($0) }
                    }
                    .frame(maxWidth: .infinity)
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<60) { Text("\($0) min").tag($0) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .clipped()

                Divider()

                AiringReminderOffsetSummary(offset: offset)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                    .animation(.default, value: offset)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }

        private func saveTiming(useDefault: Bool) {
            Task {
                if await airingReminders.setTimingOffset(
                    useDefault ? nil : offset,
                    entryIdentityRawID: subscription.id
                ) {
                    dismiss()
                } else {
                    saveFailed = true
                }
            }
        }
    }
#endif
