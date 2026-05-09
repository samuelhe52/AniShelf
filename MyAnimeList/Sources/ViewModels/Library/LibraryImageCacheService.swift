import DataProvider
import Foundation
import Kingfisher
import SwiftUI

@MainActor
enum LibraryImageCacheService {
    static func prefetchImages<C: Collection>(
        for entries: C,
        reporter: LibraryRefreshReporter = .toast
    )
    where C.Element == AnimeEntry {
        let urls = Array(Set(imageURLs(for: entries)))
        Task {
            _ = await prefetchImagesNow(urls: urls, reporter: reporter)
        }
    }

    @discardableResult
    static func prefetchImagesNow<C: Collection>(
        for entries: C,
        reporter: LibraryRefreshReporter = .toast
    ) async -> LibraryRefreshCompletion where C.Element == AnimeEntry {
        let urls = Array(Set(imageURLs(for: entries)))
        return await prefetchImagesNow(urls: urls, reporter: reporter)
    }

    @discardableResult
    private static func prefetchImagesNow(
        urls: [URL],
        reporter: LibraryRefreshReporter
    ) async -> LibraryRefreshCompletion {
        reporter.report(
            .imagePrefetchProgress(
                current: 0,
                total: urls.count,
                messageResource: "Fetching Images: 0 / \(urls.count)"
            )
        )

        guard !urls.isEmpty else {
            let completion = LibraryRefreshCompletion(
                state: .completed,
                messageResource: "Fetched: 0, failed: 0",
                successfulItemCount: 0,
                failedItemCount: 0
            )
            reporter.report(.imagePrefetchPhaseComplete(completion))
            return completion
        }

        let session = PrefetchSession()
        return await withCheckedContinuation { continuation in
            let prefetcher = ImagePrefetcher(
                urls: urls,
                progressBlock: { skipped, failed, completed in
                    let total = urls.count
                    let current = skipped.count + failed.count + completed.count
                    Task { @MainActor in
                        reporter.report(
                            .imagePrefetchProgress(
                                current: current,
                                total: total,
                                messageResource: "Fetching Images: \(current) / \(total)"
                            )
                        )
                    }
                },
                completionHandler: { skipped, failed, completed in
                    let fetchedCount = skipped.count + completed.count
                    let failedCount = failed.count
                    let state: LibraryRefreshCompletionState

                    if failed.isEmpty {
                        state = .completed
                    } else if completed.isEmpty && skipped.isEmpty {
                        state = .failed
                    } else {
                        state = .partialComplete
                    }

                    let completion = LibraryRefreshCompletion(
                        state: state,
                        messageResource: "Fetched: \(fetchedCount), failed: \(failedCount)",
                        successfulItemCount: fetchedCount,
                        failedItemCount: failedCount
                    )
                    Task { @MainActor in
                        reporter.report(.imagePrefetchPhaseComplete(completion))
                        libraryStoreLogger.info(
                            "Prefetched images: Fetched: \(fetchedCount), failed: \(failedCount)"
                        )
                        session.prefetcher = nil
                        continuation.resume(returning: completion)
                    }
                }
            )
            session.prefetcher = prefetcher
            prefetcher.start()
        }
    }

    static func imageURLs<C: Collection>(for entries: C) -> [URL]
    where C.Element == AnimeEntry {
        entries.flatMap { entry in
            [entry.posterURL, entry.detail?.heroImageURL, entry.detail?.logoImageURL].compactMap(\.self)
        }
    }

    static func relatedImageURLs(for entry: AnimeEntry) -> Set<URL> {
        var urls = Set([entry.posterURL, entry.backdropURL].compactMap(\.self))

        if let detail = entry.detail {
            urls.formUnion([detail.heroImageURL, detail.logoImageURL].compactMap(\.self))
            urls.formUnion(detail.characters.compactMap(\.profileURL))
            urls.formUnion(detail.staff.compactMap(\.profileURL))
            urls.formUnion(detail.seasons.compactMap(\.posterURL))
            urls.formUnion(detail.episodes.compactMap(\.imageURL))
        }

        return urls
    }

    static func removeCachedImages(for urls: Set<URL>) {
        guard !urls.isEmpty else { return }

        let cacheKeys = Array(urls.map(\.cacheKey))
        let processorIdentifiers = Self.cachedImageProcessorIdentifiers

        Task.detached(priority: .utility) {
            let cache = KingfisherManager.shared.cache
            var removedCount = 0

            for cacheKey in cacheKeys {
                for processorIdentifier in processorIdentifiers {
                    do {
                        try await cache.removeImage(
                            forKey: cacheKey,
                            processorIdentifier: processorIdentifier
                        )
                        removedCount += 1
                    } catch {
                        libraryStoreLogger.warning("Failed to remove cached image for key \(cacheKey): \(error)")
                    }
                }
            }

            libraryStoreLogger.info("Removed \(removedCount) Kingfisher cache entries for deleted library content.")
        }
    }

    private static let cachedImageProcessorIdentifiers: [String] = {
        let downsampledIdentifiers = [240, 300, 360, 500, 720, 800, 1_200].map { targetWidth in
            let size = CGSize(width: targetWidth, height: targetWidth * 1.5)
            return DownsamplingImageProcessor(size: size).identifier
        }
        return [""] + downsampledIdentifiers
    }()

    private final class PrefetchSession {
        var prefetcher: ImagePrefetcher?
    }
}
