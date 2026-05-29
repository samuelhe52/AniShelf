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
    let targetWidth: CGFloat?
    let animation: Animation?
    @Binding var imageLoaded: Bool
    @State private var loadState: LoadState = .loading

    private var requestID: String {
        "\(url?.absoluteString ?? "nil")|\(targetWidth?.description ?? "nil")"
    }

    init(
        url: URL?,
        targetWidth: CGFloat? = nil,
        animation: Animation? = .default,
        diskCacheExpiration: StorageExpiration,
        imageLoaded: Binding<Bool> = .constant(false)
    ) {
        self.url = url
        self.animation = animation
        self.diskCacheExpiration = diskCacheExpiration
        self.targetWidth = targetWidth
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
                .font(.system(size: targetWidth == nil ? 28 : 48, weight: .regular))
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
            .cacheOriginalImage,
            .diskCacheExpiration(diskCacheExpiration)
        ]

        if let targetWidth {
            let size = CGSize(width: targetWidth, height: targetWidth * 1.5)
            let processor = DownsamplingImageProcessor(size: size)
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
