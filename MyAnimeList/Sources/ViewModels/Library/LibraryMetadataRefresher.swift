import DataProvider
import Foundation
import SwiftData
import SwiftUI
import os

fileprivate let libraryMetadataRefreshLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibraryMetadataRefresh"
)

@MainActor
final class LibraryMetadataRefresher {
    private struct LatestInfoFailure {
        let tmdbID: Int
        let name: String
        let message: String
    }

    private enum LatestInfoFetchOutcome {
        case success(PersistentIdentifier, EntryMetadata, AnimeEntryDetailDTO)
        case failure(LatestInfoFailure)
    }

    private let repository: LibraryRepository
    private let applyMetadataRefresh:
        ([LibraryMetadataRefreshUpdate], [LibraryMetadataRefreshParentUpdate]) async throws -> Void

    init(
        repository: LibraryRepository,
        applyMetadataRefresh:
            @escaping (
                [LibraryMetadataRefreshUpdate],
                [LibraryMetadataRefreshParentUpdate]
            ) async throws -> Void
    ) {
        self.repository = repository
        self.applyMetadataRefresh = applyMetadataRefresh
    }

    func refreshInfos(
        for library: [AnimeEntry],
        fetcher: InfoFetcher,
        language: Language,
        options: LibraryRefreshOptions = .toastDefault
    ) async {
        libraryMetadataRefreshLogger.info(
            "Starting library metadata refresh for \(library.count, privacy: .public) entries in \(language.rawValue, privacy: .public) with image prefetch \(options.prefetchImages, privacy: .public)."
        )
        options.reporter.report(
            .metadataProgress(
                current: 0,
                total: library.count,
                messageResource: "Fetching Info: 0 / \(library.count)"
            )
        )

        var refreshedCount = 0
        var imagePrefetchTargets: [LibraryImageCacheService.ImagePrefetchTarget] = []
        var failures: [LatestInfoFailure] = []
        var applyFailureCount = 0
        let totalCount = library.count

        let chunks = chunkedEntries(library, chunkSize: 8)
        for (chunkIndex, chunk) in chunks.enumerated() {
            libraryMetadataRefreshLogger.debug(
                "Refreshing metadata chunk \(chunkIndex + 1, privacy: .public) of \(chunks.count, privacy: .public) containing \(chunk.count, privacy: .public) entries."
            )
            let chunkInfos = await latestInfoForEntries(
                entries: chunk,
                fetcher: fetcher,
                language: language,
                updateProgress: { current, _ in
                    let resolvedCurrent = refreshedCount + failures.count + current
                    options.reporter.report(
                        .metadataProgress(
                            current: resolvedCurrent,
                            total: totalCount,
                            messageResource: "Fetching Info: \(resolvedCurrent) / \(totalCount)"
                        )
                    )
                })
            failures.append(contentsOf: chunkInfos.failures)
            libraryMetadataRefreshLogger.info(
                "Finished metadata chunk \(chunkIndex + 1, privacy: .public) of \(chunks.count, privacy: .public): refreshed \(chunkInfos.successes.count, privacy: .public), failed \(chunkInfos.failures.count, privacy: .public)."
            )

            guard !chunkInfos.successes.isEmpty else { continue }

            libraryMetadataRefreshLogger.info(
                "Applying refreshed metadata chunk \(chunkIndex + 1, privacy: .public) of \(chunks.count, privacy: .public) for \(chunkInfos.successes.count, privacy: .public) entries."
            )

            var updates: [LibraryMetadataRefreshUpdate] = []
            var parentUpdates: [LibraryMetadataRefreshParentUpdate] = []
            var chunkImagePrefetchTargets: [LibraryImageCacheService.ImagePrefetchTarget] = []
            updates.reserveCapacity(chunkInfos.successes.count)
            for (id, info, detailDTO) in chunkInfos.successes {
                if let entry = library[id] {
                    let update = LibraryMetadataRefreshUpdate(
                        entryID: id,
                        info: info,
                        detail: detailDTO,
                        preservingCustomPoster: entry.usingCustomPoster,
                        customPosterPath: entry.usingCustomPoster ? entry.customPosterPath : nil
                    )
                    updates.append(update)
                    if options.prefetchImages {
                        chunkImagePrefetchTargets.append(
                            contentsOf: imagePrefetchTargetsForRefreshPhase(from: update)
                        )
                    }
                    if let parentUpdate = await parentSeriesUpdate(
                        for: entry,
                        refreshedInfo: info,
                        fetcher: fetcher,
                        language: language)
                    {
                        parentUpdates.append(parentUpdate)
                    }
                }
            }

            do {
                try await applyMetadataRefresh(updates, parentUpdates)
            } catch {
                applyFailureCount += updates.count
                libraryMetadataRefreshLogger.error(
                    "Failed applying metadata chunk \(chunkIndex + 1, privacy: .public) of \(chunks.count, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                break
            }

            refreshedCount += updates.count
            imagePrefetchTargets.append(contentsOf: chunkImagePrefetchTargets)
        }
        libraryMetadataRefreshLogger.info(
            "Saved library metadata refresh results for \(refreshedCount, privacy: .public) refreshed entries."
        )
        let metadataCompletion = metadataCompletion(
            refreshedCount: refreshedCount,
            failureCount: failures.count + applyFailureCount
        )
        libraryMetadataRefreshLogger.info(
            "Library metadata refresh completed with state \(self.completionStateLabel(metadataCompletion.state), privacy: .public): refreshed \(refreshedCount, privacy: .public), failed \(failures.count + applyFailureCount, privacy: .public)."
        )
        options.reporter.report(.metadataPhaseComplete(metadataCompletion))

        if options.prefetchImages, !imagePrefetchTargets.isEmpty {
            libraryMetadataRefreshLogger.info(
                "Starting image prefetch for refreshed library content."
            )
            let imagePrefetchCompletion = await LibraryImageCacheService.prefetchImageTargetsForRefreshPhaseNow(
                imagePrefetchTargets,
                reporter: options.reporter
            )
            libraryMetadataRefreshLogger.info(
                "Library info refresh completed with image prefetch state \(self.completionStateLabel(imagePrefetchCompletion.state), privacy: .public)."
            )
            options.reporter.report(
                .refreshComplete(
                    refreshCompletion(
                        metadataCompletion: metadataCompletion,
                        imagePrefetchCompletion: imagePrefetchCompletion
                    )
                )
            )
        } else {
            if options.prefetchImages {
                libraryMetadataRefreshLogger.info(
                    "Skipped image prefetch because no entries refreshed successfully."
                )
            } else {
                libraryMetadataRefreshLogger.info(
                    "Skipped image prefetch because it was disabled for this refresh."
                )
            }
            options.reporter.report(.refreshComplete(metadataCompletion))
        }
    }

    private func imagePrefetchTargetsForRefreshPhase(
        from update: LibraryMetadataRefreshUpdate
    ) -> [LibraryImageCacheService.ImagePrefetchTarget] {
        // Refresh prefetch should follow the poster the UI will show after the write:
        // custom poster when preserved, otherwise the refreshed TMDb poster.
        let posterURL =
            update.preservingCustomPoster
            ? TMDbImageURLResolver.current.url(for: update.customPosterPath, role: .poster)
            : update.info.posterURL
        return LibraryImageCacheService.imagePrefetchTargets(
            posterURL: posterURL,
            backdropURL: update.info.backdropURL,
            logoImageURL: update.info.logoURL
        )
    }

    private func metadataCompletion(
        refreshedCount: Int,
        failureCount: Int
    ) -> LibraryRefreshCompletion {
        if failureCount == 0 {
            return .init(
                state: .completed,
                messageResource: "Refreshed infos for \(refreshedCount) entries.",
                successfulItemCount: refreshedCount,
                failedItemCount: failureCount
            )
        } else if refreshedCount == 0 {
            return .init(
                state: .failed,
                messageResource: "Failed to refresh \(failureCount) entries.",
                successfulItemCount: refreshedCount,
                failedItemCount: failureCount
            )
        } else {
            return .init(
                state: .partialComplete,
                messageResource: "Refreshed \(refreshedCount) entries, failed \(failureCount).",
                successfulItemCount: refreshedCount,
                failedItemCount: failureCount
            )
        }
    }

    private func refreshCompletion(
        metadataCompletion: LibraryRefreshCompletion,
        imagePrefetchCompletion: LibraryRefreshCompletion
    ) -> LibraryRefreshCompletion {
        let refreshedCount = metadataCompletion.successfulItemCount ?? 0
        let metadataFailureCount = metadataCompletion.failedItemCount ?? 0
        let fetchedImageCount = imagePrefetchCompletion.successfulItemCount ?? 0
        let imageFailureCount = imagePrefetchCompletion.failedItemCount ?? 0

        let messageResource: LocalizedStringResource
        switch (metadataFailureCount, imageFailureCount) {
        case (0, 0):
            messageResource = "Refreshed \(refreshedCount) entries and fetched \(fetchedImageCount) images."
        case (0, _):
            messageResource =
                "Refreshed \(refreshedCount) entries. Fetched \(fetchedImageCount) images, failed \(imageFailureCount)."
        case (_, 0):
            messageResource =
                "Refreshed \(refreshedCount) entries, failed \(metadataFailureCount). Fetched \(fetchedImageCount) images."
        default:
            messageResource =
                "Refreshed \(refreshedCount) entries, failed \(metadataFailureCount). Fetched \(fetchedImageCount) images, failed \(imageFailureCount)."
        }

        return .init(
            state: refreshCompletionState(
                metadataState: metadataCompletion.state,
                imagePrefetchState: imagePrefetchCompletion.state
            ),
            messageResource: messageResource
        )
    }

    private func refreshCompletionState(
        metadataState: LibraryRefreshCompletionState,
        imagePrefetchState: LibraryRefreshCompletionState
    ) -> LibraryRefreshCompletionState {
        switch (metadataState, imagePrefetchState) {
        case (.completed, .completed):
            .completed
        case (.failed, _):
            .failed
        case (_, .failed), (.partialComplete, _), (_, .partialComplete):
            .partialComplete
        }
    }

    private func completionStateLabel(_ state: LibraryRefreshCompletionState) -> String {
        switch state {
        case .completed:
            "completed"
        case .failed:
            "failed"
        case .partialComplete:
            "partialComplete"
        }
    }

    private func chunkedEntries(_ entries: [AnimeEntry], chunkSize: Int) -> [ArraySlice<AnimeEntry>] {
        var chunks: [ArraySlice<AnimeEntry>] = []
        var currentIndex = entries.startIndex

        while currentIndex < entries.endIndex {
            let endIndex =
                entries.index(
                    currentIndex,
                    offsetBy: chunkSize,
                    limitedBy: entries.endIndex) ?? entries.endIndex
            chunks.append(entries[currentIndex..<endIndex])
            currentIndex = endIndex
        }

        return chunks
    }

    private func latestInfoForEntries<C: Collection<AnimeEntry>>(
        entries: C,
        fetcher: InfoFetcher,
        language: Language,
        updateProgress: @escaping (Int, Int) -> Void
    ) async -> (
        successes: [(PersistentIdentifier, EntryMetadata, AnimeEntryDetailDTO)],
        failures: [LatestInfoFailure]
    ) {
        await withTaskGroup(
            of: LatestInfoFetchOutcome.self
        ) { group in
            var fetchedInfos: [(PersistentIdentifier, EntryMetadata, AnimeEntryDetailDTO)] = []
            var failures: [LatestInfoFailure] = []

            for entry in entries {
                let entryID = entry.id
                let tmdbID = entry.tmdbID
                let name = entry.name
                let type = entry.type
                group.addTask {
                    do {
                        let latestInfo = try await self.fetchLatestInfo(
                            entryID: entryID,
                            tmdbID: tmdbID,
                            entryType: type,
                            fetcher: fetcher,
                            language: language)
                        return .success(latestInfo.0, latestInfo.1, latestInfo.2)
                    } catch {
                        return .failure(
                            .init(
                                tmdbID: tmdbID,
                                name: name,
                                message: error.localizedDescription))
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let id, let info, let detail):
                    fetchedInfos.append((id, info, detail))
                case .failure(let failure):
                    failures.append(failure)
                    libraryMetadataRefreshLogger.error(
                        "Failed to refresh entry \(failure.tmdbID, privacy: .public), name: \(failure.name, privacy: .public): \(failure.message)"
                    )
                }
                updateProgress(fetchedInfos.count + failures.count, entries.count)
            }

            return (fetchedInfos, failures)
        }
    }

    private func fetchLatestInfo(
        entryID: PersistentIdentifier,
        tmdbID: Int,
        entryType: AnimeType,
        fetcher: InfoFetcher,
        language: Language
    ) async throws -> (PersistentIdentifier, EntryMetadata, AnimeEntryDetailDTO) {
        let latestInfo = try await fetcher.latestInfo(
            entryType: entryType,
            tmdbID: tmdbID,
            language: language)
        return (entryID, latestInfo.0, latestInfo.1)
    }

    private func parentSeriesUpdate(
        for entry: AnimeEntry,
        refreshedInfo: EntryMetadata,
        fetcher: InfoFetcher,
        language: Language
    ) async -> LibraryMetadataRefreshParentUpdate? {
        guard let parentSeriesID = refreshedInfo.type.parentSeriesID else { return nil }

        if entry.parentSeriesEntry?.tmdbID == parentSeriesID {
            return nil
        }

        if repository.existingEntry(tmdbID: parentSeriesID) != nil {
            return .init(
                childEntryID: entry.id,
                parentSeriesID: parentSeriesID,
                parentInfo: nil,
                parentDetail: nil
            )
        }

        do {
            let parentLatestInfo = try await fetcher.latestInfo(
                entryType: .series,
                tmdbID: parentSeriesID,
                language: language
            )
            return .init(
                childEntryID: entry.id,
                parentSeriesID: parentSeriesID,
                parentInfo: parentLatestInfo.0,
                parentDetail: parentLatestInfo.1
            )
        } catch {
            libraryMetadataRefreshLogger.warning(
                "Failed to resolve parent series \(parentSeriesID, privacy: .public) for entry \(entry.tmdbID, privacy: .public): \(error.localizedDescription)"
            )
            return nil
        }
    }
}
