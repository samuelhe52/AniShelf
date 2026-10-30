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
    @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false
    @Environment(\.libraryEntryDetailActivation) private var detailActivation

    var entry: AnimeEntry
    var snapshot: LibraryEntrySnapshot
    var tapGesturesEnabled: Bool = true
    var favoriteButtonEnabled: Bool = true
    var onTap: (() -> Void)? = nil
    var onOpenDetails: (() -> Void)? = nil
    var onToggleFavorite: (AnimeEntry) -> Void = { _ in }

    private let metadataFont = Font.system(size: 10.5, weight: .medium)
    private let overviewFont = Font.system(size: 11, weight: .regular)
    private let posterWidth: CGFloat = 88
    private let posterHeight: CGFloat = 132
    private let rowHeight: CGFloat = 126
    private let favoriteButtonTapClearance: CGFloat = 44

    init(
        entry: AnimeEntry,
        snapshot: LibraryEntrySnapshot? = nil,
        tapGesturesEnabled: Bool = true,
        favoriteButtonEnabled: Bool = true,
        onTap: (() -> Void)? = nil,
        onOpenDetails: (() -> Void)? = nil,
        onToggleFavorite: @escaping (AnimeEntry) -> Void = { _ in }
    ) {
        self.entry = entry
        self.snapshot = snapshot ?? LibraryEntrySnapshot(entry: entry)
        self.tapGesturesEnabled = tapGesturesEnabled
        self.favoriteButtonEnabled = favoriteButtonEnabled
        self.onTap = onTap
        self.onOpenDetails = onOpenDetails
        self.onToggleFavorite = onToggleFavorite
    }

    var body: some View {
        #if os(macOS)
            compactRow
                .overlay {
                    // Mac lists select natively; an inert overlay would still take the click
                    // away from the table and leave keyboard focus elsewhere.
                    if tapGesturesEnabled {
                        rowTapSurface
                    }
                }
        #else
            HStack(alignment: .top, spacing: 11) {
                poster
                info
            }
            .frame(height: rowHeight, alignment: .top)
            .padding(.vertical, 5)
            .overlay {
                rowTapSurface
            }
        #endif
    }

    #if os(macOS)
        /// A dense desktop row: a small poster, title and metadata on two lines, and the
        /// badges trailing.
        ///
        /// The synopsis stays in the inspector.
        private var compactRow: some View {
            HStack(spacing: 10) {
                KFImageView(
                    image: snapshot.displayPosterImage(.posterThumbnail),
                    diskCacheExpiration: .longTerm
                )
                .scaledToFill()
                .frame(width: 40, height: 60)
                .clipShape(.rect(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.separator, lineWidth: 0.5)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(compactMetadataText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: 6) {
                    statusBadge
                    LibraryEpisodeProgressBadge(
                        label: snapshot.episodeProgressLabel,
                        fractionCompleted: snapshot.episodeProgressFraction
                    )
                    if !showsEpisodeProgress {
                        LibraryRewatchCountBadge(count: snapshot.rewatchCount, status: snapshot.watchStatus)
                    }
                    LibraryScoreBadge(score: snapshot.score)
                }
                .fixedSize()

                compactFavoriteButton
            }
            .padding(.vertical, 2)
        }

        private var compactMetadataText: String {
            (primaryMetadata + [secondaryMetadataText].compactMap { $0 }).joined(separator: " · ")
        }

        private var compactFavoriteButton: some View {
            LibraryFavoriteToggle(
                entry: entry,
                displayedIsFavorite: snapshot.isFavorite,
                onToggleFavorite: onToggleFavorite
            ) { isFavorite in
                LibraryFavoriteSymbol(
                    isFavorite: isFavorite,
                    font: .body,
                    shadowColor: .clear,
                    shadowRadius: 0
                )
                .frame(width: 24, height: 24)
                .contentShape(.rect)
            }
            .disabled(!favoriteButtonEnabled)
            .macHelp(Text(snapshot.isFavorite ? "Remove from Favorites" : "Add to Favorites"))
        }
    #endif

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
            if detailActivation.usesSingleTap(userPreference: openDetailWithSingleTap) {
                Color.clear
                    .contentShape(.rect)
                    .gesture(
                        TapGesture().onEnded { onOpenDetails() },
                        including: tapGestureMask
                    )
            } else {
                // Keep focus immediate without allowing one tap to open double-tap detail.
                Color.clear
                    .contentShape(.rect)
                    .simultaneousGesture(
                        TapGesture().onEnded { onTap?() },
                        including: tapGestureMask
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { onOpenDetails() },
                        including: tapGestureMask
                    )
            }
        } else {
            Color.clear
                .contentShape(.rect)
                .gesture(
                    TapGesture().onEnded { onTap?() },
                    including: tapGestureMask
                )
        }
    }

    /// Disabling via a mask (instead of swapping tap wrappers) keeps the row's
    /// recognizer tree stable and lets the List's edit-mode selection receive
    /// whole-row taps during multi-selection.
    private var tapGestureMask: GestureMask {
        tapGesturesEnabled ? .all : .subviews
    }

    private var info: some View {
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
            image: snapshot.displayPosterImage(.posterThumbnail),
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
            Text(snapshot.title)
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
        LibraryFavoriteToggle(
            entry: entry,
            displayedIsFavorite: snapshot.isFavorite,
            onToggleFavorite: onToggleFavorite
        ) { isFavorite in
            LibraryFavoriteSymbol(
                isFavorite: isFavorite,
                font: .footnote.weight(.semibold),
                shadowColor: isFavorite ? .pink.opacity(0.3) : .clear,
                shadowRadius: isFavorite ? 5 : 0
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
        .disabled(!favoriteButtonEnabled)
    }

    private var primaryMetadata: [String] {
        snapshot.primaryMetadata
    }

    private var secondaryMetadataText: String? {
        snapshot.secondaryMetadata
    }

    private var overviewText: String? {
        snapshot.overview
    }

    private var statusLabel: some View {
        HStack(spacing: showsEpisodeProgress ? 6 : 10) {
            statusBadge
            LibraryEpisodeProgressBadge(
                label: snapshot.episodeProgressLabel,
                fractionCompleted: snapshot.episodeProgressFraction
            )
            if !showsEpisodeProgress {
                LibraryRewatchCountBadge(count: snapshot.rewatchCount, status: snapshot.watchStatus)
            }
            LibraryScoreBadge(score: snapshot.score)
            Spacer(minLength: 8)
            favoriteButton
        }
    }

    private var statusBadge: some View {
        LibraryWatchStatusBadge(
            status: snapshot.watchStatus,
            isRewatching: snapshot.isRewatching,
            rewatchCount: showsEpisodeProgress ? snapshot.rewatchCount : 0
        )
        .fixedSize(horizontal: showsEpisodeProgress, vertical: false)
    }

    private var showsEpisodeProgress: Bool {
        episodeProgressTrackingEnabled && !(snapshot.episodeProgressLabel ?? "").isEmpty
    }
}
