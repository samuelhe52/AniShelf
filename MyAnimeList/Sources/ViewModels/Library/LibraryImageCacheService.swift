//
//  LibraryImageCacheService.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/7.
//

import DataProvider
import Foundation
import Kingfisher
import SwiftUI

@MainActor
enum LibraryImageCacheService {
    private static let prefetchDiskCacheExpiration: StorageExpiration = .longTerm

    static func galleryPosterDiskCacheExpiration(
        longTermCachingEnabled: Bool = false
    ) -> StorageExpiration {
        longTermCachingEnabled ? .longTerm : .shortTerm
    }

    static func prefetchImages<C: Collection>(
        for entries: C,
        longTermGalleryPosterCachingEnabled: Bool = false,
        reporter: LibraryRefreshReporter = .toast
    )
    where C.Element == AnimeEntry {
        let targets = imagePrefetchTargets(
            for: entries,
            longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
        )
        Task {
            _ = await prefetchImageTargetsNow(
                targets,
                diskCacheExpiration: prefetchDiskCacheExpiration,
                reporter: reporter
            )
        }
    }

    @discardableResult
    static func prefetchImagesNow<C: Collection>(
        for entries: C,
        longTermGalleryPosterCachingEnabled: Bool = false,
        reporter: LibraryRefreshReporter = .toast
    ) async -> LibraryRefreshCompletion where C.Element == AnimeEntry {
        let targets = imagePrefetchTargets(
            for: entries,
            longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
        )
        return await prefetchImageTargetsNow(
            targets,
            diskCacheExpiration: prefetchDiskCacheExpiration,
            reporter: reporter
        )
    }

    @discardableResult
    static func prefetchImagesForRefreshPhaseNow<C: Collection>(
        for entries: C,
        longTermGalleryPosterCachingEnabled: Bool = false,
        reporter: LibraryRefreshReporter
    ) async -> LibraryRefreshCompletion where C.Element == AnimeEntry {
        let targets = imagePrefetchTargets(
            for: entries,
            longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
        )
        return await prefetchImagePhaseTargetsNow(
            targets,
            diskCacheExpiration: prefetchDiskCacheExpiration,
            reporter: reporter
        )
    }

    /// Prefetches the supplied image targets as the image phase of a library refresh.
    ///
    /// Use this overload when refresh metadata has already been materialized outside the main
    /// model context. Passing targets directly lets callers prefetch the newly fetched remote
    /// assets without depending on stale `AnimeEntry` instances.
    ///
    /// - Parameters:
    ///   - targets: The poster, hero, and logo image variants to prefetch.
    ///   - reporter: The reporter that receives image prefetch phase progress and completion.
    /// - Returns: The completion summary for the image prefetch phase.
    @discardableResult
    static func prefetchImageTargetsForRefreshPhaseNow(
        _ targets: [TMDbImage],
        reporter: LibraryRefreshReporter
    ) async -> LibraryRefreshCompletion {
        await prefetchImagePhaseTargetsNow(
            Array(Set(targets)),
            diskCacheExpiration: prefetchDiskCacheExpiration,
            reporter: reporter
        )
    }

    @discardableResult
    private static func prefetchImageTargetsNow(
        _ targets: [TMDbImage],
        diskCacheExpiration: StorageExpiration,
        reporter: LibraryRefreshReporter
    ) async -> LibraryRefreshCompletion {
        let completion = await prefetchImagePhaseTargetsNow(
            targets,
            diskCacheExpiration: diskCacheExpiration,
            reporter: reporter
        )
        reporter.report(.refreshComplete(completion))
        return completion
    }

