//
//  EntryDetailMacTrackingRows.swift
//  MyAnimeList
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// The Mac tracking card: label/value rows with dividers, matching the stat card above
    /// it. iOS uses the disclosure editor in `EntryDetailTrackingComponents.swift`.
    struct MacEntryTrackingEditor: View {
        @Bindable var entry: AnimeEntry
        /// The notes when the inspector opened; a rewrite can be reverted to them.
        let originalNotes: String?
        let scoringEnabled: Bool
        let episodeProgressTrackingEnabled: Bool
        let onWatchStatusSelected: (AnimeEntry.WatchStatus) -> Void
        let onEpisodeProgressCompletionSuggested: (AnimeEntryEpisodeProgressCompletionPrompt) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if scoringEnabled {
                    EntryTrackingRow(EntryDetailL10n.score) {
                        EntryScoreCard(score: entry.entryScore, onSetScore: { entry.updateEntryScore($0) }, isInline: true)
                    }
                    Divider()
                }

                EntryTrackingRow(EntryDetailL10n.watchStatus) {
                    AnimeEntryWatchedStatusPicker(
                        selection: entry.activeWatchStatusBinding(onSelect: onWatchStatusSelected),
                        isDisabled: entry.isDateTrackingLocked,
                        isRewatching: entry.isRewatching
                    )
                    .pickerStyle(.segmented)
                }
                // Usually set by the rewatch prompt; the menu is for corrections. The
                // middle segment reads "Rewatching" while the flag is on.
                .contextMenu {
                    if entry.watchStatus == .watching {
                        Toggle(isOn: rewatchingBinding) {
                            Text(EntryDetailL10n.rewatching)
                        }
                    }
                }

                if entry.showsRewatchControls {
                    Divider()
                    EntryRewatchCountRow(entry: entry)
                }

                EntryDateRows(entry: entry)

                if episodeProgressTrackingEnabled, entry.watchStatus == .watching {
                    Divider()
                    EntryEpisodeProgressControl(
                        entry: entry,
                        onCompletionPromptRequested: onEpisodeProgressCompletionSuggested
                    )
                    .id(entry.libraryIdentity.rawID)
                    .padding(.vertical, 7)
                }

                Divider()
                notesSection
                    .padding(.vertical, 10)
            }
            .animation(.default, value: entry.watchStatus)
            .animation(.default, value: entry.isDateTrackingEnabled)
        }

        private var rewatchingBinding: Binding<Bool> {
            Binding(
                get: { entry.isRewatching },
                set: { isRewatching in
                    withAnimation(.default) {
                        _ = entry.updateRewatching(isRewatching)
                    }
                }
            )
        }

        private var notesSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(EntryDetailL10n.notes)
                    Spacer(minLength: 8)
                    // Edits save as they happen. A rewrite, unlike an append, may lose text,
                    // so it can be reverted here; iOS offers Discard from its Done menu.
                    if let originalNotes, !entry.notes.hasPrefix(originalNotes) {
                        Button(EntryDetailL10n.revertNotes) {
                            entry.updateNotes(originalNotes)
                        }
                        .controlSize(.small)
                    }
                }
                ScrollIsolatedPlaceholderTextEditor(
                    text: Binding(
                        get: { entry.notes },
                        set: { entry.updateNotes($0) }
                    ),
                    placeholder: EntryDetailL10n.writeSomeThoughts
                )
                // A quiet inset surface keeps the editor legible without a bright
                // white panel competing with the surrounding inspector content.
                .font(.body)
                .lineSpacing(3)
                .frame(height: 200)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
            }
        }
    }

    /// A label/control row for the Mac tracking card: the label on the leading side and
    /// the control on the trailing side.
    ///
    /// Labels use the primary color, as in System
    /// Settings, so the controls do not read as disabled. An
    /// optional accessory, such as the rewatch badge, follows the label.
    struct EntryTrackingRow<Accessory: View, Content: View>: View {
        let title: LocalizedStringResource
        @ViewBuilder let accessory: Accessory
        @ViewBuilder let content: Content

        init(
            _ title: LocalizedStringResource,
            @ViewBuilder accessory: () -> Accessory = { EmptyView() },
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.accessory = accessory()
            self.content = content()
        }

        var body: some View {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .lineLimit(1)
                accessory
                Spacer(minLength: 12)
                content
            }
            .padding(.vertical, 7)
        }
    }

    /// Completed rewatches as a number field and stepper, the same control as episode
    /// progress.
    ///
    /// The Rewatching flag lives in the status row's context menu instead.
    struct EntryRewatchCountRow: View {
        @Bindable var entry: AnimeEntry

        private static let range = 0...999

        private var count: Binding<Int> {
            Binding(
                get: { entry.rewatchCount },
                set: { newValue in
                    withAnimation(.default) {
                        _ = entry.updateRewatchCount(min(max(newValue, Self.range.lowerBound), Self.range.upperBound))
                    }
                }
            )
        }

        var body: some View {
            EntryTrackingRow(EntryDetailL10n.timesRewatched) {
                HStack(spacing: 6) {
                    TextField(value: count, format: .number) {
                        Text(EntryDetailL10n.timesRewatched)
                    }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 52)

                    Stepper(value: count, in: Self.range) {
                        Text(EntryDetailL10n.timesRewatched)
                    }
                    .labelsHidden()
                }
            }
        }
    }

    /// Start and finish rows.
    ///
    /// An unset date is a placeholder rather than a dimmed copy of
    /// today, and a date the status does not expect stays hidden until it has a value.
    ///
    /// Hiding dates is rare, so it lives in the rows' context menu rather than its own
    /// row; while dates are hidden, one Dates row offers to track them again.
    struct EntryDateRows: View {
        @Bindable var entry: AnimeEntry

        private var isLocked: Bool {
            entry.watchStatus == .dropped
        }

        var body: some View {
            if entry.isDateTrackingEnabled {
                trackedRows
            } else {
                Divider()
                EntryTrackingRow(EntryDetailL10n.dates) {
                    Button(EntryDetailL10n.trackDates) {
                        setDateTracking(true)
                    }
                    .buttonStyle(.link)
                }
            }
        }

        @ViewBuilder
        private var trackedRows: some View {
            let slots = entry.visibleDateSlots
            if slots.start {
                Divider()
                EntryTrackingRow(EntryDetailL10n.dateStarted) {
                    EntryDateToken(
                        date: $entry.dateStarted.onSet { entry.markTrackingModified() },
                        range: Date.distantPast...(entry.dateFinished ?? .now),
                        isLocked: isLocked
                    )
                }
                .contextMenu { dateMenu(clearing: $entry.dateStarted) }
            }
            if slots.finish {
                Divider()
                EntryTrackingRow(EntryDetailL10n.dateFinished) {
                    HStack(spacing: 8) {
                        if let duration {
                            Text(duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        EntryDateToken(
                            date: $entry.dateFinished.onSet { entry.markTrackingModified() },
                            range: (entry.dateStarted ?? .distantPast)...Date.distantFuture,
                            isLocked: isLocked
                        )
                    }
                }
                .contextMenu { dateMenu(clearing: $entry.dateFinished) }
            }
            if isLocked {
                Label(EntryDetailL10n.droppedDatesLocked, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 7)
            }
        }

        @ViewBuilder
        private func dateMenu(clearing date: Binding<Date?>) -> some View {
            if date.wrappedValue != nil, !isLocked {
                Button(EntryDetailL10n.clear) {
                    date.wrappedValue = nil
                    entry.markTrackingModified()
                }
                Divider()
            }
            Button(EntryDetailL10n.hideDates) {
                setDateTracking(false)
            }
        }

        private func setDateTracking(_ isEnabled: Bool) {
            withAnimation(.default) {
                _ = entry.updateDateTrackingEnabled(isEnabled)
            }
        }

        /// Whole days between the two dates, shown only once both exist.
        private var duration: String? {
            guard let start = entry.dateStarted, let finish = entry.dateFinished else { return nil }
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: start)
            let finishDay = calendar.startOfDay(for: finish)
            guard finishDay > startDay else { return nil }
            return (startDay..<finishDay).formatted(.components(style: .wide, fields: [.day]))
        }
    }

    /// One date as a quiet capsule.
    ///
    /// A click opens a calendar with Today and Clear.
    fileprivate struct EntryDateToken: View {
        @Binding var date: Date?
        let range: ClosedRange<Date>
        let isLocked: Bool

        @State private var isEditing = false
        @State private var isHovering = false

        var body: some View {
            Button {
                isEditing = true
            } label: {
                Group {
                    if let date {
                        Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                            .monospacedDigit()
                    } else {
                        Label {
                            Text(EntryDetailL10n.notSet)
                        } icon: {
                            Image(systemName: "plus")
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovering && !isLocked ? 0.1 : 0.05))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .disabled(isLocked)
            .opacity(isLocked ? 0.5 : 1)
            .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                EntryDateCalendar(date: $date, range: range) {
                    isEditing = false
                }
            }
        }
    }

    fileprivate struct EntryDateCalendar: View {
        @Binding var date: Date?
        let range: ClosedRange<Date>
        let dismiss: () -> Void

        private var selection: Binding<Date> {
            Binding(
                get: { date ?? min(max(.now, range.lowerBound), range.upperBound) },
                set: { date = $0 }
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                PlainCalendarPicker(selection: selection, range: range)

                HStack {
                    Button(EntryDetailL10n.today) {
                        date = .now
                        dismiss()
                    }
                    .disabled(!range.contains(.now))
                    Spacer(minLength: 12)
                    Button(EntryDetailL10n.clear) {
                        date = nil
                        dismiss()
                    }
                    .disabled(date == nil)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    /// The AppKit month calendar without its bezel.
    ///
    /// SwiftUI's graphical `DatePicker` keeps
    /// the bezel, which drew a second panel inside the popover's glass.
    fileprivate struct PlainCalendarPicker: NSViewRepresentable {
        @Binding var selection: Date
        let range: ClosedRange<Date>

        func makeNSView(context: Context) -> NSDatePicker {
            let picker = NSDatePicker()
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = .yearMonthDay
            picker.isBezeled = false
            picker.isBordered = false
            picker.drawsBackground = false
            // The calendar takes focus when the popover opens; its ring framed the whole
            // month in accent blue.
            picker.focusRingType = .none
            picker.target = context.coordinator
            picker.action = #selector(Coordinator.dateChanged(_:))
            return picker
        }

        func updateNSView(_ picker: NSDatePicker, context: Context) {
            context.coordinator.selection = $selection
            picker.locale = context.environment.locale
            picker.calendar = context.environment.calendar
            picker.timeZone = context.environment.timeZone
            picker.minDate = range.lowerBound
            picker.maxDate = range.upperBound
            if picker.dateValue != selection {
                picker.dateValue = selection
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(selection: $selection)
        }

        @MainActor final class Coordinator: NSObject {
            var selection: Binding<Date>

            init(selection: Binding<Date>) {
                self.selection = selection
            }

            @objc func dateChanged(_ sender: NSDatePicker) {
                selection.wrappedValue = sender.dateValue
            }
        }
    }

    extension AnimeEntry {
        /// Which date rows show: a date shows when it has a value or when the status
        /// expects one.
        fileprivate var visibleDateSlots: (start: Bool, finish: Bool) {
            switch watchStatus {
            case .planToWatch:
                (true, dateFinished != nil)
            case .watching, .watched:
                (true, true)
            case .dropped:
                (dateStarted != nil || dateFinished == nil, dateFinished != nil)
            }
        }
    }
#endif
