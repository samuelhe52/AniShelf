import DataProvider
import Foundation
import SwiftUI

@MainActor
final class LibraryMetadataRefreshController {
    private struct LatestInfoFailure {
        let tmdbID: Int
        let name: String
        let message: String
    }

    private enum LatestInfoFetchOutcome {
        case success(Int, BasicInfo, AnimeEntryDetail)
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
        prefetchAllImages: @escaping ([AnimeEntry]) -> Void
    ) {
        Task {
            ToastCenter.global.progressState =
                .progress(
                    current: 0,
                    total: library.count,
                    messageResource: "Fetching Info: 0 / \(library.count)")

            var fetchedInfos: [Int: (BasicInfo, AnimeEntryDetail)] = [:]
            var failures: [LatestInfoFailure] = []
            let totalCount = library.count

            do {
                for chunk in chunkedEntries(library, chunkSize: 8) {
                    let chunkInfos = await latestInfoForEntries(
                        entries: chunk,
                        fetcher: fetcher,
                        language: language,
                        updateProgress: { current, _ in
                            let messageResource: LocalizedStringResource =
                                "Fetching Info: \(fetchedInfos.count + failures.count + current) / \(totalCount)"
                            ToastCenter.global.progressState =
                                .progress(
                                    current: fetchedInfos.count + failures.count + current,
                                    total: totalCount,
                                    messageResource: messageResource)
                        })
                    for (id, info, detail) in chunkInfos.successes {
                        fetchedInfos[id] = (info, detail)
                    }
                    failures.append(contentsOf: chunkInfos.failures)
                }
                ToastCenter.global.progressState = nil

                ToastCenter.global.loadingMessage = .message("Organizing Library...")
                for (id, payload) in fetchedInfos {
                    if let entry = library.entryWithTMDbID(id) {
                        entry.replaceMetadata(
                            from: payload.0,
                            preservingCustomPoster: entry.usingCustomPoster)
                        entry.detail = payload.1
                        await resolveParentSeriesEntry(for: entry, fetcher: fetcher, language: language)
                    }
                }
                try repository.save()
                ToastCenter.global.loadingMessage = nil
                if failures.isEmpty {
                    ToastCenter.global.completionState = .completed(
                        "Refreshed infos for \(fetchedInfos.count) entries.")
                } else if fetchedInfos.isEmpty {
                    ToastCenter.global.completionState = .failed(
                        "Failed to refresh \(failures.count) entries.")
                } else {
                    ToastCenter.global.completionState = .partialComplete(
                        "Refreshed \(fetchedInfos.count) entries, failed \(failures.count).")
                }
            } catch {
                libraryStoreLogger.error("Error refreshing infos: \(error)")
                ToastCenter.global.completionState = .failed(message: error.localizedDescription)
                return
            }
            if !fetchedInfos.isEmpty {
                prefetchAllImages(library)
            }
        }
    }

    func chunkedEntries(_ entries: [AnimeEntry], chunkSize: Int) -> [ArraySlice<AnimeEntry>] {
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
        successes: [(Int, BasicInfo, AnimeEntryDetail)],
        failures: [LatestInfoFailure]
    ) {
        await withTaskGroup(
            of: LatestInfoFetchOutcome.self
        ) { group in
            var fetchedInfos: [(Int, BasicInfo, AnimeEntryDetail)] = []
            var failures: [LatestInfoFailure] = []

            for entry in entries {
                let tmdbID = entry.tmdbID
                let name = entry.name
                let type = entry.type
                let originalPosterURL = entry.posterURL
                let usingCustomPoster = entry.usingCustomPoster
                group.addTask {
                    do {
                        let payload = try await self.fetchLatestInfo(
                            tmdbID: tmdbID,
                            entryType: type,
                            originalPosterURL: originalPosterURL,
                            usingCustomPoster: usingCustomPoster,
                            fetcher: fetcher,
                            language: language)
                        return .success(payload.0, payload.1, payload.2)
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

    func fetchLatestInfo(
        tmdbID: Int,
        entryType: AnimeType,
        originalPosterURL: URL?,
        usingCustomPoster: Bool,
        fetcher: InfoFetcher,
        language: Language
    ) async throws -> (Int, BasicInfo, AnimeEntryDetail) {
        let payload = try await fetcher.latestInfo(
            entryType: entryType,
            tmdbID: tmdbID,
            language: language)
        var resolvedInfo = payload.0
        if usingCustomPoster {
            resolvedInfo.posterURL = originalPosterURL
        }
        return (tmdbID, resolvedInfo, payload.1)
    }

    func resolveParentSeriesEntry(for entry: AnimeEntry, fetcher: InfoFetcher, language: Language) async {
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

extension LibraryStore {
    func chunkedLibraryEntries(chunkSize: Int) -> [ArraySlice<AnimeEntry>] {
        metadataRefreshController.chunkedEntries(library, chunkSize: chunkSize)
    }

    func refreshInfos() {
        metadataRefreshController.refreshInfos(
            for: library,
            fetcher: infoFetcher,
            language: language,
            prefetchAllImages: { [imageCacheController] entries in
                imageCacheController.prefetchImages(for: entries)
            }
        )
    }

    func fetchLatestInfo(
        tmdbID: Int,
        entryType: AnimeType,
        originalPosterURL: URL?,
        usingCustomPoster: Bool
    ) async throws -> (Int, BasicInfo, AnimeEntryDetail) {
        try await metadataRefreshController.fetchLatestInfo(
            tmdbID: tmdbID,
            entryType: entryType,
            originalPosterURL: originalPosterURL,
            usingCustomPoster: usingCustomPoster,
            fetcher: infoFetcher,
            language: language
        )
    }

    func resolveParentSeriesEntry(for entry: AnimeEntry) async {
        await metadataRefreshController.resolveParentSeriesEntry(
            for: entry,
            fetcher: infoFetcher,
            language: language
        )
    }
}
