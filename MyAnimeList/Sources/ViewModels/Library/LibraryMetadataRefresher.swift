import DataProvider
import Foundation
import SwiftUI

@MainActor
final class LibraryMetadataRefresher {
    private struct LatestInfoFailure {
        let tmdbID: Int
        let name: String
        let message: String
    }

    private enum LatestInfoFetchOutcome {
        case success(Int, BasicInfo, AnimeEntryDetailDTO)
        case failure(LatestInfoFailure)
    }

    private let repository: LibraryRepository

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func refreshInfos(
        for library: [AnimeEntry],
        fetcher: InfoFetcher,
        language: Language,
        options: LibraryRefreshOptions = .toastDefault
    ) async {
        options.reporter.report(
            .metadataProgress(
                current: 0,
                total: library.count,
                messageResource: "Fetching Info: 0 / \(library.count)"
            )
        )

        var fetchedInfos: [Int: (BasicInfo, AnimeEntryDetailDTO)] = [:]
        var failures: [LatestInfoFailure] = []
        let totalCount = library.count

        do {
            for chunk in chunkedEntries(library, chunkSize: 8) {
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
            }

            options.reporter.report(
                .organizingLibrary(messageResource: "Organizing Library...")
            )
            for (id, fetchedInfo) in fetchedInfos {
                if let entry = library.entryWithTMDbID(id) {
                    let (info, detailDTO) = fetchedInfo
                    entry.replaceMetadata(
                        from: info,
                        preservingCustomPoster: entry.usingCustomPoster)
                    entry.replaceDetail(from: detailDTO)
                    await resolveParentSeriesEntry(for: entry, fetcher: fetcher, language: language)
                }
            }
            try repository.save()
            let metadataCompletion = metadataCompletion(
                refreshedCount: fetchedInfos.count,
                failureCount: failures.count
            )
            options.reporter.report(.metadataPhaseComplete(metadataCompletion))

            if options.prefetchImages, !fetchedInfos.isEmpty {
                let imagePrefetchCompletion = await LibraryImageCacheService.prefetchImagesNow(
                    for: library,
                    reporter: options.reporter
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
                options.reporter.report(.refreshComplete(metadataCompletion))
            }
        } catch {
            libraryStoreLogger.error("Error refreshing infos: \(error)")
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
        successes: [(Int, BasicInfo, AnimeEntryDetailDTO)],
        failures: [LatestInfoFailure]
    ) {
        await withTaskGroup(
            of: LatestInfoFetchOutcome.self
        ) { group in
            var fetchedInfos: [(Int, BasicInfo, AnimeEntryDetailDTO)] = []
            var failures: [LatestInfoFailure] = []

            for entry in entries {
                let tmdbID = entry.tmdbID
                let name = entry.name
                let type = entry.type
                let originalPosterURL = entry.posterURL
                let usingCustomPoster = entry.usingCustomPoster
                group.addTask {
                    do {
                        let latestInfo = try await self.fetchLatestInfo(
                            tmdbID: tmdbID,
                            entryType: type,
                            originalPosterURL: originalPosterURL,
                            usingCustomPoster: usingCustomPoster,
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
                    libraryStoreLogger.error(
                        "Failed to refresh entry \(failure.tmdbID, privacy: .public), name: \(failure.name, privacy: .public): \(failure.message)"
                    )
                }
                updateProgress(fetchedInfos.count + failures.count, entries.count)
            }

            return (fetchedInfos, failures)
        }
    }

    private func fetchLatestInfo(
        tmdbID: Int,
        entryType: AnimeType,
        originalPosterURL: URL?,
        usingCustomPoster: Bool,
        fetcher: InfoFetcher,
        language: Language
    ) async throws -> (Int, BasicInfo, AnimeEntryDetailDTO) {
        let latestInfo = try await fetcher.latestInfo(
            entryType: entryType,
            tmdbID: tmdbID,
            language: language)
        var resolvedInfo = latestInfo.0
        if usingCustomPoster {
            resolvedInfo.posterURL = originalPosterURL
        }
        return (tmdbID, resolvedInfo, latestInfo.1)
    }

    private func resolveParentSeriesEntry(
        for entry: AnimeEntry,
        fetcher: InfoFetcher,
        language: Language
    ) async {
        guard let parentSeriesID = entry.parentSeriesID else { return }

        if entry.parentSeriesEntry?.tmdbID == parentSeriesID {
            return
        }

        if let parentSeriesEntry = repository.existingEntry(tmdbID: parentSeriesID) {
            entry.parentSeriesEntry = parentSeriesEntry
            return
        }

        do {
            let parentSeriesEntry =
                try await AnimeEntry
                .generateParentSeriesEntryForSeason(
                    parentSeriesID: parentSeriesID,
                    fetcher: fetcher,
                    infoLanguage: language)
            repository.insert(parentSeriesEntry)
            entry.parentSeriesEntry = parentSeriesEntry
        } catch {
            libraryStoreLogger.warning(
                "Failed to resolve parent series \(parentSeriesID, privacy: .public) for entry \(entry.tmdbID, privacy: .public): \(error.localizedDescription)"
            )
        }
    }
}
