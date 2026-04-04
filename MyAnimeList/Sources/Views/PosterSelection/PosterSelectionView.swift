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
    let fetcher: InfoFetcher
    let onPosterSelected: (URL) -> Void
    @State private var imageLoadState: ImageLoadState = .loading

    init(tmdbID: Int, type: AnimeType, infoFetcher: InfoFetcher = .init(), onPosterSelected: @escaping (URL) -> Void) {
        self.tmdbID = tmdbID
        self.type = type
        self.fetcher = infoFetcher
        self.onPosterSelected = onPosterSelected
    }

    @State var availablePosters: [Poster] = []
    @State var seriesPosters: [Poster] = []
    @State var previewPoster: Poster?
    @State var useSeriesPoster: Bool = false
    @Environment(\.dismiss) var dismiss
    @Namespace var preview

    private var currentPosters: [Poster] {
        useSeriesPoster ? seriesPosters : availablePosters
    }

    @MainActor
    private struct Constants {
        /// The ideal width for poster images to fetch from TMDb.
        static let idealPosterWidth: Int = 200
        static let pickerPadding: CGFloat = 5
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if case .season = type {
                    PopupSectionCard("Poster Source", systemImage: "square.stack") {
                        Picker(selection: $useSeriesPoster) {
                            Text("Season").tag(false)
                            Text("TV Series").tag(true)
                        } label: {
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, Constants.pickerPadding)
                    }
                }

                PopupSectionCard("Posters", systemImage: "photo.on.rectangle") {
                    switch imageLoadState {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    case .loaded:
                        posterGrid
                    case .empty:
                        contentUnavailable
                    case .error(let error):
                        Text("Error loading posters: \(error.localizedDescription)")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .animation(.default.delay(0.5), value: useSeriesPoster)
        .animation(.default, value: availablePosters)
        .animation(.default, value: seriesPosters)
        .padding(.horizontal, 16)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .fullScreenCover(item: $previewPoster) { poster in
            PosterSlides(
                posters: availablePosters,
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
            Task {
                if newValue {
                    await fetchSeriesPostersIfNeeded()
                } else {
                    await ensurePrimaryPostersLoadedIfNeeded()
                }
            }
        }
        .task {
            await ensurePrimaryPostersLoadedIfNeeded()
        }
    }

    @ViewBuilder
    private var posterGrid: some View {
        PosterGridView(
            posters: currentPosters,
            previewNamespace: preview,
            onPosterTap: { poster in
                previewPoster = poster
            }
        )
    }

    @ViewBuilder
    private var contentUnavailable: some View {
        ContentUnavailableView(
            "No Posters Available",
            systemImage: "photo.on.rectangle",
            description: Text("TMDb did not return posters for this selection yet.")
        )
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }

    @MainActor
    private func ensurePrimaryPostersLoadedIfNeeded() async {
        if availablePosters.isEmpty {
            await fetchPrimaryPosters()
        } else {
            syncLoadStateWithCurrentData()
        }
    }

    /// Fetches posters for the current TMDb entity (movie/series/season) and updates state.
    ///
    /// This is the default poster path; seasons use it unless toggled to parent-series posters.
    @MainActor
    private func fetchPrimaryPosters() async {
        do {
            imageLoadState = .loading
            let posters = try await primaryPosterRequest()
            availablePosters = posters.filteredAndSorted()
            if !useSeriesPoster {
                syncLoadStateWithCurrentData(sourceOverride: availablePosters)
            }
        } catch {
            logger.error("Error fetching posters: \(error.localizedDescription)")
            imageLoadState = .error(error)
        }
    }

    @MainActor
    private func fetchSeriesPostersIfNeeded() async {
        guard case .season(_, let parentSeriesID) = type else { return }
        if !seriesPosters.isEmpty {
            if useSeriesPoster {
                syncLoadStateWithCurrentData()
            }
            return
        }

        do {
            imageLoadState = .loading
            seriesPosters = try await fetcher.postersForSeries(
                seriesID: parentSeriesID,
                idealWidth: Constants.idealPosterWidth
            )
            .filteredAndSorted()
            if useSeriesPoster {
                syncLoadStateWithCurrentData(sourceOverride: seriesPosters)
            }
        } catch {
            logger.error("Error fetching posters: \(error.localizedDescription)")
            imageLoadState = .error(error)
        }
    }

    /// Builds and executes the primary poster request based on the current anime type.
    @MainActor
    private func primaryPosterRequest() async throws -> [Poster] {
        switch type {
        case .movie:
            return try await fetcher.postersForMovie(
                for: tmdbID,
                idealWidth: Constants.idealPosterWidth)
        case .series:
            return try await fetcher.postersForSeries(
                seriesID: tmdbID,
                idealWidth: Constants.idealPosterWidth)
        case .season(let seasonNumber, let parentSeriesID):
            return try await fetcher.postersForSeason(
                forSeason: seasonNumber,
                inParentSeries: parentSeriesID,
                idealWidth: Constants.idealPosterWidth)
        }
    }

    /// Syncs the displayed load state with the provided posters (or current selection).
    @MainActor
    private func syncLoadStateWithCurrentData(sourceOverride: [Poster]? = nil) {
        let posters = sourceOverride ?? currentPosters
        imageLoadState = posters.isEmpty ? .empty : .loaded
    }

    private enum ImageLoadState {
        case loading
        case loaded
        case empty
        case error(Error)
    }
}

extension Array where Element == Poster {
    func filteredAndSorted(language: Language = .japanese) -> [Poster] {
        let prioritized = self.sorted {
            $0.metadata.width > $1.metadata.width
        }

        let filtered = prioritized.filter { $0.metadata.languageCode == language.rawValue }
        return filtered.isEmpty ? prioritized : filtered
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
