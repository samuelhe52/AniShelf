//
//  LibraryGridItem.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

import DataProvider
import SwiftUI

/// A library grid card. iOS dims the cards outside a multi-selection (`isSelected`); the Mac
/// rings the selected cards instead (`showsSelectionRing`).
struct LibraryGridItem: View {
    var snapshot: LibraryEntrySnapshot
    var isSelected: Bool = true
    var showsSelectionRing = false
    private let posterShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            poster
            titleLabel
        }
        .opacity(selectionOpacity)
        .scaleEffect(selectionScale)
        .contentShape(.rect)
        .animation(.bouncy(duration: 0.18, extraBounce: 0.1), value: isSelected)
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { posterImage }
            .overlay(alignment: .topLeading) { statusIndicator }
            .overlay(alignment: .topTrailing) { favoriteIndicator }
            .overlay(alignment: .bottom) { progressBar }
            .overlay {
                posterShape
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(posterShape)
            .overlay {
                ZStack {
                    if showsSelectionRing {
                        posterShape
                            .inset(by: -3.5)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 1.04)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .animation(.snappy(duration: 0.12), value: showsSelectionRing)
            }
            .shadow(color: .black.opacity(0.22), radius: 11, y: 6)
    }

    private var posterImage: some View {
        KFImageView(
            url: snapshot.displayPosterURL(for: .grid),
            targetSize: TMDbPosterDisplayType.grid.targetSize,
            diskCacheExpiration: .longTerm
        )
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleLabel: some View {
        Text(snapshot.title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.88))
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .lineSpacing(-1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
    }

    private var statusIndicator: some View {
        LibraryWatchStatusIndicator(
            status: snapshot.watchStatus,
            diameter: 10,
            strokeColor: .white.opacity(0.88),
            strokeWidth: 1.8,
            shadowColor: .black.opacity(0.22),
            shadowRadius: 4,
            shadowYOffset: 2
        )
        .padding(8)
    }

    private var progressBar: some View {
        LibraryPosterEpisodeProgressBar(
            fractionCompleted: snapshot.episodeProgressFraction,
            style: .compact
        )
    }

    @ViewBuilder
    private var favoriteIndicator: some View {
        if snapshot.isFavorite {
            LibraryFavoriteSymbol(
                isFavorite: true,
                font: .system(size: 11, weight: .bold),
                filledColor: .pink.opacity(0.92),
                emptyColor: .pink.opacity(0.92),
                shadowColor: .black.opacity(0.55),
                shadowRadius: 5,
                shadowYOffset: 2
            )
            .padding(8)
        }
    }

    private var selectionOpacity: Double {
        isSelected ? 1 : 0.48
    }

    private var selectionScale: CGFloat {
        isSelected ? 1 : 0.95
    }
}
