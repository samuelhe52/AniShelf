//
//  PosterSelectionView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/12.
//

import DataProvider
import Kingfisher
import SwiftUI
import TMDb
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "PosterSelectionView")

typealias Poster = ImageURLWithMetadata

struct PosterSelectionView: View {
    let tmdbID: Int
    let type: AnimeType
    let originalPosterLanguageCode: String?
    let fetcher: InfoFetcher
    let onPosterSelected: (URL) -> Void

    init(
        tmdbID: Int,
        type: AnimeType,
        originalPosterLanguageCode: String? = nil,
        infoFetcher: InfoFetcher = .init(),
        onPosterSelected: @escaping (URL) -> Void
    ) {
        self.tmdbID = tmdbID
        self.type = type
        self.originalPosterLanguageCode = originalPosterLanguageCode
        self.fetcher = infoFetcher
        self.onPosterSelected = onPosterSelected
    }

    @State private var loadState: LoadState = .loading
    @State private var availablePosters: [Poster] = []
    @State private var seriesPosters: [Poster] = []
    @State private var previewPoster: Poster?
    @State private var useSeriesPoster: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Namespace private var preview
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    private var currentPosters: [Poster] {
        useSeriesPoster ? seriesPosters : availablePosters
    }
    private var metadataLanguageCode: String {
        (followsSystemLanguage ? Language.current : preferredLanguage).rawValue
    }

    @MainActor
    private struct Constants {
        static let idealPosterWidth: Int = 200
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if case .season = type {
                    Picker(selection: $useSeriesPoster) {
                        Text("Season").tag(false)
                        Text("TV Series").tag(true)
                    } label: {
                    }
                    .pickerStyle(.segmented)
                }

                switch loadState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                case .loaded:
                    PosterGridView(
                        posters: currentPosters,
                        previewNamespace: preview,
                        onPosterTap: { poster in
                            previewPoster = poster
                        }
                    )
                case .empty:
                    ContentUnavailableView(
                        "No Posters Available",
                        systemImage: "photo.on.rectangle",
                        description: Text(
                            "TMDb did not return posters for this selection yet.")
                    )
                case .error(let error):
                    ContentUnavailableView(
                        "Error Loading Posters",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(item: $previewPoster) { poster in
            PosterSlides(
                posters: currentPosters,
                currentPoster: poster,
                onPosterSelected: { url in
                    if let url {
                        onPosterSelected(url)
                    }
                    dismiss()
                }
            )
            .navigationTransition(
                .zoom(
                    sourceID: poster.metadata.filePath,
                    in: preview))
        }
        .onChange(of: useSeriesPoster, initial: false) { _, newValue in
            guard case .season = type else { return }
            previewPoster = nil
            Task {
                if newValue {
                    await fetchSeriesPostersIfNeeded()
                } else {
                    syncLoadState()
                }
            }
        }
        .task { await fetchPrimaryPosters() }
    }

    // MARK: - Data Fetching

    @MainActor
    private func fetchPrimaryPosters() async {
        do {
            loadState = .loading
            let resolvedPosters = try await primaryPosterRequest()
            availablePosters = resolvedPosters.filteredAndSorted(
                originalLanguageCode: originalPosterLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
            syncLoadState()
        } catch {
            logger.error("Error fetching posters: \(error.localizedDescription)")
            loadState = .error(error)
        }
    }

    @MainActor
    private func fetchSeriesPostersIfNeeded() async {
        guard case .season(_, let parentSeriesID) = type else { return }
        if !seriesPosters.isEmpty {
            syncLoadState()
            return
        }

        do {
            loadState = .loading
            seriesPosters = try await fetcher.postersForSeries(
                seriesID: parentSeriesID,
                idealWidth: Constants.idealPosterWidth
            )
            .filteredAndSorted(
                originalLanguageCode: originalPosterLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
            syncLoadState()
        } catch {
            logger.error("Error fetching posters: \(error.localizedDescription)")
            loadState = .error(error)
        }
    }

    @MainActor
    private func primaryPosterRequest() async throws -> [Poster] {
        switch type {
        case .movie:
            return try await fetcher.postersForMovie(
                for: tmdbID, idealWidth: Constants.idealPosterWidth)
        case .series:
            return try await fetcher.postersForSeries(
                seriesID: tmdbID, idealWidth: Constants.idealPosterWidth)
        case .season(let seasonNumber, let parentSeriesID):
            return try await fetcher.postersForSeason(
                forSeason: seasonNumber, inParentSeries: parentSeriesID,
                idealWidth: Constants.idealPosterWidth)
        }
    }

    @MainActor
    private func syncLoadState() {
        loadState = currentPosters.isEmpty ? .empty : .loaded
    }

    private enum LoadState: Equatable {
        case loading
        case loaded
        case empty
        case error(Error)

        static func == (lhs: LoadState, rhs: LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.loaded, .loaded), (.empty, .empty): return true
            case (.error, .error): return true
            default: return false
            }
        }
    }
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
