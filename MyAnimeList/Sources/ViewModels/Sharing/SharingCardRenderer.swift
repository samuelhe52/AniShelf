import Foundation
import SwiftUI
import UIKit
import os

/// Output payload returned after a poster render completes.
@MainActor
struct SharingCardRenderOutcome {
    /// Final PNG, HEIC, or JPEG location.
    let imageURL: URL
    /// Aspect ratio used to render the card, already clamped to allowed bounds.
    let aspectRatio: CGFloat
    /// Pixel dimensions of the persisted image.
    let pixelSize: CGSize
}

/// Handles poster loading, caching, and export so the view model stays lean.
@MainActor
final class SharingCardRenderer {
    private let pipeline: SharingCardExportPipeline
    private let defaultAspectRatio: CGFloat
    private let minAspectRatio: CGFloat
    private let maxAspectRatio: CGFloat

    private var renderCache: [SharingCardRenderTrigger: SharingCardRenderOutcome] = [:]
    private struct LoadedPosterKey: Equatable {
        let url: URL
        let exportSize: SharingCardExportSize
    }

    private var lastLoadedPosterKey: LoadedPosterKey?
    private var cachedImage: UIImage?
    private var lastRenderedImageKey: SharingCardVisualRenderKey?
    private var cachedRenderedImage: UIImage?

    private let logger = Logger(subsystem: "com.samuelhe.MyAnimeList", category: "SharingCardRenderer")

    /// Configures a renderer with the desired poster dimensions and quality.
    init(
        baseWidth: CGFloat,
        jpegQuality: CGFloat,
        heicQuality: CGFloat,
        defaultAspectRatio: CGFloat,
        minAspectRatio: CGFloat,
        maxAspectRatio: CGFloat
    ) {
        self.pipeline = SharingCardExportPipeline(
            baseWidth: baseWidth,
            jpegQuality: jpegQuality,
            heicQuality: heicQuality
        )
        self.defaultAspectRatio = defaultAspectRatio
        self.minAspectRatio = minAspectRatio
        self.maxAspectRatio = maxAspectRatio
    }

    /// Produces (or reuses) a rendered poster for the given trigger.
    func renderPoster(
        for trigger: SharingCardRenderTrigger,
        metadata: PosterMetadata,
        fileName: String,
        onPosterLoaded: (UIImage, CGFloat) -> Void
    ) async -> SharingCardRenderOutcome? {
        guard let posterURL = trigger.posterURL else { return nil }
        guard !Task.isCancelled else { return nil }

        if let cachedOutcome = renderCache[trigger] {
            guard
                let image = await loadImageIfNeeded(
                    from: posterURL,
                    exportSize: trigger.exportSize
                )
            else { return nil }
            guard !Task.isCancelled else { return nil }
            onPosterLoaded(image, cachedOutcome.aspectRatio)
            return cachedOutcome
        }

        guard
            let image = await loadImageIfNeeded(
                from: posterURL,
                exportSize: trigger.exportSize
            )
        else { return nil }
        guard !Task.isCancelled else { return nil }

        do {
            let aspectRatio = clampAspectRatio(for: image)
            onPosterLoaded(image, aspectRatio)
            await Task.yield()
            guard !Task.isCancelled else { return nil }
            let renderedImage = try await renderImageIfNeeded(
                from: image,
                metadata: metadata,
                aspectRatio: aspectRatio,
                for: trigger
            )
            guard !Task.isCancelled else { return nil }
            let export = try await pipeline.persistRenderedPoster(
                renderedImage,
                fileName: fileName,
                style: trigger.exportStyle
            )
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: export.imageURL)
                return nil
            }
            let outcome = SharingCardRenderOutcome(
                imageURL: export.imageURL,
                aspectRatio: aspectRatio,
                pixelSize: export.pixelSize
            )
            renderCache[trigger] = outcome
            return outcome
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Error rendering poster: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes cached files and resets the memoized poster bitmap.
    func cleanup() {
        for outcome in renderCache.values {
            try? FileManager.default.removeItem(at: outcome.imageURL)
        }
        renderCache.removeAll()
        cachedImage = nil
        lastLoadedPosterKey = nil
        cachedRenderedImage = nil
        lastRenderedImageKey = nil
    }

    /// Retrieves the poster image, respecting the last-loaded cache.
    private func loadImageIfNeeded(
        from url: URL,
        exportSize: SharingCardExportSize
    ) async -> UIImage? {
        let key = LoadedPosterKey(url: url, exportSize: exportSize)
        if lastLoadedPosterKey == key, let cachedImage {
            return cachedImage
        }

        do {
            let image = try await pipeline.loadImage(from: url, exportSize: exportSize)
            cachedImage = image
            lastLoadedPosterKey = key
            return image
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Error loading image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reuses the normalized rounded bitmap when only PNG/HEIC encoding changes.
    private func renderImageIfNeeded(
        from image: UIImage,
        metadata: PosterMetadata,
        aspectRatio: CGFloat,
        for trigger: SharingCardRenderTrigger
    ) async throws -> UIImage {
        let key = trigger.visualRenderKey
        if lastRenderedImageKey == key, let cachedRenderedImage {
            return cachedRenderedImage
        }

        let renderedImage = try await pipeline.renderPosterImage(
            image: image,
            metadata: metadata,
            aspectRatio: aspectRatio,
            usesRoundedCorners: trigger.exportStyle.usesRoundedCorners,
            exportSize: trigger.exportSize
        )
        try Task.checkCancellation()

        if trigger.exportStyle.usesRoundedCorners {
            cachedRenderedImage = renderedImage
            lastRenderedImageKey = key
        } else {
            cachedRenderedImage = nil
            lastRenderedImageKey = nil
        }
        return renderedImage
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
