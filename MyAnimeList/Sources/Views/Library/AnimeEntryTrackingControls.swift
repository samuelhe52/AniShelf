//
//  AnimeEntryTrackingControls.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

import DataProvider
import SwiftUI

struct AnimeEntryWatchedStatusPicker: View {
    @Binding var selection: AnimeEntry.WatchStatus
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(selection: $selection) {
                Text(EntryDetailL10n.planned).tag(AnimeEntry.WatchStatus.planToWatch)
                Text(EntryDetailL10n.watching).tag(AnimeEntry.WatchStatus.watching)
                Text(EntryDetailL10n.watched).tag(AnimeEntry.WatchStatus.watched)
            } label: {
            }
            .disabled(isDisabled)
            .lineLimit(1)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}

struct AnimeEntryDatePickers: View {
    @Binding var dateStarted: Date?
    @Binding var dateFinished: Date?
    let isLocked: Bool
    var labelsHidden: Bool = false

    private var dateStartedPickerBinding: Binding<Date> {
        Binding(
            get: {
                dateStarted ?? .now
            },
            set: {
                dateStarted = $0
            }
        )
    }

    private var dateFinishedPickerBinding: Binding<Date> {
        Binding(
            get: {
                dateFinished ?? .now
            },
            set: {
                dateFinished = $0
            }
        )
    }

    private var dateStartedRange: ClosedRange<Date> {
        Date.distantPast...(dateFinished ?? .now)
    }

    private var dateFinishedRange: ClosedRange<Date> {
        (dateStarted ?? .now)...Date.distantFuture
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                DatePicker(
                    selection: dateStartedPickerBinding,
                    in: dateStartedRange,
                    displayedComponents: [.date]
                ) {
                    Text(EntryDetailL10n.dateStarted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .opacity(dateStarted == nil ? 0.5 : 1)

                Image(systemName: "ellipsis")
                    .alignmentGuide(VerticalAlignment.center) { d in
                        labelsHidden ? d[VerticalAlignment.center] : -6
                    }
                    .foregroundStyle(.secondary)

                DatePicker(
                    selection: dateFinishedPickerBinding,
                    in: dateFinishedRange,
                    displayedComponents: [.date]
                ) {
                    Text(EntryDetailL10n.dateFinished)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .opacity(dateFinished == nil ? 0.5 : 1)

                Spacer()
            }
            .datePickerStyle(.vertical(labelsHidden: labelsHidden))
            .disabled(isLocked)
            .animation(.default, value: isLocked)

            if isLocked {
                Label(EntryDetailL10n.droppedDatesLocked, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
