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

        var fetchedInfos: [PersistentIdentifier: (EntryMetadata, AnimeEntryDetailDTO)] = [:]
        var failures: [LatestInfoFailure] = []
        let totalCount = library.count

        do {
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
                        let resolvedCurrent = fetchedInfos.count + failures.count + current
                        options.reporter.report(
                            .metadataProgress(
                                current: resolvedCurrent,
                                total: totalCount,
                                messageResource: "Fetching Info: \(resolvedCurrent) / \(totalCount)"
                            )
                        )
                    })
                for (id, info, detail) in chunkInfos.successes {
                    fetchedInfos[id] = (info, detail)
                }
                failures.append(contentsOf: chunkInfos.failures)
                libraryMetadataRefreshLogger.info(
                    "Finished metadata chunk \(chunkIndex + 1, privacy: .public) of \(chunks.count, privacy: .public): refreshed \(chunkInfos.successes.count, privacy: .public), failed \(chunkInfos.failures.count, privacy: .public)."
                )
            }

            libraryMetadataRefreshLogger.info(
                "Applying refreshed metadata for \(fetchedInfos.count, privacy: .public) entries."
            )
            options.reporter.report(
                .organizingLibrary(messageResource: "Organizing Library...")
            )
            var updates: [LibraryMetadataRefreshUpdate] = []
            var parentUpdates: [LibraryMetadataRefreshParentUpdate] = []
            for (id, fetchedInfo) in fetchedInfos {
                if let entry = library[id] {
                    let (info, detailDTO) = fetchedInfo
                    updates.append(
                        .init(
                            entryID: id,
                            info: info,
                            detail: detailDTO,
                            preservingCustomPoster: entry.usingCustomPoster
                        )
                    )
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
            try await applyMetadataRefresh(updates, parentUpdates)
            libraryMetadataRefreshLogger.info(
                "Saved library metadata refresh results for \(fetchedInfos.count, privacy: .public) refreshed entries."
            )
            let metadataCompletion = metadataCompletion(
                refreshedCount: fetchedInfos.count,
                failureCount: failures.count
            )
            libraryMetadataRefreshLogger.info(
                "Library metadata refresh completed with state \(self.completionStateLabel(metadataCompletion.state), privacy: .public): refreshed \(fetchedInfos.count, privacy: .public), failed \(failures.count, privacy: .public)."
            )
            options.reporter.report(.metadataPhaseComplete(metadataCompletion))

            if options.prefetchImages, !fetchedInfos.isEmpty {
                libraryMetadataRefreshLogger.info(
                    "Starting image prefetch for refreshed library content."
                )
                let imagePrefetchCompletion = await LibraryImageCacheService.prefetchImageTargetsForRefreshPhaseNow(
                    imagePrefetchTargetsForRefreshPhase(from: updates),
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
        } catch {
            libraryMetadataRefreshLogger.error("Error refreshing infos: \(error)")
            options.reporter.report(
                .refreshComplete(
                    .init(
                        state: .failed,
                        messageResource: LocalizedStringResource(stringLiteral: error.localizedDescription)
                    )
                )
            )
            return
        }
    }

    /// Returns the image targets that should be prefetched from refreshed metadata updates.
    ///
    /// The refresh writer applies updates on a background model context, so the main-context
    /// `AnimeEntry` instances passed into the refresh can still contain stale image URLs. Building
    /// the prefetch set from update payloads ensures posters, backdrops, and logos use the freshly
    /// fetched metadata.
    ///
    /// Parent-series artwork is intentionally excluded here. Refresh can discover or insert parent
    /// series transitively, and prefetching every parent image would let cache growth scale beyond
    /// the entries the user explicitly refreshed.
    private func imagePrefetchTargetsForRefreshPhase(
        from updates: [LibraryMetadataRefreshUpdate]
    ) -> [LibraryImageCacheService.ImagePrefetchTarget] {
        updates.flatMap { update in
            LibraryImageCacheService.imagePrefetchTargets(
                posterURL: update.info.posterURL,
                backdropURL: update.info.backdropURL,
                logoImageURL: update.detail.logoImageURL
            )
        }
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
