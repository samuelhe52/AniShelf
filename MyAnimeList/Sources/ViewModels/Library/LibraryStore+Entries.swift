//
//  LibraryStore+Entries.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/7.
//

import DataProvider
import Foundation

extension LibraryStore {
    /// Adds an entry from TMDb. `latestInfoFetcher` replaces the TMDb fetches in tests.
    @discardableResult
    func createNewEntry(
        tmdbID id: Int,
        type: AnimeType,
        latestInfoFetcher: LibraryEntryLatestInfoFetcher? = nil
    ) async throws -> AnimeEntry? {
        let identity = LibraryEntryIdentity(entryType: type, tmdbID: id)
        if let existingEntry = repository.existingEntry(identity: identity) {
            if !existingEntry.onDisplay {
                try await hydrateExistingEntry(existingEntry, type: type)
                return existingEntry
            }
            return try revealExistingEntry(existingEntry)
        }
        libraryStoreLogger.debug("Creating new entry with id: \(id), type: \(type)...")
        let latestInfo =
            if let latestInfoFetcher {
                try await latestInfoFetcher(type, id, language)
            } else {
                try await infoFetcher.latestInfo(
                    entryType: type,
                    tmdbID: id,
                    language: language,
                    posterLanguage: posterLanguage
                )
            }
        var generatedParentSeriesEntry: AnimeEntry?
        if let parentSeriesID = type.parentSeriesID,
            repository.existingEntry(identity: .init(entryType: .series, tmdbID: parentSeriesID)) == nil
        {
            if let latestInfoFetcher {
                let parentInfo = try await latestInfoFetcher(.series, parentSeriesID, language).0
                let parentSeriesEntry = AnimeEntry(fromInfo: parentInfo)
                parentSeriesEntry.setDisplayState(false)
                generatedParentSeriesEntry = parentSeriesEntry
            } else {
                generatedParentSeriesEntry =
                    try await AnimeEntry
                    .generateParentSeriesEntryForSeason(
                        parentSeriesID: parentSeriesID,
                        fetcher: infoFetcher,
                        infoLanguage: language,
                        posterLanguage: posterLanguage)
            }
        }

        // Another window, or a second add of the same show, may have inserted the entry or its
        // parent series while this one awaited TMDb. Recheck both before inserting; nothing
        // suspends between here and the insert, so the check holds (docs-ai 028).
        if let existingEntry = repository.existingEntry(identity: identity) {
            guard !existingEntry.onDisplay else { return try revealExistingEntry(existingEntry) }
            try hydrateExistingEntry(existingEntry, from: latestInfo.0, detail: latestInfo.1)
            return existingEntry
        }
        let entry = AnimeEntry(fromInfo: latestInfo.0)
        applyNewEntryDefaults(to: entry)
        entry.replaceDetail(from: latestInfo.1)
        if let parentSeriesID = entry.parentSeriesID {
            entry.parentSeriesEntry =
                repository.existingEntry(identity: .init(entryType: .series, tmdbID: parentSeriesID))
                ?? generatedParentSeriesEntry
        }
        try repository.newEntry(entry)
        return entry
    }

    /// Refreshes one season whose parent series link is missing; the refresh relinks or inserts the
    /// series (docs-ai 033).
    ///
    /// Tries once per launch and defers to a running Refresh All, which repairs the link itself.
    func restoreMissingParentSeries(for entry: AnimeEntry) async {
        guard case .season = entry.type, entry.parentSeriesEntry == nil, !isRefreshingAllMetadata,
            parentSeriesRestoreAttemptedIDs.insert(entry.id).inserted
        else { return }
        libraryStoreLogger.info("Restoring the missing parent series of a season entry.")
        let writer = LibraryMetadataRefreshWriter(modelContainer: dataProvider.sharedModelContainer)
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled,
            applyMetadataRefresh: { updates, parentUpdates in
                try await writer.apply(updates: updates, parentUpdates: parentUpdates)
            }
        )
        await performWithDeferredLibrarySaveRefresh {
            await refresher.refreshInfos(
                for: [entry],
                fetcher: infoFetcher,
                language: language,
                posterLanguage: posterLanguage,
                options: .init(reporter: .silent, prefetchImages: false)
            )
        }
    }

    /// Shows an entry that already exists, returning `nil` because nothing new was created.
    private func revealExistingEntry(_ existingEntry: AnimeEntry) throws -> AnimeEntry? {
        existingEntry.updateDisplayState(true)
        try repository.save()
        libraryStoreLogger.warning(
            "Entry with id \(existingEntry.tmdbID) already exists in the store. Setting `onDisplay` to `true` and returning..."
        )
        return nil
    }

    func hydrateExistingEntry(_ entry: AnimeEntry, type: AnimeType) async throws {
        let tmdbID = entry.tmdbID
        let latestInfo = try await infoFetcher.latestInfo(
            entryType: entry.type,
            tmdbID: tmdbID,
            language: language,
            posterLanguage: posterLanguage
        )
        try hydrateExistingEntry(
            entry,
            from: latestInfo.0,
            detail: latestInfo.1
        )
    }

    func hydrateExistingEntry(
        _ entry: AnimeEntry,
        from info: EntryMetadata,
        detail: AnimeEntryDetailDTO
    ) throws {
        entry.replaceMetadata(from: info, preservingCustomPoster: entry.usingCustomPoster)
        entry.replaceDetail(from: detail)
        if entry.userInfo.isEmpty {
            applyNewEntryDefaults(to: entry)
        }
        entry.updateDisplayState(true)
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

    func newEntryFromEntryMetadata(_ info: EntryMetadata) {
        do {
            let entry = AnimeEntry(fromInfo: info)
            applyNewEntryDefaults(to: entry)
            try repository.newEntry(entry)
            prefetchImagesForDefaultBehavior([entry])
        } catch {
            libraryStoreLogger.error("Error creating new entry from EntryMetadata: \(error)")
        }
    }

    @discardableResult
    func deleteEntry(_ entry: AnimeEntry) -> Bool {
        let cachedImageKeys =
            entry.childSeasonEntries.isEmpty
            ? LibraryImageCacheService.relatedCacheKeys(for: entry) : []
        do {
            try repository.deleteEntry(entry)
            LibraryImageCacheService.removeCachedImages(cachedImageKeys)
            return true
        } catch {
            libraryStoreLogger.error("Failed to delete entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteEntries(_ entries: [AnimeEntry]) -> Bool {
        let selectedIDs = Set(entries.map(\.id))
        let cachedImageKeys = Set(
            entries.flatMap { entry in
                entry.childSeasonEntries.contains(where: { !selectedIDs.contains($0.id) })
                    ? [] : LibraryImageCacheService.relatedCacheKeys(for: entry)
            })
        do {
            try repository.deleteEntries(entries)
            LibraryImageCacheService.removeCachedImages(cachedImageKeys)
            return true
        } catch {
            libraryStoreLogger.error("Failed to delete entries: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    func prefetchImagesForDefaultBehavior<C: Collection>(_ entries: C)
    where C.Element == AnimeEntry {
        guard autoPrefetchImagesOnAddAndRestore else { return }
        LibraryImageCacheService.prefetchImages(
            for: entries,
            longTermGalleryPosterCachingEnabled: longTermGalleryPosterCachingEnabled
        )
    }
}
