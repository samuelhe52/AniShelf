//
//  AnimeEntryListRow.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/5.
//

import DataProvider
import Kingfisher
import SwiftUI

struct AnimeEntryListRow: View {
    var entry: AnimeEntry
    var onSelect: (() -> Void)? = nil
    var onOpenDetails: (() -> Void)? = nil

    private let metadataFont = Font.system(size: 10.5, weight: .medium)
    private let overviewFont = Font.system(size: 11, weight: .regular)
    private let posterWidth: CGFloat = 88
    private let posterHeight: CGFloat = 132
    private let rowHeight: CGFloat = 126
    private let favoriteButtonTapClearance: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            poster
            info(entry: entry)
        }
        .frame(height: rowHeight, alignment: .top)
        .padding(.vertical, 5)
        .overlay {
            rowTapSurface
        }
    }

    private var rowTapSurface: some View {
        HStack(spacing: 0) {
            rowTapTarget

            Color.clear
                .frame(width: favoriteButtonTapClearance)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rowTapTarget: some View {
        if let onOpenDetails {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { onSelect?() }
                .onTapGesture(count: 2) { onOpenDetails() }
        } else {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { onSelect?() }
        }
    }

    @ViewBuilder
    private func info(entry: AnimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
            if let overviewText {
                Text(overviewText)
                    .font(overviewFont)
                    .foregroundStyle(.secondary.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .padding(.top, 6)
                    .layoutPriority(0)
            }

            Spacer(minLength: 0)

            statusLabel
                .padding(.top, overviewText == nil ? 10 : 7)
                .layoutPriority(3)
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .topLeading)
    }

    private var poster: some View {
        KFImageView(
            url: entry.posterURL,
            targetWidth: 240,
            diskCacheExpiration: .longTerm
        )
        .scaledToFill()
        .frame(width: posterWidth, height: posterHeight)
        .clipped()
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
        .padding(.vertical, -3)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.displayName)
                .font(.headline.weight(.semibold))
                .lineLimit(1...2)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .layoutPriority(2)

            metadataBlock
                .layoutPriority(1)
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ForEach(Array(primaryMetadata.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("•")
                    }
                    Text(item)
                }
            }
            .lineLimit(1)

            if let secondaryMetadataText {
                Text(secondaryMetadataText)
                    .lineLimit(1)
            }
        }
        .font(metadataFont)
        .foregroundStyle(.secondary)
    }

    private var favoriteButton: some View {
        LibraryFavoriteToggle(entry: entry) { isFavorite in
            LibraryFavoriteSymbol(
                isFavorite: isFavorite,
                font: .footnote.weight(.semibold)
            )
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(.white.opacity(isFavorite ? 0.1 : 0.04))
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(isFavorite ? 0.18 : 0.08), lineWidth: 1)
            }
            .contentShape(.rect)
        }
    }

    private var primaryMetadata: [String] {
        [
            yearText,
            typeSummaryText
        ].compactMap(\.self)
    }

    private var yearText: String? {
        entry.onAirDate?.formatted(.dateTime.year().month().day())
    }

    private var typeSummaryText: String? {
        switch entry.type {
        case .movie:
            return String(localized: movieSummaryResource)
        case .series:
            return entry.detail?.episodeCount.map { String(localized: episodeCountResource($0)) }
                ?? String(localized: "Series")
        case .season(let seasonNumber, _):
            return entry.detail?.episodeCount.map { String(localized: episodeCountResource($0)) }
                ?? String(localized: seasonSummaryResource(seasonNumber: seasonNumber))
        }
    }

    private var secondaryMetadataText: String? {
        guard case .season(let seasonNumber, _) = entry.type else { return nil }
        return String(localized: seasonSummaryResource(seasonNumber: seasonNumber))
    }

    private var movieSummaryResource: LocalizedStringResource {
        if let runtime = entry.detail?.runtimeMinutes {
            return "\(runtime) min"
        }
        return "Movie"
    }

    private func seasonSummaryResource(seasonNumber: Int) -> LocalizedStringResource {
        if seasonNumber == 0 {
            return "Specials"
        }
        return "Season \(seasonNumber)"
    }

    private func episodeCountResource(_ count: Int) -> LocalizedStringResource {
        "\(count) episodes"
    }

    private var overviewText: String? {
        guard
            let overview = entry.displayOverview?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !overview.isEmpty
        else {
            return nil
        }

        return overview
    }

    private var statusLabel: some View {
        HStack(spacing: 10) {
            statusBadge
            Spacer(minLength: 8)
            favoriteButton
        }
    }

    private var statusBadge: some View {
        LibraryWatchStatusBadge(status: entry.watchStatus)
    }
}
