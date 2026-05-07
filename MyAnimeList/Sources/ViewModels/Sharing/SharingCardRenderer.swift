import Foundation
import SwiftUI
import UIKit
import os

/// Output payload returned after a poster render completes.
@MainActor
struct SharingCardRenderOutcome {
    /// Final JPEG location.
    let imageURL: URL
    /// Cached bitmap used for previews while the sheet stays open.
    let image: UIImage?
    /// Aspect ratio used to render the card, already clamped to allowed bounds.
    let aspectRatio: CGFloat
}

/// Handles poster loading, caching, and export so the view model stays lean.
@MainActor
final class SharingCardRenderer {
    private let pipeline: SharingCardExportPipeline
    private let defaultAspectRatio: CGFloat
    private let minAspectRatio: CGFloat
    private let maxAspectRatio: CGFloat

    private var renderCache: [SharingCardRenderTrigger: URL] = [:]
    private var lastLoadedPosterURL: URL?
    private var cachedImage: UIImage?
    private var cachedAspectRatio: CGFloat

    private let logger = Logger(subsystem: "com.samuelhe.MyAnimeList", category: "SharingCardRenderer")

    /// Configures a renderer with the desired poster dimensions and quality.
    init(
        baseWidth: CGFloat,
        jpegQuality: CGFloat,
        defaultAspectRatio: CGFloat,
        minAspectRatio: CGFloat,
        maxAspectRatio: CGFloat
    ) {
        self.pipeline = SharingCardExportPipeline(baseWidth: baseWidth, jpegQuality: jpegQuality)
        self.defaultAspectRatio = defaultAspectRatio
        self.minAspectRatio = minAspectRatio
        self.maxAspectRatio = maxAspectRatio
        self.cachedAspectRatio = defaultAspectRatio
    }

    /// Produces (or reuses) a rendered poster for the given trigger.
    func renderPoster(
        for trigger: SharingCardRenderTrigger,
        metadata: PosterMetadata,
        fileName: String
    ) async -> SharingCardRenderOutcome? {
        guard let posterURL = trigger.posterURL else { return nil }
        guard !Task.isCancelled else { return nil }

        if let cachedURL = renderCache[trigger] {
            return SharingCardRenderOutcome(
                imageURL: cachedURL,
                image: cachedImage,
                aspectRatio: cachedAspectRatio
            )
        }

        guard let image = await loadImageIfNeeded(from: posterURL) else { return nil }
        guard !Task.isCancelled else { return nil }

        do {
            let aspectRatio = clampAspectRatio(for: image)
            let fileURL = try await pipeline.renderPoster(
                image: image,
                metadata: metadata,
                aspectRatio: aspectRatio,
                fileName: fileName
            )
            renderCache[trigger] = fileURL
            cachedAspectRatio = aspectRatio
            return SharingCardRenderOutcome(imageURL: fileURL, image: image, aspectRatio: aspectRatio)
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Error rendering poster: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes cached files and resets any memoized bitmaps/aspect ratios.
    func cleanup() {
        for url in renderCache.values {
            try? FileManager.default.removeItem(at: url)
        }
        renderCache.removeAll()
        cachedImage = nil
        lastLoadedPosterURL = nil
        cachedAspectRatio = defaultAspectRatio
    }

    /// Retrieves the poster image, respecting the last-loaded cache.
    private func loadImageIfNeeded(from url: URL) async -> UIImage? {
        if lastLoadedPosterURL == url, let cachedImage {
            return cachedImage
        }

        do {
            let image = try await pipeline.loadImage(from: url)
            cachedImage = image
            lastLoadedPosterURL = url
            cachedAspectRatio = clampAspectRatio(for: image)
            return image
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Error loading image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Converts an image's intrinsic ratio into the nearest supported variant.
    private func clampAspectRatio(for image: UIImage) -> CGFloat {
        let ratio = image.size.width / max(image.size.height, 1)
        return clampAspectRatio(ratio)
    }

    /// Hard-limits arbitrary aspect ratios so the layout stays predictable.
    private func clampAspectRatio(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return defaultAspectRatio }
        return min(max(ratio, minAspectRatio), maxAspectRatio)
    }
}
