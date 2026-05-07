import DataProvider
import Foundation

extension LibraryStore {
    @discardableResult
    func createNewEntry(
        tmdbID id: Int,
        type: AnimeType
    ) async throws -> AnimeEntry? {
        guard library.map(\.tmdbID).contains(id) == false else {
            library.entryWithTMDbID(id)?.onDisplay = true
            libraryStoreLogger.warning(
                "Entry with id \(id) already exists. Setting `onDisplay` to `true` and returning..."
            )
            return nil
        }
        libraryStoreLogger.debug("Creating new entry with id: \(id), type: \(type)...")
        async let info = infoFetcher.fetchInfoFromTMDB(
            entryType: type,
            tmdbID: id,
            language: language)
        async let detail = infoFetcher.detailInfo(
            entryType: type,
            tmdbID: id,
            language: language
        )
        let entry = AnimeEntry(fromInfo: try await info)
        applyNewEntryDefaults(to: entry)
        entry.detail = try await detail
        if let parentSeriesID = entry.parentSeriesID {
            if let parentSeriesEntry = library.first(where: { $0.tmdbID == parentSeriesID }) {
                entry.parentSeriesEntry = parentSeriesEntry
            } else {
                let parentSeriesEntry =
                    try await AnimeEntry
                    .generateParentSeriesEntryForSeason(
                        parentSeriesID: parentSeriesID,
                        fetcher: infoFetcher,
                        infoLanguage: language)
                entry.parentSeriesEntry = parentSeriesEntry
            }
        }
        try repository.newEntry(entry)
        return entry
    }

    func newEntry(tmdbID id: Int, type: AnimeType) async -> Bool {
        do {
            if let entry = try await createNewEntry(tmdbID: id, type: type) {
                prefetchImagesForDefaultBehavior([entry])
            }
            return true
        } catch {
            libraryStoreLogger.error("Error creating new entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    func newEntryFromSearchResults<Sources: Collection<SearchResult>>(_ results: Sources) async
        -> Bool
    {
        do {
            var createdEntries: [AnimeEntry] = []
            for result in results {
                if let entry = try await createNewEntry(tmdbID: result.tmdbID, type: result.type) {
                    createdEntries.append(entry)
                }
            }
            prefetchImagesForDefaultBehavior(createdEntries)
            return true
        } catch {
            libraryStoreLogger.error("Error creating new entries from search results: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    func newEntryFromBasicInfo(_ info: BasicInfo) {
        do {
            let entry = AnimeEntry(fromInfo: info)
            applyNewEntryDefaults(to: entry)
            try repository.newEntry(entry)
            prefetchImagesForDefaultBehavior([entry])
        } catch {
            libraryStoreLogger.error("Error creating new entry from BasicInfo: \(error)")
        }
    }

    @discardableResult
    func deleteEntry(_ entry: AnimeEntry) -> Bool {
        let cachedImageURLs = imageCacheController.relatedImageURLs(for: entry)
        do {
            try repository.deleteEntry(entry)
            imageCacheController.removeCachedImages(for: cachedImageURLs)
            return true
        } catch {
            libraryStoreLogger.error("Failed to delete entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    func clearLibrary() {
        let cachedImageURLs = Set(library.flatMap { imageCacheController.relatedImageURLs(for: $0) })
        do {
            try repository.clearLibrary()
            imageCacheController.removeCachedImages(for: cachedImageURLs)
        } catch {
            libraryStoreLogger.error("Error clearing library: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    func prefetchAllImages() {
        imageCacheController.prefetchImages(for: library)
    }

    func prefetchImagesForDefaultBehavior<C: Collection>(_ entries: C)
    where C.Element == AnimeEntry {
        guard autoPrefetchImagesOnAddAndRestore else { return }
        imageCacheController.prefetchImages(for: entries)
    }
}
