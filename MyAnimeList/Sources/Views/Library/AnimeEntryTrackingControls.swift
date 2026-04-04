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

    private var watchedStatusBinding: Binding<WatchedStatus> {
        Binding(
            get: {
                entry.watchStatus
            },
            set: {
                entry.watchStatus = $0
                switch $0 {
                case .watched:
                    entry.dateFinished = .now
                case .watching:
                    entry.dateStarted = .now
                    entry.dateFinished = nil
                default: break
                }
            })
    }

    var body: some View {
        Picker(selection: watchedStatusBinding) {
            Text("Plan to Watch").tag(WatchedStatus.planToWatch)
            Text("Watching").tag(WatchedStatus.watching)
            Text("Watched").tag(WatchedStatus.watched)
        } label: {
        }
    }
}

struct AnimeEntryDatePickers: View {
    var entry: AnimeEntry
    var labelsHidden: Bool = false

    private var dateStartedBinding: Binding<Date> {
        Binding(
            get: {
                entry.dateStarted ?? .now
            },
            set: {
                entry.dateStarted = $0
            })
    }

    private var dateFinishedBinding: Binding<Date> {
        Binding(
            get: {
                entry.dateFinished ?? .now
            },
            set: {
                entry.dateFinished = $0
                if $0 < .now {
                    entry.watchStatus = .watched
                }
            })
    }

    var body: some View {
        HStack {
            Spacer()
            DatePicker(
                selection: dateStartedBinding,
                in: Date.distantPast...(entry.dateFinished ?? .now),
                displayedComponents: [.date]
            ) {
                Text("Date Started")
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
                Text("Date Finished")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .datePickerStyle(.vertical(labelsHidden: labelsHidden))
    }
}
