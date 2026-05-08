import DataProvider
import Foundation
import Kingfisher
import SwiftUI

@MainActor
enum LibraryImageCacheService {
    static func prefetchImages<C: Collection>(for entries: C)
    where C.Element == AnimeEntry {
        let urls = Array(Set(imageURLs(for: entries)))
        ToastCenter.global.progressState =
            .progress(
                current: 0,
                total: urls.count,
                messageResource: "Fetching Images: 0 / \(urls.count)")
        let prefetcher = ImagePrefetcher(
            urls: urls,
            progressBlock: { skipped, failed, completed in
                let total = urls.count
                let current = skipped.count + failed.count + completed.count
                ToastCenter.global.progressState =
                    .progress(
                        current: current,
                        total: total,
                        messageResource: "Fetching Images: \(current) / \(total)")
            },
            completionHandler: { skipped, failed, completed in
                var state: ToastCenter.CompletedWithMessage.State = .completed
                let messageResourceString =
                    "Fetched: \(skipped.count + completed.count), failed: \(failed.count)"
                let messageResource = LocalizedStringResource(
                    "Fetched: \(skipped.count + completed.count), failed: \(failed.count)")
                if failed.isEmpty {
                    state = .completed
                } else if completed.isEmpty && skipped.isEmpty {
                    state = .failed
                } else {
                    state = .partialComplete
                }
                ToastCenter.global.progressState = nil
                ToastCenter.global.completionState = .init(
                    state: state,
                    messageResource: messageResource)
                libraryStoreLogger.info("Prefetched images: \(messageResourceString)")
            })
        prefetcher.start()
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
}
