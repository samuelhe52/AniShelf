//
//  PosterGridView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/12/17.
//

import Foundation
import Kingfisher
import SwiftUI

struct PosterGridView: View {
    let posters: [Poster]
    let previewNamespace: Namespace.ID
    let onPosterTap: (Poster) -> Void

    private struct Constants {
        static let gridItemMinSize: CGFloat = 100
        static let gridItemMaxSize: CGFloat = 200
        static let gridItemVerticalSpacing: CGFloat = 12
        static let gridItemHorizontalSpacing: CGFloat = 12
        static let posterCornerRadius: CGFloat = 5
        static let cacheExpiration: StorageExpiration = .transient
    }

    var body: some View {
        ScrollView {
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
                    posterWithInfo(poster: poster)
                        .transition(.opacity)
                        .onTapGesture {
                            onPosterTap(poster)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func posterWithInfo(poster: Poster) -> some View {
        let width = poster.metadata.width
        let height = poster.metadata.height
        VStack {
            KFImageView(
                url: poster.url,
                targetWidth: 300,
                diskCacheExpiration: Constants.cacheExpiration
            )
            .overlay {
                RoundedRectangle(cornerRadius: Constants.posterCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Constants.posterCornerRadius))
            .aspectRatio(contentMode: .fit)
            Text("\(width) x \(height)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .matchedTransitionSource(id: poster.metadata.filePath, in: previewNamespace)
    }
}
