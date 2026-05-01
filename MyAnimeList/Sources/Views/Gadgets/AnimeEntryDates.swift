//
//  AnimeEntryDates.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/19/25.
//

import DataProvider
import SwiftUI

struct AnimeEntryDates: View {
    var entry: AnimeEntry
    var labelsHidden: Bool = false

    private var dateFormatStyle: Date.FormatStyle {
        .dateTime.year().month().day()
    }

    var body: some View {
        HStack(spacing: 18) {
            dateColumn(label: dateStartedResource, value: entry.dateStarted)

            Image(systemName: "ellipsis")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary.opacity(0.72))
                .alignmentGuide(VerticalAlignment.center) { d in
                    labelsHidden ? d[VerticalAlignment.center] : -7
                }

            dateColumn(label: dateFinishedResource, value: entry.dateFinished)
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
    private func dateColumn(label: LocalizedStringResource, value: Date?) -> some View {
        VStack(spacing: 4) {
            if !labelsHidden {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let value {
                Text(value, format: dateFormatStyle)
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
