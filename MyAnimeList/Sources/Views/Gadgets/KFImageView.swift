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
        case loaded(UIImage)
        case fallback
    }

    let url: URL?
    let diskCacheExpiration: StorageExpiration
    let targetSize: CGSize?
    let cacheOriginalImage: Bool
    let animation: Animation?
    @Binding var imageLoaded: Bool
    @State private var loadState: LoadState = .loading

    private var requestID: String {
        "\(url?.absoluteString ?? "nil")|\(targetSize?.debugDescription ?? "nil")|\(cacheOriginalImage)"
    }

    init(
        url: URL?,
        targetWidth: CGFloat? = nil,
        targetSize: CGSize? = nil,
        cacheOriginalImage: Bool = false,
        animation: Animation? = .default,
        diskCacheExpiration: StorageExpiration,
        imageLoaded: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self.animation = animation
        self.diskCacheExpiration = diskCacheExpiration
        self.targetSize = targetSize ?? targetWidth.map(PosterImageSize.targetSize(width:))
        self.cacheOriginalImage = cacheOriginalImage
        self._imageLoaded = imageLoaded
    }

    var body: some View {
        Group {
            switch loadState {
            case .loaded(let displayImage):
                Image(uiImage: displayImage)
                    .resizable()
            case .fallback:
                fallbackImage
            case .loading:
                ProgressView()
                    .frame(minWidth: 100, minHeight: 100)
            }
        }
        .task(id: requestID) { await loadImage(requestID: requestID) }
    }

    private var fallbackImage: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))

            Image(systemName: "photo.badge.exclamationmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.system(size: targetSize == nil ? 28 : 48, weight: .regular))
        }
    }

    @MainActor
    private func loadImage(requestID: String) async {
        guard let url else {
            loadState = .fallback
            imageLoaded = false
            return
        }

        loadState = .loading
        imageLoaded = false

        var kfRetrieveOptions: KingfisherOptionsInfo = [
            .diskCacheExpiration(diskCacheExpiration)
        ]

        if cacheOriginalImage {
            kfRetrieveOptions.append(.cacheOriginalImage)
        }

        if let targetSize {
            let processor = DownsamplingImageProcessor(size: targetSize)
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
