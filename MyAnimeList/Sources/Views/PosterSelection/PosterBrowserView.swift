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
    @State private var postersBySource: [PosterSource: [Poster]] = [:]
    @State private var useSeriesPoster = false
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    private var currentPosters: [Poster] {
        postersBySource[selectedPosterSource] ?? []
    }

    private var selectedPosterSource: PosterSource {
        if useSeriesPoster, case .season(_, let parentSeriesID) = type {
            return .series(parentSeriesID)
        }
        return primaryPosterSource
    }

    private var primaryPosterSource: PosterSource {
        switch type {
        case .movie:
            return .movie(tmdbID)
        case .series:
            return .series(tmdbID)
        case .season(let seasonNumber, let parentSeriesID):
            return .season(number: seasonNumber, parentSeriesID: parentSeriesID)
        }
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
        .task(id: selectedPosterSource) {
            let source = selectedPosterSource
            await loadPosters(for: source)
        }
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
    private func loadPosters(for source: PosterSource) async {
        if let cachedPosters = postersBySource[source] {
            guard selectedPosterSource == source else { return }
            loadState = cachedPosters.isEmpty ? .empty : .loaded
            return
        }

        do {
            loadState = .loading
            let resolvedPosters = try await posterRequest(for: source)
            guard !Task.isCancelled, selectedPosterSource == source else { return }
            let posters = resolvedPosters.filteredAndSorted(
                originalLanguageCode: originalPosterLanguageCode,
                metadataLanguageCode: metadataLanguageCode
            )
            postersBySource[source] = posters
            loadState = posters.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, selectedPosterSource == source else { return }
            logger.error("Error fetching posters: \(error.localizedDescription)")
            loadState = .error(error)
        }
    }

    @MainActor
    private func posterRequest(for source: PosterSource) async throws -> [Poster] {
        switch source {
        case .movie(let id):
            return try await fetcher.postersForMovie(
                for: id,
                idealWidth: Constants.idealPosterWidth
            )
        case .series(let id):
            return try await fetcher.postersForSeries(
                seriesID: id,
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

    private enum PosterSource: Hashable {
        case movie(Int)
        case series(Int)
        case season(number: Int, parentSeriesID: Int)
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
