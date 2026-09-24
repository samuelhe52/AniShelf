import DataProvider
import Foundation
import Kingfisher
import SwiftUI

@MainActor
enum LibraryImageCacheService {
    /// Poster display contexts warmed by default.
    ///
    /// Gallery is added only when long-term gallery poster caching is enabled.
    ///
    /// Each context maps to a distinct sized TMDb URL, which Kingfisher keys on directly. Prefetch
    /// must build targets from these same sized URLs, or the warmed entries never match the keys the
    /// list/grid/gallery views look up.
    private static let standardPosterPrefetchDisplayTypes: [TMDbPosterDisplayType] = [.list, .grid]
    private static let backdropPrefetchTargetSize = CGSize(width: 1_200, height: 675)
    private static let logoPrefetchTargetSize = CGSize(width: 500, height: 500)
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
        _ targets: [ImagePrefetchTarget],
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
        _ targets: [ImagePrefetchTarget],
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
        _ targets: [ImagePrefetchTarget],
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
    ) -> [ImagePrefetchTarget]
    where C.Element == AnimeEntry {
        entries.flatMap { entry in
            Self.imagePrefetchTargets(
                posterPath: entry.selectedPosterPath,
                backdropURL: entry.backdropURL,
                logoImageURL: entry.detail?.logoImageURL,
                longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
            )
        }
    }

    static func imagePrefetchTargets(
        posterPath: String?,
        backdropURL: URL?,
        logoImageURL: URL?,
        longTermGalleryPosterCachingEnabled: Bool = false
    ) -> [ImagePrefetchTarget] {
        var targets: [ImagePrefetchTarget] = []

        if let posterPath {
            targets += posterPrefetchDisplayTypes(
                longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
            ).compactMap { displayType in
                guard
                    let url = TMDbImageURLResolver.current.url(
                        for: posterPath,
                        role: .poster,
                        idealWidth: displayType.idealWidth
                    )
                else { return nil }
                return ImagePrefetchTarget(
                    url: url,
                    targetSize: PosterImageSize.targetSize(width: CGFloat(displayType.idealWidth))
                )
            }
        }

        if let backdropURL {
            targets.append(ImagePrefetchTarget(url: backdropURL, targetSize: backdropPrefetchTargetSize))
        }

        if let logoImageURL {
            targets.append(ImagePrefetchTarget(url: logoImageURL, targetSize: logoPrefetchTargetSize))
        }

        return targets
    }

    private static func posterPrefetchDisplayTypes(
        longTermGalleryPosterCachingEnabled: Bool
    ) -> [TMDbPosterDisplayType] {
        if longTermGalleryPosterCachingEnabled {
            return standardPosterPrefetchDisplayTypes + [.gallery]
        }
        return standardPosterPrefetchDisplayTypes
    }

    static func relatedImageURLs(for entry: AnimeEntry) -> Set<URL> {
        // Either stored poster may have been displayed before the user changed their selection.
        // Include each original URL and every sized list/grid/gallery rendition.
        var urls = Set([entry.backdropURL].compactMap(\.self))
        for posterPath in Set([entry.posterPath, entry.customPosterPath].compactMap(\.self)) {
            if let originalURL = TMDbImageURLResolver.current.url(for: posterPath, role: .poster) {
                urls.insert(originalURL)
            }
            urls.formUnion(
                TMDbPosterDisplayType.allCases.compactMap { displayType in
                    TMDbImageURLResolver.current.url(
                        for: posterPath,
                        role: .poster,
                        idealWidth: displayType.idealWidth
                    )
                }
            )
        }

        if let detail = entry.detail {
            urls.formUnion([detail.heroImageURL, detail.logoImageURL].compactMap(\.self))
            // Production company logos can be shared across entries, so retain their cached images.
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
        let sizes = [
            PosterImageSize.targetSize(width: 240),
            PosterImageSize.targetSize(width: 300),
            PosterImageSize.targetSize(width: 360),
            PosterImageSize.targetSize(width: 500),
            PosterImageSize.targetSize(width: 1_000),
            backdropPrefetchTargetSize,
            logoPrefetchTargetSize
        ]
        let downsampledIdentifiers = sizes.map { size in
            DownsamplingImageProcessor(size: size).identifier
        }
        let svgIdentifiers = sizes.flatMap { size in
            [1, 2, 3].map { scale in
                SVGImageProcessor.identifier(targetSize: size, scale: CGFloat(scale))
            }
        }
        return [""] + downsampledIdentifiers + svgIdentifiers
    }()

    nonisolated static func imagePrefetchWorkItems(from targets: [ImagePrefetchTarget]) -> [ImagePrefetchWorkItem] {
        Dictionary(grouping: Array(Set(targets)), by: \.url)
            .map { url, targets in
                ImagePrefetchWorkItem(
                    url: url,
                    targetSizes: Set(targets.map(\.targetSize))
                )
            }
    }

    struct ImagePrefetchTarget: Hashable {
        let url: URL
        let targetSize: CGSize
    }

    struct ImagePrefetchWorkItem: Equatable {
        let url: URL
        let targetSizes: Set<CGSize>
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
            if let downloadProcessor = LibraryImageProcessorFactory.downloadProcessor(
                for: workItem.url,
                targetSize: missingProcessors.first?.0
            ) {
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

            for (targetSize, processor) in missingProcessors {
                // Variant processing decodes the original synchronously. Run it on a
                // dedicated queue so it doesn't block Swift's cooperative executor, which
                // other concurrent prefetch work (and the rest of the app) shares.
                guard
                    let image = await Self.process(originalData, using: processor)
                else {
                    throw ImagePrefetchError.processingFailed(url: workItem.url, targetSize: targetSize)
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
    ) async -> [(CGSize, any ImageProcessor)] {
        let cacheKey = workItem.url.cacheKey
        let processors = workItem.targetSizes
            .compactMap { targetSize in
                LibraryImageProcessorFactory.processor(
                    for: workItem.url,
                    targetSize: targetSize
                ).map { processor in
                    (targetSize, processor)
                }
            }

        let missingProcessors = await withTaskGroup(
            of: Optional<(CGSize, any ImageProcessor)>.self,
            returning: [(CGSize, any ImageProcessor)].self
        ) { group in
            for (targetSize, processor) in processors {
                group.addTask {
                    // Kingfisher's synchronous cache probe can hit disk on memory misses. Use its
                    // async variant so disk metadata checks run on Kingfisher's I/O queue instead
                    // of blocking Swift's cooperative executor.
                    let cacheType = await cache.imageCachedTypeAsync(
                        forKey: cacheKey,
                        processorIdentifier: processor.identifier
                    )
                    return cacheType.cached ? nil : (targetSize, processor)
                }
            }

            var missingProcessors: [(CGSize, any ImageProcessor)] = []
            for await processor in group {
                if let processor {
                    missingProcessors.append(processor)
                }
            }
            return missingProcessors
        }

        return
            missingProcessors
            .sorted {
                if $0.0.width == $1.0.width {
                    return $0.0.height < $1.0.height
                }
                return $0.0.width < $1.0.width
            }
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
        case processingFailed(url: URL, targetSize: CGSize)
    }
}
