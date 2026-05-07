//
//  LibraryProfileSettingsActions.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/7.
//

import Foundation
import Kingfisher

@MainActor
final class LibraryProfileSettingsActions {
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    func createBackup() throws -> URL {
        let backupManager = BackupManager(dataProvider: store.dataProvider)
        return try backupManager.createBackup()
    }

    func restoreBackup(from url: URL) throws {
        let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let backupManager = BackupManager(dataProvider: store.dataProvider)
        try backupManager.restoreBackup(from: url)
        store.reloadPersistedPreferences()
        try store.refreshLibrary()
        if store.autoPrefetchImagesOnAddAndRestore {
            prefetchAllImages()
        }
    }

    func metadataCacheSize() async -> Result<UInt, KingfisherError> {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                continuation.resume(returning: result)
            }
        }
    }

    func clearMetadataCache() {
        KingfisherManager.shared.cache.clearCache()
    }

    func refreshInfos() {
        let metadataRefresher = LibraryMetadataRefresher(repository: store.repository)
        let imageCacheService = LibraryImageCacheService()
        metadataRefresher.refreshInfos(
            for: store.library,
            fetcher: store.infoFetcher,
            language: store.language,
            prefetchAllImages: { [imageCacheService] entries in
                imageCacheService.prefetchImages(for: entries)
            }
        )
    }

    func clearLibrary() {
        let imageCacheService = LibraryImageCacheService()
        let cachedImageURLs = Set(store.library.flatMap { imageCacheService.relatedImageURLs(for: $0) })
        do {
            try store.repository.clearLibrary()
            imageCacheService.removeCachedImages(for: cachedImageURLs)
        } catch {
            libraryStoreLogger.error("Error clearing library: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    func prefetchAllImages() {
        let imageCacheService = LibraryImageCacheService()
        imageCacheService.prefetchImages(for: store.library)
    }
}
