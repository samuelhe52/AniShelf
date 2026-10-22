//
//  MacAiringReminderTimingSheet.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import SwiftUI

#if os(macOS)
    /// Sets a custom reminder offset with a Clock-style duration editor.
    struct MacAiringReminderTimingSheet: View {
        @Environment(\.dismiss) private var dismiss
        private let airingReminders = AiringReminderCoordinator.shared

        let subscription: AiringReminderSubscription
        @State private var isAfter: Bool
        @State private var hours: Int
        @State private var minutes: Int
        @State private var saveFailed = false

        init(subscription: AiringReminderSubscription, defaultTiming: AiringReminderTimingPreset) {
            self.subscription = subscription
            let offset = subscription.effectiveTimingOffsetMinutes(defaultTiming: defaultTiming)
            _isAfter = State(initialValue: offset > 0)
            _hours = State(initialValue: abs(offset) / 60)
            _minutes = State(initialValue: abs(offset) % 60)
        }

        private var offset: Int { (hours * 60 + minutes) * (isAfter ? 1 : -1) }

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reminder Timing")
                        .font(.title2.weight(.semibold))
                    Text(subscription.displayTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 16) {
                    Picker("Remind Me", selection: $isAfter) {
                        Text("Before Airtime").tag(false)
                        Text("After Airtime").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    MacReminderOffsetPicker(hours: $hours, minutes: $minutes)
                        .padding(.vertical, 4)

                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "bell")
                            .accessibilityHidden(true)
                        AiringReminderOffsetSummary(offset: offset)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.default, value: offset)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }

                if saveFailed {
                    Text("Reminder timing could not be fully updated. Please try again.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { saveTiming() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!(0...23).contains(hours) || !(0...59).contains(minutes))
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 420)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(airingReminders.isRefreshing)
            .interactiveDismissDisabled(airingReminders.isRefreshing)
        }

        private func saveTiming() {
            Task {
                if await airingReminders.setTimingOffset(offset, entryIdentityRawID: subscription.id) {
                    dismiss()
                } else {
                    saveFailed = true
                }
            }
        }
    }

    /// A duration editor whose selected component is replaced as a whole, like Clock.
    fileprivate struct MacReminderOffsetPicker: View {
        @Binding var hours: Int
        @Binding var minutes: Int

        private enum Component: Hashable {
            case hours, minutes

            var title: LocalizedStringResource {
                switch self {
                case .hours: "Hours"
                case .minutes: "Minutes"
                }
            }

            var upperBound: Int { self == .hours ? 23 : 59 }
        }

        @FocusState private var selection: Component?
        @State private var enteredDigits = ""

        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 24) {
                    Text(Component.hours.title).frame(width: 100)
                    Text(Component.minutes.title).frame(width: 100)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 2) {
                    segment(.hours)
                    VStack(spacing: 12) {
                        Circle().frame(width: 4, height: 4)
                        Circle().frame(width: 4, height: 4)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 80)
                    .accessibilityHidden(true)
                    segment(.minutes)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear { selection = .hours }
            .onChange(of: selection) { enteredDigits = "" }
        }

        private func segment(_ component: Component) -> some View {
            Text(value(for: component), format: .number.precision(.integerLength(2)).grouping(.never))
                .font(.system(size: 64, weight: .light))
                .monospacedDigit()
                .foregroundStyle(selection == component ? Color.white : Color.primary)
                .frame(width: 100, height: 80)
                .background(
                    selection == component ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
                .focusable(interactions: .edit)
                .focused($selection, equals: component)
                .focusEffectDisabled()
                .onTapGesture {
                    selection = component
                    enteredDigits = ""
                }
                .help(Text(LocalizedStringResource("Type a value, or use the Up and Down arrow keys.")))
                .accessibilityLabel(Text(component.title))
                .accessibilityValue(Text(value(for: component), format: .number))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    selection = component
                    enteredDigits = ""
                }
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(component, by: 1)
                    case .decrement: adjust(component, by: -1)
                    @unknown default: break
                    }
                }
                .onKeyPress(characters: .decimalDigits) { press in
                    guard press.characters.count == 1, let digit = Int(press.characters) else { return .ignored }
                    let candidate = enteredDigits + String(digit)
                    let number = Int(candidate) ?? digit
                    if number <= component.upperBound {
                        setValue(number, for: component)
                        enteredDigits = candidate
                    } else {
                        setValue(digit, for: component)
                        enteredDigits = String(digit)
                    }
                    if enteredDigits.count == 2 {
                        enteredDigits = ""
                        if component == .hours { selection = .minutes }
                    }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    adjust(component, by: 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    adjust(component, by: -1)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    selection = .hours
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    selection = .minutes
                    return .handled
                }
                .onKeyPress(.delete) {
                    setValue(0, for: component)
                    enteredDigits = ""
                    return .handled
                }
        }

        private func value(for component: Component) -> Int {
            component == .hours ? hours : minutes
        }

        private func setValue(_ value: Int, for component: Component) {
            if component == .hours { hours = value } else { minutes = value }
        }

        private func adjust(_ component: Component, by amount: Int) {
            let current = min(max(value(for: component), 0), component.upperBound)
            setValue(min(max(current + amount, 0), component.upperBound), for: component)
            enteredDigits = ""
        }
    }
#endif
