import DataProvider
import Foundation

fileprivate enum DeletionScrollTarget: Equatable {
    case preserveCurrent
    case clear
    case entry(Int)
}

extension LibraryStore {
    @discardableResult
    func createNewEntry(
        tmdbID id: Int,
        type: AnimeType
    ) async throws -> AnimeEntry? {
        if let existingEntry = repository.existingEntry(tmdbID: id) {
            if !existingEntry.onDisplay {
                try await hydrateExistingEntry(existingEntry, type: type)
                return existingEntry
            }

            existingEntry.onDisplay = true
            try repository.save()
            libraryStoreLogger.warning(
                "Entry with id \(id) already exists in the store. Setting `onDisplay` to `true` and returning..."
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
        entry.replaceDetail(from: try await detail)
        if let parentSeriesID = entry.parentSeriesID {
            if let parentSeriesEntry = repository.existingEntry(tmdbID: parentSeriesID) {
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

    func hydrateExistingEntry(_ entry: AnimeEntry, type: AnimeType) async throws {
        let tmdbID = entry.tmdbID
        async let info = infoFetcher.fetchInfoFromTMDB(
            entryType: type,
            tmdbID: tmdbID,
            language: language
        )
        async let detail = infoFetcher.detailInfo(
            entryType: type,
            tmdbID: tmdbID,
            language: language
        )
        let resolvedInfo = try await info
        let resolvedDetail = try await detail
        try hydrateExistingEntry(
            entry,
            from: resolvedInfo,
            detail: resolvedDetail
        )
    }

    func hydrateExistingEntry(
        _ entry: AnimeEntry,
        from info: BasicInfo,
        detail: AnimeEntryDetailDTO
    ) throws {
        entry.replaceMetadata(from: info, preservingCustomPoster: entry.usingCustomPoster)
        entry.replaceDetail(from: detail)
        if entry.userInfo.isEmpty {
            applyNewEntryDefaults(to: entry)
        }
        entry.onDisplay = true
        try repository.save()
        libraryStoreLogger.info(
            "Hydrated hidden entry \(entry.tmdbID, privacy: .public) and set `onDisplay` to `true`."
        )
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
        let cachedImageURLs = LibraryImageCacheService.relatedImageURLs(for: entry)
        do {
            try repository.deleteEntry(entry)
            LibraryImageCacheService.removeCachedImages(for: cachedImageURLs)
            return true
        } catch {
            libraryStoreLogger.error("Failed to delete entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteEntry(_ entry: AnimeEntry, updateScrolledID: (Int?) -> Void) -> Bool {
        let scrollTarget = deletionScrollTarget(for: entry)

        guard deleteEntry(entry) else { return false }

        switch scrollTarget {
        case .preserveCurrent:
            break
        case .clear:
            updateScrolledID(nil)
        case .entry(let targetID):
            updateScrolledID(targetID)
        }

        return true
    }

    func prefetchImagesForDefaultBehavior<C: Collection>(_ entries: C)
    where C.Element == AnimeEntry {
        guard autoPrefetchImagesOnAddAndRestore else { return }
        LibraryImageCacheService.prefetchImages(for: entries)
    }

    private func deletionScrollTarget(for entry: AnimeEntry) -> DeletionScrollTarget {
        let entries = libraryOnDisplay
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return .preserveCurrent
        }

        if index > 0 {
            return .entry(entries[index - 1].tmdbID)
        }

        let nextIndex = index + 1
        guard nextIndex < entries.endIndex else {
            return .clear
        }
        return .entry(entries[nextIndex].tmdbID)
    }
}
