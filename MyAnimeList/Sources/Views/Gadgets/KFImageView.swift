//
//  KFImageView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/11.
//

import Kingfisher
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "PosterView")

struct KFImageView: View {
    private enum LoadState {
        case loading
        case loaded(PlatformImage)
        case fallback
    }

    let url: URL?
    let diskCacheExpiration: StorageExpiration
    private let processor: (any ImageProcessor)?
    let cacheOriginalImage: Bool
    let animation: Animation?
    @Binding var imageLoaded: Bool
    @State private var loadState: LoadState = .loading

    private var requestID: String {
        "\(url?.absoluteString ?? "nil")|\(processor?.identifier ?? "nil")|\(cacheOriginalImage)"
    }

    /// Shows a library image at its catalog variant, so it shares cache entries with prefetch.
    init(
        image: TMDbImage?,
        cacheOriginalImage: Bool = false,
        animation: Animation? = .default,
        diskCacheExpiration: StorageExpiration,
        imageLoaded: Binding<Bool> = .constant(false)
    ) {
        self.init(
            url: image?.url,
            processor: image?.processor,
            cacheOriginalImage: cacheOriginalImage,
            animation: animation,
            diskCacheExpiration: diskCacheExpiration,
            imageLoaded: imageLoaded
        )
    }

    /// Shows an image outside the variant catalog, such as a search result or a poster picker
    /// page. These are not prefetched or removed with library entries.
    ///
    /// - Parameter maxPixelDimension: The longest edge of the decoded bitmap; `nil` decodes at
    ///   full size.
    init(
        url: URL?,
        maxPixelDimension: CGFloat? = nil,
        cacheOriginalImage: Bool = false,
        animation: Animation? = .default,
        diskCacheExpiration: StorageExpiration,
        imageLoaded: Binding<Bool> = .constant(false)
    ) {
        self.init(
            url: url,
            processor: url.flatMap { url in
                maxPixelDimension.map {
                    LibraryImageProcessorFactory.processor(for: url, maxPixelDimension: $0)
                } ?? LibraryImageProcessorFactory.unsizedProcessor(for: url)
            },
            cacheOriginalImage: cacheOriginalImage,
            animation: animation,
            diskCacheExpiration: diskCacheExpiration,
            imageLoaded: imageLoaded
        )
    }

    private init(
        url: URL?,
        processor: (any ImageProcessor)?,
        cacheOriginalImage: Bool,
        animation: Animation?,
        diskCacheExpiration: StorageExpiration,
        imageLoaded: Binding<Bool>
    ) {
        self.url = url
        self.processor = processor
        self.animation = animation
        self.diskCacheExpiration = diskCacheExpiration
        self.cacheOriginalImage = cacheOriginalImage
        self._imageLoaded = imageLoaded
        // Lazy grids and lists recreate their cells, for example when a window resize changes the
        // column count. Starting from the memory cache keeps those cells from flashing a spinner.
        if let cachedImage = Self.memoryCachedImage(url: url, processor: processor) {
            self._loadState = State(initialValue: .loaded(cachedImage))
        }
    }

    private static func memoryCachedImage(url: URL?, processor: (any ImageProcessor)?) -> PlatformImage? {
        guard let url else { return nil }
        var options = KingfisherParsedOptionsInfo(nil)
        if let processor {
            options.processor = processor
        }
        return KingfisherManager.shared.cache.retrieveImageInMemoryCache(
            forKey: url.cacheKey,
            options: options
        )
    }

    var body: some View {
        Group {
            switch loadState {
            case .loaded(let displayImage):
                Image(platformImage: displayImage)
                    .resizable()
            case .fallback:
                fallbackImage
            case .loading:
                ProgressView()
                    #if os(macOS)
                        .controlSize(.small)
                    #endif
                    .frame(minWidth: 100, minHeight: 100)
            }
        }
        .task(id: requestID) { await loadImage(requestID: requestID) }
    }

    private var fallbackImage: some View {
        ZStack {
            Rectangle()
                .fill(Color.platformSecondarySystemFill)

            Image(systemName: "photo.badge.exclamationmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.system(size: processor == nil ? 28 : 48, weight: .regular))
        }
    }

    @MainActor
    private func loadImage(requestID: String) async {
        guard let url else {
            loadState = .fallback
            imageLoaded = false
            return
        }

        if let cachedImage = Self.memoryCachedImage(url: url, processor: processor) {
            loadState = .loaded(cachedImage)
            imageLoaded = true
            return
        }

        loadState = .loading
        imageLoaded = false

        var kfRetrieveOptions: KingfisherOptionsInfo = [
            // Keep disk existence probes on Kingfisher's I/O queue after a memory miss.
            .asyncCacheTypeCheck,
            .diskCacheExpiration(diskCacheExpiration)
        ]

        if cacheOriginalImage {
            kfRetrieveOptions.append(.cacheOriginalImage)
        }

        if let processor {
            kfRetrieveOptions.append(.processor(processor))
        }

        do {
            let result = try await KingfisherManager.shared
                .retrieveImage(with: url, options: kfRetrieveOptions)
            guard !Task.isCancelled, requestID == self.requestID else { return }
            // Only animate if the image was fetched from network (not cached)
            let shouldAnimate = result.cacheType == .none
            withAnimation(shouldAnimate ? animation : nil) {
                loadState = .loaded(result.image)
                imageLoaded = true
            }
        } catch {
            guard !Task.isCancelled, requestID == self.requestID else { return }
            logger.warning("Error loading image: \(error)")
            withAnimation(animation) {
                loadState = .fallback
                imageLoaded = false
            }
        }
    }
}
