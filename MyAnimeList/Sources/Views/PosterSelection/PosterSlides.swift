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

    private let contentTransitionAnimation = Animation.easeInOut(duration: 0.2)

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            switch fetchState {
            case .idle, .loading:
                loadingView
                    .transition(.opacity)
            case .empty:
                emptyView
                    .transition(.opacity)
            case .failed(let message):
                errorView(message)
                    .transition(.opacity)
            case .loaded:
                loadedView
                    .padding()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(contentTransitionAnimation, value: fetchState)
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
            // A page-styled TabView can recalculate its page geometry as remote images load,
            // producing visible jitter during a swipe. Full-container scroll targets keep
            // each page stable while retaining the system's native paging behavior.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(loadedPosters, id: \.poster.id) { item in
                        posterPage(for: item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentSlideID)

            PosterPageIndicator(
                numberOfPages: loadedPosters.count,
                currentPage: currentSlideIndex
            )
            .frame(height: 8)

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

    private func posterPage(for item: (poster: Poster, url: URL)) -> some View {
        let width = item.poster.metadata.width
        let height = item.poster.metadata.height
        let aspectRatio = CGFloat(width) / CGFloat(max(height, 1))

        return KFImageView(
            url: item.url,
            animation: contentTransitionAnimation,
            diskCacheExpiration: .shortTerm
        )
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 15))
        .padding(8)
        .containerRelativeFrame([.horizontal, .vertical])
        .id(item.poster.id)
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

    private var currentSlideIndex: Int {
        guard let currentSlideID else { return 0 }
        return loadedPosters.firstIndex(where: { $0.poster.id == currentSlideID }) ?? 0
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

/// Mirrors the current scroll target with system page dots.
///
/// ScrollView paging does not
/// provide them, and disabling interaction keeps swipe ownership in the ScrollView.
fileprivate struct PosterPageIndicator: UIViewRepresentable {
    let numberOfPages: Int
    let currentPage: Int

    func makeUIView(context: Context) -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.isUserInteractionEnabled = false
        pageControl.currentPageIndicatorTintColor = .secondaryLabel
        pageControl.pageIndicatorTintColor = .tertiaryLabel
        return pageControl
    }

    func updateUIView(_ pageControl: UIPageControl, context: Context) {
        pageControl.numberOfPages = numberOfPages
        pageControl.currentPage = currentPage
        pageControl.hidesForSinglePage = true
    }
}
