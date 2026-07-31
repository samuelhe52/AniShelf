//
//  PosterSelectionView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/12.
//

import DataProvider
import SwiftUI

typealias Poster = ImageURLWithMetadata

struct PosterSelectionView: View {
    let tmdbID: Int
    let type: AnimeType
    let originalPosterLanguageCode: String?
    let fetcher: InfoFetcher
    let showsDismissButton: Bool
    let onPosterSelected: (URL) -> Void

    init(
        tmdbID: Int,
        type: AnimeType,
        originalPosterLanguageCode: String? = nil,
        infoFetcher: InfoFetcher = .init(),
        showsDismissButton: Bool = true,
        onPosterSelected: @escaping (URL) -> Void
    ) {
        self.tmdbID = tmdbID
        self.type = type
        self.originalPosterLanguageCode = originalPosterLanguageCode
        self.fetcher = infoFetcher
        self.showsDismissButton = showsDismissButton
        self.onPosterSelected = onPosterSelected
    }

    @State private var previewSelection: PosterPreviewSelection?
    @State private var pendingPosterSelectionURL: URL?
    @Environment(\.dismiss) private var dismiss
    @Namespace private var preview

    var body: some View {
        ScrollView {
            PosterBrowserView(
                tmdbID: tmdbID,
                type: type,
                originalPosterLanguageCode: originalPosterLanguageCode,
                fetcher: fetcher,
                previewNamespace: preview,
                selectedPosterPath: nil,
                onPosterTap: { poster, posters in
                    previewSelection = PosterPreviewSelection(
                        poster: poster,
                        posters: posters
                    )
                }
            )
            .padding(.horizontal, 16)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
        .preferredNavigationBarScrollEdgeEffect()
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .presentationDragIndicator(.visible)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .sheet(item: $previewSelection, onDismiss: finishPendingPosterSelection) { selection in
            PosterSlides(
                posters: selection.posters,
                currentPoster: selection.poster,
                onPosterSelected: { url in
                    pendingPosterSelectionURL = url
                    previewSelection = nil
                }
            )
            .presentationSizing(.page)
            .presentationCompactAdaptation(.fullScreenCover)
            .navigationTransition(
                .zoom(
                    sourceID: selection.poster.metadata.filePath,
                    in: preview))
        }
        .presentationSizing(.page)
    }

    private func finishPendingPosterSelection() {
        guard let pendingPosterSelectionURL else { return }
        self.pendingPosterSelectionURL = nil
        onPosterSelected(pendingPosterSelectionURL)
        dismiss()
    }
}

fileprivate struct PosterPreviewSelection: Identifiable {
    let poster: Poster
    let posters: [Poster]

    var id: Poster.ID { poster.id }
}

extension Array where Element == Poster {
    func filteredAndSorted(
        originalLanguageCode: String? = nil,
        metadataLanguageCode: String? = nil
    ) -> [Poster] {
        let fallbackPosters = sorted { lhs, rhs in
            lhs.metadata.width > rhs.metadata.width
        }
        let rankedPosters: [(poster: Poster, priority: Int)] = compactMap { poster in
            guard
                let priority = TMDbImageSelection.posterLanguagePriority(
                    for: poster.metadata.languageCode,
                    originalLanguageCode: originalLanguageCode,
                    metadataLanguageCode: metadataLanguageCode
                )
            else {
                return nil
            }
            return (poster: poster, priority: priority)
        }
        guard !rankedPosters.isEmpty else { return fallbackPosters }
        return rankedPosters.sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 < rhs.1
            }
            return lhs.0.metadata.width > rhs.0.metadata.width
        }
        .map(\.0)
    }
}

#Preview {
    NavigationStack {
        PosterSelectionView(
            tmdbID: 307972,
            type: .season(seasonNumber: 1, parentSeriesID: 209867),
            onPosterSelected: { _ in }
        )
    }
}
