//
//  PosterSlides.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/12/17.
//

import Kingfisher
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "PosterSlides")

/// A view that displays a slidable list of posters for selection.
struct PosterSlides: View {
    let posters: [Poster]
    let currentPoster: Poster

    private let fetcher = InfoFetcher()
    let onPosterSelected: (URL?) -> Void
    @State private var fullSizePosterURLs: [Poster: URL] = [:]
    @State private var fetchState: FetchState = .idle
    @State private var currentSlideID: String?
    @State private var showSelectionConfirmation = false

    var body: some View {
        Group {
            switch fetchState {
            case .idle, .loading:
                loadingView
            case .empty:
                emptyView
            case .failed(let message):
                errorView(message)
            case .loaded:
                loadedView
            }
        }
        .task(id: posters) {
            await loadPosterURLsOnAppear(force: true)
        }
        .alert("Use this poster?", isPresented: $showSelectionConfirmation, presenting: currentSlide) {
            slide in
            Button("Use Poster") {
                onPosterSelected(slide.url)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This will replace the current poster.")
        }
    }

    private var loadedView: some View {
        VStack(spacing: 12) {
            TabView(selection: $currentSlideID) {
                ForEach(loadedPosters, id: \.poster.id) { item in
                    KFImageView(url: item.url, diskCacheExpiration: .shortTerm)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 15))
                        .containerRelativeFrame(.vertical)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .tag(item.poster.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            if let slide = currentSlide {
                VStack(spacing: 15) {
                    Text("\(slide.poster.metadata.width) x \(slide.poster.metadata.height)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Button("Use this poster") {
                        showSelectionConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private var loadedPosters: [(poster: Poster, url: URL)] {
        posters.compactMap { poster in
            guard let url = fullSizePosterURLs[poster] else { return nil }
            return (poster: poster, url: url)
        }
    }

    private var currentSlide: (poster: Poster, url: URL)? {
        guard let first = loadedPosters.first else { return nil }
        if let currentSlideID,
            let match = loadedPosters.first(where: { $0.poster.id == currentSlideID })
        {
            return match
        }
        return first
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading posters...")
            Spacer()
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("No posters available right now.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadPosterURLsOnAppear(force: true) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Failed to load posters.")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadPosterURLsOnAppear(force: true) }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
    }

    @MainActor
    private func loadPosterURLsOnAppear(force: Bool = false) async {
        guard force || fetchState == .idle else { return }
        fetchState = .loading
        fullSizePosterURLs = [:]

        let result = await fetchAllFullSizePosterURLs()
        fullSizePosterURLs = result.urlMap

        updateCurrentSlide(with: result.urlMap)

        if !result.urlMap.isEmpty {
            fetchState = .loaded
        } else if let firstError = result.errors.first {
            fetchState = .failed(firstError.localizedDescription)
        } else {
            fetchState = .empty
        }
    }

    private func fetchAllFullSizePosterURLs() async -> (urlMap: [Poster: URL], errors: [Error]) {
        await withTaskGroup(of: (Poster, Result<URL, Error>).self) { group in
            for poster in posters {
                group.addTask {
                    do {
                        let url = try await fetchFullSizeURL(for: poster)
                        return (poster, .success(url))
                    } catch {
                        return (poster, .failure(error))
                    }
                }
            }

            var urlMap: [Poster: URL] = [:]
            var errors: [Error] = []

            for await (poster, result) in group {
                switch result {
                case .success(let url):
                    urlMap[poster] = url
                case .failure(let error):
                    errors.append(error)
                    logger.error("Error fetching preview poster image: \(error.localizedDescription)")
                }
            }

            return (urlMap, errors)
        }
    }

    private func fetchFullSizeURL(for poster: Poster) async throws -> URL {
        let path = poster.metadata.filePath
        guard
            let url =
                try await fetcher
                .tmdbClient
                .imagesConfiguration
                .posterURL(for: path)
        else {
            throw PosterSlidesError.fullSizeURLMissing
        }
        return url
    }

    private func updateCurrentSlide(with urlMap: [Poster: URL]) {
        if let currentSlideID, urlMap.keys.contains(where: { $0.id == currentSlideID }) {
            return
        }

        if let match = urlMap.keys.first(where: { $0.id == currentPoster.id }) {
            currentSlideID = match.id
        } else if let first = urlMap.keys.first {
            currentSlideID = first.id
        } else {
            currentSlideID = nil
        }
    }

    private enum PosterSlidesError: LocalizedError {
        case fullSizeURLMissing

        var errorDescription: String? {
            switch self {
            case .fullSizeURLMissing:
                return "TMDb did not return a full-size poster URL."
            }
        }
    }

    private enum FetchState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }
}
