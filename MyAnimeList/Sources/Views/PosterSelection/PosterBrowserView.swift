//
//  PosterBrowserView.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "PosterBrowserView")

/// Shared poster browser content used by both the standalone picker and the wide sharing composer.
struct PosterBrowserView: View {
    let tmdbID: Int
    let type: AnimeType
    let originalPosterLanguageCode: String?
    let fetcher: InfoFetcher
    let previewNamespace: Namespace.ID
    let selectedPosterPath: String?
    let onPosterTap: (Poster, [Poster]) -> Void

    @State private var loadState: LoadState = .loading
    @State private var availablePosters: [Poster] = []
    @State private var seriesPosters: [Poster] = []
    @State private var useSeriesPoster = false
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
        static let idealPosterWidth = 200
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if case .season = type {
                Picker(selection: $useSeriesPoster) {
                    Text("Season").tag(false)
                    Text("TV Series").tag(true)
                } label: {
                }
                .pickerStyle(.segmented)
            }

            browserContent
        }
        .onChange(of: useSeriesPoster, initial: false) { _, newValue in
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

    @ViewBuilder
    private var browserContent: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        case .loaded:
            PosterGridView(
                posters: currentPosters,
                previewNamespace: previewNamespace,
                selectedPosterPath: selectedPosterPath,
                onPosterTap: { poster in
                    onPosterTap(poster, currentPosters)
                }
            )
        case .empty:
            ContentUnavailableView(
                "No Posters Available",
                systemImage: "photo.on.rectangle",
                description: Text("TMDb did not return posters for this selection yet.")
            )
        case .error(let error):
            ContentUnavailableView(
                "Error Loading Posters",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        }
    }

    @MainActor
    private func fetchPrimaryPosters() async {
        do {
            loadState = .loading
            let resolvedPosters = try await primaryPosterRequest()
            guard !Task.isCancelled else { return }
            availablePosters = resolvedPosters.filteredAndSorted(
                originalLanguageCode: originalPosterLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
            syncLoadState()
        } catch is CancellationError {
            return
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
            let resolvedPosters = try await fetcher.postersForSeries(
                seriesID: parentSeriesID,
                idealWidth: Constants.idealPosterWidth
            )
            guard !Task.isCancelled else { return }
            seriesPosters = resolvedPosters.filteredAndSorted(
                originalLanguageCode: originalPosterLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
            syncLoadState()
        } catch is CancellationError {
            return
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
                for: tmdbID,
                idealWidth: Constants.idealPosterWidth
            )
        case .series:
            return try await fetcher.postersForSeries(
                seriesID: tmdbID,
                idealWidth: Constants.idealPosterWidth
            )
        case .season(let seasonNumber, let parentSeriesID):
            return try await fetcher.postersForSeason(
                forSeason: seasonNumber,
                inParentSeries: parentSeriesID,
                idealWidth: Constants.idealPosterWidth
            )
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
            case (.loading, .loading), (.loaded, .loaded), (.empty, .empty):
                return true
            case (.error, .error):
                return true
            default:
                return false
            }
        }
    }
}
