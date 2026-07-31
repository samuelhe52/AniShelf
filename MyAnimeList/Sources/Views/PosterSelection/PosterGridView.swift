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
        static let posterCornerRadius: CGFloat = 8
        static let selectedStrokeWidth: CGFloat = 4
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

        VStack {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    KFImageView(
                        url: poster.url,
                        targetWidth: 300,
                        diskCacheExpiration: Constants.cacheExpiration
                    )
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Constants.posterCornerRadius, style: .continuous)
                        .strokeBorder(
                            selected ? Color.accentColor : .white.opacity(0.18),
                            lineWidth: selected ? Constants.selectedStrokeWidth : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(7)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Constants.posterCornerRadius))
            Text("\(width) x \(height)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .matchedTransitionSource(id: poster.metadata.filePath, in: previewNamespace)
        .animation(.snappy(duration: 0.2), value: selected)
    }

    private func isSelected(_ poster: Poster) -> Bool {
        TMDbImagePath.storagePath(from: poster.metadata.filePath) == selectedPosterPath
    }
}