    @discardableResult
    private static func prefetchImagePhaseTargetsNow(
        _ targets: [TMDbImage],
        diskCacheExpiration: StorageExpiration,
        reporter: LibraryRefreshReporter
    ) async -> LibraryRefreshCompletion {
        let workItems = imagePrefetchWorkItems(from: targets)
        reporter.report(
            .imagePrefetchProgress(
                current: 0,
                total: workItems.count,
                messageResource: "Caching Images: 0 / \(workItems.count)"
            )
        )

        guard !workItems.isEmpty else {
            let completion = LibraryRefreshCompletion(
                state: .completed,
                messageResource: "Fetched: 0, failed: 0",
                successfulItemCount: 0,
                failedItemCount: 0
            )
            reporter.report(.imagePrefetchPhaseComplete(completion))
            return completion
        }

        let prefetcher = KingfisherVariantImagePrefetcher(diskCacheExpiration: diskCacheExpiration)
        let result = await prefetcher.prefetch(workItems) { progress in
            await MainActor.run {
                reporter.report(
                    .imagePrefetchProgress(
                        current: progress.current,
                        total: progress.total,
                        messageResource: "Caching Images: \(progress.current) / \(progress.total)"
                    )
                )
            }
        }
        let fetchedCount = result.successfulItemCount
        let failedCount = result.failedItemCount

        let state: LibraryRefreshCompletionState
        if failedCount == 0 {
            state = .completed
        } else if fetchedCount == 0 {
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
        reporter.report(.imagePrefetchPhaseComplete(completion))
        libraryStoreLogger.info(
            "Prefetched images: Fetched: \(fetchedCount), failed: \(failedCount)"
        )
        return completion
    }

    static func imagePrefetchTargets<C: Collection>(
        for entries: C,
        longTermGalleryPosterCachingEnabled: Bool = false
    ) -> [TMDbImage]
    where C.Element == AnimeEntry {
        entries.flatMap { entry in
            Self.imagePrefetchTargets(
                posterPath: entry.selectedPosterPath,
                backdropPath: entry.backdropPath,
                logoPath: entry.detail?.logoImagePath,
                longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
            )
        }
    }

    /// The library's images at the variants the library views display.
    ///
    /// The full-size poster is added only when long-term gallery poster caching is enabled.
    static func imagePrefetchTargets(
        posterPath: String?,
        backdropPath: String?,
        logoPath: String?,
        longTermGalleryPosterCachingEnabled: Bool = false
    ) -> [TMDbImage] {
        let posterVariants: [TMDbImageVariant] =
            longTermGalleryPosterCachingEnabled ? [.posterThumbnail, .posterFull] : [.posterThumbnail]
        return posterVariants.compactMap { TMDbImage(path: posterPath, variant: $0) }
            + [
                TMDbImage(path: backdropPath, variant: .backdrop),
                TMDbImage(path: logoPath, variant: .logo)
            ].compactMap(\.self)
    }

    /// Every Kingfisher cache entry the entry's images may occupy.
    static func relatedCacheKeys(for entry: AnimeEntry) -> Set<CachedImageKey> {
        // Either stored poster may have been displayed before the user changed their selection,
        // at any poster variant or, for sharing, at its original size.
        var images = Set([TMDbImage(path: entry.backdropPath, variant: .backdrop)].compactMap(\.self))
        var unprocessedURLs = Set<URL>()
        for posterPath in Set([entry.posterPath, entry.customPosterPath].compactMap(\.self)) {
            images.formUnion(
                [TMDbImageVariant.posterThumbnail, .posterFull].compactMap {
                    TMDbImage(path: posterPath, variant: $0)
                }
            )
            if let originalURL = TMDbImageURLResolver.current.originalURL(for: posterPath, role: .poster) {
                unprocessedURLs.insert(originalURL)
            }
        }

        if let detail = entry.detail {
            images.formUnion([detail.logoImage].compactMap(\.self))
            // Production company logos can be shared across entries, so retain their cached images.
            images.formUnion(detail.characters.compactMap(\.profileImage))
            images.formUnion(detail.staff.compactMap(\.profileImage))
            images.formUnion(detail.seasons.compactMap(\.posterImage))
            images.formUnion(detail.episodes.compactMap(\.stillImage))
        }

        unprocessedURLs.formUnion(images.map(\.url))
        return Set(images.map(CachedImageKey.init(image:)))
            .union(unprocessedURLs.map { CachedImageKey(url: $0, processorIdentifier: "") })
    }

    static func removeCachedImages(_ keys: Set<CachedImageKey>) {
        guard !keys.isEmpty else { return }

        Task.detached(priority: .utility) {
            let cache = KingfisherManager.shared.cache
            var removedCount = 0

            for key in keys {
                do {
                    try await cache.removeImage(
                        forKey: key.url.cacheKey,
                        processorIdentifier: key.processorIdentifier
                    )
                    removedCount += 1
                } catch {
                    libraryStoreLogger.warning("Failed to remove cached image for key \(key.url): \(error)")
                }
            }

            libraryStoreLogger.info("Removed \(removedCount) Kingfisher cache entries for deleted library content.")
        }
    }

    /// Groups targets by URL, so one download feeds every variant of it.
    nonisolated static func imagePrefetchWorkItems(from targets: [TMDbImage]) -> [ImagePrefetchWorkItem] {
        Dictionary(grouping: Array(Set(targets)), by: \.url)
            .map { url, targets in
                ImagePrefetchWorkItem(url: url, variants: Set(targets.map(\.variant)))
            }
    }

    struct ImagePrefetchWorkItem: Equatable {
        let url: URL
        let variants: Set<TMDbImageVariant>
    }

    /// One Kingfisher cache entry: a URL's bitmap under a processor, or its unprocessed data
    /// under the empty identifier.
    struct CachedImageKey: Hashable, Sendable {
        let url: URL
        let processorIdentifier: String

        init(url: URL, processorIdentifier: String) {
            self.url = url
            self.processorIdentifier = processorIdentifier
        }

        init(image: TMDbImage) {
            self.init(url: image.url, processorIdentifier: image.processor.identifier)
        }
    }
}

fileprivate struct KingfisherVariantImagePrefetcher: Sendable {
    /// Serial-friendly concurrent queue for the synchronous, CPU-heavy downsampling work, kept
    /// off Swift's cooperative executor so it doesn't starve other structured-concurrency tasks.
    private static let processingQueue = DispatchQueue(
        label: "com.anishelf.image-prefetch.processing",
        qos: .utility,
        attributes: .concurrent
    )

    static func process(
        _ data: Data,
        using processor: any ImageProcessor
    ) async -> KFCrossPlatformImage? {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                let options = KingfisherParsedOptionsInfo([.processor(processor)])
                let image = processor.process(item: .data(data), options: options)
                continuation.resume(returning: image)
            }
        }
    }

    static func serialize(
        _ image: KFCrossPlatformImage,
        originalData: Data
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            processingQueue.async {
                let data = DefaultCacheSerializer.default.data(with: image, original: originalData)
                continuation.resume(returning: data)
            }
        }
    }

    private let maxConcurrentDownloads: Int
    private let diskCacheExpiration: StorageExpiration
    private let downloader: ImageDownloader
    private let cache: ImageCache

    init(
        maxConcurrentDownloads: Int = 5,
        diskCacheExpiration: StorageExpiration,
        downloader: ImageDownloader = KingfisherManager.shared.downloader,
        cache: ImageCache = KingfisherManager.shared.cache
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.diskCacheExpiration = diskCacheExpiration
        self.downloader = downloader
        self.cache = cache
    }

    func prefetch(
        _ workItems: [LibraryImageCacheService.ImagePrefetchWorkItem],
        progressHandler: @Sendable (ImagePrefetchProgress) async -> Void
    ) async -> ImagePrefetchSummary {
        guard !workItems.isEmpty else {
            return ImagePrefetchSummary(successfulItemCount: 0, failedItemCount: 0)
        }

        let total = workItems.count
        var nextIndex = 0
        var completedCount = 0
        var successfulItemCount = 0
        var failedItemCount = 0
        let workerCount = min(maxConcurrentDownloads, total)

        await withTaskGroup(of: ImagePrefetchURLResult.self) { group in
            for _ in 0..<workerCount {
                let workItem = workItems[nextIndex]
                group.addTask {
                    await prefetch(workItem)
                }
                nextIndex += 1
            }

            while let result = await group.next() {
                completedCount += 1
                switch result {
                case .success:
                    successfulItemCount += 1
                case .failure(let url, let error):
                    failedItemCount += 1
                    libraryStoreLogger.warning("Failed to prefetch image variants for \(url): \(error)")
                }

                await progressHandler(
                    ImagePrefetchProgress(
                        current: completedCount,
                        total: total
                    )
                )

                if nextIndex < total {
                    let workItem = workItems[nextIndex]
                    group.addTask {
                        await prefetch(workItem)
                    }
                    nextIndex += 1
                }
            }
        }

        return ImagePrefetchSummary(
            successfulItemCount: successfulItemCount,
            failedItemCount: failedItemCount
        )
    }

    private func prefetch(
        _ workItem: LibraryImageCacheService.ImagePrefetchWorkItem
    ) async -> ImagePrefetchURLResult {
        do {
            let missingProcessors = await missingProcessors(for: workItem)
            guard !missingProcessors.isEmpty else {
                return .success(workItem.url)
            }

            let downloadOptions: KingfisherParsedOptionsInfo
            // Kingfisher cannot decode SVG data by default, so the download itself needs the
            // SVG processor to succeed.
            if workItem.url.isSVGImageURL, let downloadProcessor = missingProcessors.first?.1 {
                downloadOptions = KingfisherParsedOptionsInfo([.processor(downloadProcessor)])
            } else {
                downloadOptions = KingfisherParsedOptionsInfo(nil)
            }
            let loadingResult = try await downloader.downloadImage(
                with: workItem.url,
                options: downloadOptions
            )
            let originalData = loadingResult.originalData
            let cacheKey = workItem.url.cacheKey

            for (variant, processor) in missingProcessors {
                // Variant processing decodes the original synchronously. Run it on a
                // dedicated queue so it doesn't block Swift's cooperative executor, which
                // other concurrent prefetch work (and the rest of the app) shares.
                guard
                    let image = await Self.process(originalData, using: processor)
                else {
                    throw ImagePrefetchError.processingFailed(url: workItem.url, variant: variant)
                }
                guard
                    let data = await Self.serialize(image, originalData: originalData)
                else {
                    throw KingfisherError.cacheError(
                        reason: .cannotSerializeImage(
                            image: image,
                            original: originalData,
                            serializer: DefaultCacheSerializer.default
                        )
                    )
                }

                try await cache.storeToDisk(
                    data,
                    forKey: cacheKey,
                    processorIdentifier: processor.identifier,
                    expiration: diskCacheExpiration
                )
            }

            return .success(workItem.url)
        } catch {
            return .failure(workItem.url, error)
        }
    }

    private func missingProcessors(
        for workItem: LibraryImageCacheService.ImagePrefetchWorkItem
    ) async -> [(TMDbImageVariant, any ImageProcessor)] {
        let cacheKey = workItem.url.cacheKey
        let processors = workItem.variants.map { variant in
            (variant, variant.processor(for: workItem.url))
        }

        let missingProcessors = await withTaskGroup(
            of: Optional<(TMDbImageVariant, any ImageProcessor)>.self,
            returning: [(TMDbImageVariant, any ImageProcessor)].self
        ) { group in
            for (variant, processor) in processors {
                group.addTask {
                    // Kingfisher's synchronous cache probe can hit disk on memory misses. Use its
                    // async variant so disk metadata checks run on Kingfisher's I/O queue instead
                    // of blocking Swift's cooperative executor.
                    let cacheType = await cache.imageCachedTypeAsync(
                        forKey: cacheKey,
                        processorIdentifier: processor.identifier
                    )
                    return cacheType.cached ? nil : (variant, processor)
                }
            }

            var missingProcessors: [(TMDbImageVariant, any ImageProcessor)] = []
            for await processor in group {
                if let processor {
                    missingProcessors.append(processor)
                }
            }
            return missingProcessors
        }

        return missingProcessors.sorted { $0.0.maxPixelDimension < $1.0.maxPixelDimension }
    }

    struct ImagePrefetchProgress: Sendable {
        let current: Int
        let total: Int
    }

    struct ImagePrefetchSummary: Sendable {
        let successfulItemCount: Int
        let failedItemCount: Int
    }

    private enum ImagePrefetchURLResult {
        case success(URL)
        case failure(URL, Error)
    }

    private enum ImagePrefetchError: Error {
        case processingFailed(url: URL, variant: TMDbImageVariant)
    }
}
