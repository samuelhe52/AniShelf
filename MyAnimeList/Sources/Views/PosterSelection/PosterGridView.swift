//
//  PosterGridView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/12/17.
//

import DataProvider
import Foundation
import Kingfisher
import SwiftUI

struct PosterGridView: View {
    let posters: [Poster]
    let previewNamespace: Namespace.ID
    let selectedPosterPath: String?
    let onPosterTap: (Poster) -> Void

    private struct Constants {
        static let gridItemMinSize: CGFloat = 100
        static let gridItemMaxSize: CGFloat = 200
        static let gridItemVerticalSpacing: CGFloat = 12
        static let gridItemHorizontalSpacing: CGFloat = 12
        static let posterCornerRadius: CGFloat = 10
        static let selectionRingGap: CGFloat = 3.5
        static let selectionRingWidth: CGFloat = 3
        static let badgeOffset: CGFloat = 6
        static let cacheExpiration: StorageExpiration = .transient
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: Constants.gridItemMinSize,
                        maximum: Constants.gridItemMaxSize),
                    spacing: Constants.gridItemHorizontalSpacing)
            ],
            spacing: Constants.gridItemVerticalSpacing
        ) {
            ForEach(posters, id: \.url) { poster in
                Button {
                    onPosterTap(poster)
                } label: {
                    posterWithInfo(poster: poster)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected(poster) ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func posterWithInfo(poster: Poster) -> some View {
        let width = poster.metadata.width
        let height = poster.metadata.height
        let aspectRatio = CGFloat(width) / CGFloat(max(height, 1))
        let selected = isSelected(poster)

        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                KFImageView(
                    url: poster.url,
                    maxPixelDimension: 450,
                    diskCacheExpiration: Constants.cacheExpiration
                )
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay {
                posterShape.stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(posterShape)
            // The ring and badge sit outside the clip, so the selection marks leave the art
            // uncovered. The inset ring stays concentric with the poster's corners.
            .overlay {
                ZStack {
                    if selected {
                        posterShape
                            .inset(by: -Constants.selectionRingGap)
                            .stroke(Color.accentColor, lineWidth: Constants.selectionRingWidth)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 1.04)),
                                    removal: .opacity
                                )
                            )
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                ZStack {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(.background).padding(-1.5))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .offset(x: Constants.badgeOffset, y: -Constants.badgeOffset)
            }
            .matchedTransitionSource(id: poster.metadata.filePath, in: previewNamespace)
            .animation(.snappy(duration: 0.2), value: selected)
            .help(Text("\(width) x \(height)"))
            .accessibilityLabel(Text("\(width) x \(height)"))
    }

    private var posterShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Constants.posterCornerRadius, style: .continuous)
    }

    private func isSelected(_ poster: Poster) -> Bool {
        TMDbImagePath.storagePath(from: poster.metadata.filePath) == selectedPosterPath
    }
}
