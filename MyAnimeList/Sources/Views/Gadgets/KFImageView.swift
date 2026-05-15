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
    let url: URL?
    let diskCacheExpiration: StorageExpiration
    let targetWidth: CGFloat?
    let animation: Animation?
    @Binding var imageLoaded: Bool
    @State private var image: UIImage? = nil
    @State private var loadedRequestID: String? = nil

    private var missingImage: UIImage? {
        UIImage(named: "missing-image-resource")
    }

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
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
            } else {
                ProgressView()
                    .frame(minWidth: 100, minHeight: 100)
            }
        }
        .task(id: requestID) { await loadImage(requestID: requestID) }
    }

    private var displayImage: UIImage? {
        if url == nil {
            return missingImage
        }

        guard loadedRequestID == requestID else { return nil }
        return image
    }

    @MainActor
    private func loadImage(requestID: String) async {
        guard let url else {
            image = nil
            loadedRequestID = nil
            imageLoaded = false
            return
        }

        image = nil
        loadedRequestID = nil
        imageLoaded = false

        var kfRetrieveOptions: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .diskCacheExpiration(diskCacheExpiration),
            .onFailureImage(missingImage)
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
                image = result.image
                loadedRequestID = requestID
                imageLoaded = true
            }
        } catch {
            guard !Task.isCancelled, requestID == self.requestID else { return }
            logger.warning("Error loading image: \(error)")
            image = missingImage
            loadedRequestID = requestID
            imageLoaded = false
        }
    }
}
