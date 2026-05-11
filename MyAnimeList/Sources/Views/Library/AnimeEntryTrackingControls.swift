//
//  AnimeEntryTrackingControls.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

import DataProvider
import SwiftUI

typealias WatchedStatus = AnimeEntry.WatchStatus

struct AnimeEntryWatchedStatusPicker: View {
    var entry: AnimeEntry

    init(for entry: AnimeEntry) {
        self.entry = entry
    }

    private var activeStatusBinding: Binding<WatchedStatus> {
        Binding(
            get: {
                switch entry.watchStatus {
                case .planToWatch, .watching, .watched:
                    return entry.watchStatus
                case .dropped:
                    return .watching
                }
            },
            set: {
                entry.setWatchStatus($0)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(selection: activeStatusBinding) {
                Text("Planned").tag(WatchedStatus.planToWatch)
                Text("Watching").tag(WatchedStatus.watching)
                Text("Watched").tag(WatchedStatus.watched)
            } label: {
            }
            .disabled(entry.watchStatus == .dropped)
            .lineLimit(1)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}

struct AnimeEntryDatePickers: View {
    var entry: AnimeEntry
    var labelsHidden: Bool = false

    var isLocked: Bool {
        entry.watchStatus == .dropped
    }

    private var dateStartedBinding: Binding<Date> {
        Binding(
            get: {
                entry.dateStarted ?? .now
            },
            set: {
                guard !isLocked else { return }
                entry.dateStarted = $0
                entry.normalizeTrackingDates()
            })
    }

    private var dateFinishedBinding: Binding<Date> {
        Binding(
            get: {
                entry.dateFinished ?? .now
            },
            set: {
                guard !isLocked else { return }
                entry.dateFinished = $0
                entry.setWatchStatus(.watched)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                DatePicker(
                    selection: dateStartedBinding,
                    in: Date.distantPast...(entry.dateFinished ?? .now),
                    displayedComponents: [.date]
                ) {
                    Text(EntryDetailL10n.dateStarted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "ellipsis")
                    .alignmentGuide(VerticalAlignment.center) { d in
                        labelsHidden ? d[VerticalAlignment.center] : -6
                    }
                    .foregroundStyle(.secondary)
                DatePicker(
                    selection: dateFinishedBinding,
                    in: (entry.dateStarted ?? .now)...Date.distantFuture,
                    displayedComponents: [.date]
                ) {
                    Text(EntryDetailL10n.dateFinished)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
