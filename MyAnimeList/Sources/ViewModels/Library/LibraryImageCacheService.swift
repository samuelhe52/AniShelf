import DataProvider
import Foundation
import Kingfisher
import SwiftUI

@MainActor
enum LibraryImageCacheService {
    private static let posterPrefetchTargetWidths: [CGFloat] = [240, 360, 1_000]
    private static let backdropPrefetchTargetSize = CGSize(width: 1_200, height: 675)
    private static let logoPrefetchTargetSize = CGSize(width: 500, height: 500)
    private static let posterHeightRatio: CGFloat = 1.5
    private static let prefetchDiskCacheExpiration: StorageExpiration = .longTerm

    static func prefetchImages<C: Collection>(
        for entries: C,
        reporter: LibraryRefreshReporter = .toast
    )
    where C.Element == AnimeEntry {
        let targets = imagePrefetchTargets(for: entries)
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
        reporter: LibraryRefreshReporter = .toast
    ) async -> LibraryRefreshCompletion where C.Element == AnimeEntry {
        let targets = imagePrefetchTargets(for: entries)
        return await prefetchImageTargetsNow(
            targets,
            diskCacheExpiration: prefetchDiskCacheExpiration,
            reporter: reporter
        )
    }

    @discardableResult
    static func prefetchImagesForRefreshPhaseNow<C: Collection>(
        for entries: C,
        reporter: LibraryRefreshReporter
    ) async -> LibraryRefreshCompletion where C.Element == AnimeEntry {
        let targets = imagePrefetchTargets(for: entries)
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

    static func imagePrefetchTargets<C: Collection>(for entries: C) -> [ImagePrefetchTarget]
    where C.Element == AnimeEntry {
        entries.flatMap { entry in
            Self.imagePrefetchTargets(
                posterURL: entry.posterURL,
                backdropURL: entry.backdropURL,
                logoImageURL: entry.detail?.logoImageURL
            )
        }
    }

    static func imagePrefetchTargets(
        posterURL: URL?,
        backdropURL: URL?,
        logoImageURL: URL?
    ) -> [ImagePrefetchTarget] {
        var targets: [ImagePrefetchTarget] = []

        if let posterURL {
            targets += posterPrefetchTargetWidths.map { targetWidth in
                ImagePrefetchTarget(url: posterURL, targetSize: posterTargetSize(width: targetWidth))
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
        let sizes = [
            posterTargetSize(width: 240),
            posterTargetSize(width: 300),
            posterTargetSize(width: 360),
            posterTargetSize(width: 500),
            posterTargetSize(width: 1_000),
            backdropPrefetchTargetSize,
            logoPrefetchTargetSize
        ]
        let downsampledIdentifiers = sizes.map { size in
            DownsamplingImageProcessor(size: size).identifier
        }
        return [""] + downsampledIdentifiers
    }()

    nonisolated static func imagePrefetchWorkItems(from targets: [ImagePrefetchTarget]) -> [ImagePrefetchWorkItem] {
        Dictionary(grouping: Array(Set(targets)), by: \.url)
            .map { url, targets in
                ImagePrefetchWorkItem(
                    url: url,
                    targetSizes: Set(targets.map(\.targetSize))
                )
            }
            .sorted {
                $0.url.absoluteString < $1.url.absoluteString
            }
    }

    private static func posterTargetSize(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width * posterHeightRatio)
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
            let missingProcessors = missingProcessors(for: workItem)
            guard !missingProcessors.isEmpty else {
                return .success(workItem.url)
            }

            let downloadOptions = KingfisherParsedOptionsInfo(nil)
            let loadingResult = try await downloader.downloadImage(
                with: workItem.url,
                options: downloadOptions
            )

            for (targetSize, processor) in missingProcessors {
                let options = KingfisherParsedOptionsInfo([
                    .processor(processor),
                    .diskCacheExpiration(diskCacheExpiration)
                ])
                guard
                    let image = processor.process(
                        item: .data(loadingResult.originalData),
                        options: options
                    )
                else {
                    throw ImagePrefetchError.processingFailed(url: workItem.url, targetSize: targetSize)
                }

                try await cache.store(
                    image,
                    original: loadingResult.originalData,
                    forKey: workItem.url.cacheKey,
                    options: options,
                    toDisk: true
                )
            }

            return .success(workItem.url)
        } catch {
            return .failure(workItem.url, error)
        }
    }

    private func missingProcessors(
        for workItem: LibraryImageCacheService.ImagePrefetchWorkItem
    ) -> [(CGSize, DownsamplingImageProcessor)] {
        workItem.targetSizes
            .map { targetSize in
                (targetSize, DownsamplingImageProcessor(size: targetSize))
            }
            .filter { _, processor in
                !cache
                    .imageCachedType(
                        forKey: workItem.url.cacheKey,
                        processorIdentifier: processor.identifier
                    )
                    .cached
            }
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
