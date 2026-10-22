//
//  AnimeEntryDates.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/19/25.
//

import DataProvider
import SwiftUI

struct AnimeEntryDates: View {
    var snapshot: LibraryEntrySnapshot
    var labelsHidden: Bool = false

    init(entry: AnimeEntry, labelsHidden: Bool = false) {
        self.snapshot = LibraryEntrySnapshot(entry: entry)
        self.labelsHidden = labelsHidden
    }

    init(snapshot: LibraryEntrySnapshot, labelsHidden: Bool = false) {
        self.snapshot = snapshot
        self.labelsHidden = labelsHidden
    }

    var body: some View {
        // Narrow shelf cards, such as on iPhone Duo's short inner landscape display, would wrap the
        // long dates in Japanese and Chinese; numeric dates keep each date on one line there.
        ViewThatFits(in: .horizontal) {
            pill(dateFormat: .dateTime.year().month().day())
            pill(dateFormat: .dateTime.year().month(.defaultDigits).day())
        }
    }

    private func pill(dateFormat: Date.FormatStyle) -> some View {
        HStack(spacing: 18) {
            dateColumn(label: dateStartedResource, value: snapshot.dateStarted, format: dateFormat)

            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary.opacity(0.72))
                .alignmentGuide(VerticalAlignment.center) { d in
                    labelsHidden ? d[VerticalAlignment.center] : -7
                }

            dateColumn(label: dateFinishedResource, value: snapshot.dateFinished, format: dateFormat)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func dateColumn(
        label: LocalizedStringResource,
        value: Date?,
        format: Date.FormatStyle
    ) -> some View {
        VStack(spacing: 4) {
            if !labelsHidden {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let value {
                Text(value, format: format)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
            } else {
                Text(notAvailableResource)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateStartedResource: LocalizedStringResource {
        "Date Started"
    }

    private var dateFinishedResource: LocalizedStringResource {
        "Date Finished"
    }

    private var notAvailableResource: LocalizedStringResource {
        "N/A"
    }
}
