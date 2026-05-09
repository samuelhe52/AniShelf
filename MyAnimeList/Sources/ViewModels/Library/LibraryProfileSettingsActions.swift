//
//  LibraryProfileSettingsActions.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/7.
//

import Foundation
import Kingfisher

struct WhatsNewActionRunner {
    let refreshMetadata: @MainActor () -> Void
    let openURL: @MainActor (URL) -> Void

    @MainActor
    func run(_ action: WhatsNewEntry.Action.Kind) {
        switch action {
        case .refreshMetadata:
            refreshMetadata()
        case .openURL(let url):
            openURL(url)
        }
    }
}

@MainActor
final class LibraryProfileSettingsActions {
    typealias RefreshInfosHandler = @MainActor (LibraryStore) -> Void

    private let store: LibraryStore
    /// Indirection for the metadata refresh path so tests can verify routing
    /// without kicking off the full library-wide refresh work.
    private let refreshInfosHandler: RefreshInfosHandler

    init(store: LibraryStore) {
        self.store = store
        self.refreshInfosHandler = Self.performRefreshInfos
    }

    init(store: LibraryStore, refreshInfosHandler: @escaping RefreshInfosHandler) {
        self.store = store
        self.refreshInfosHandler = refreshInfosHandler
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

    /// Runs the canonical metadata refresh flow for the current library.
    /// Production uses `performRefreshInfos(for:)`; tests can inject a stub.
    func refreshInfos() {
        refreshInfosHandler(store)
    }

    /// Builds the narrow action surface used by the What's New modal.
    /// The refresh CTA deliberately reuses `refreshInfos()` so there is only
    /// one in-app metadata refresh path to maintain.
    func makeWhatsNewActionRunner(
        openURL: @escaping @MainActor (URL) -> Void
    ) -> WhatsNewActionRunner {
        WhatsNewActionRunner(
            refreshMetadata: { self.refreshInfos() },
            openURL: openURL
        )
    }

    /// Default production implementation for `refreshInfos()`.
    /// Refreshes visible library metadata and prefetches any updated images.
    private static func performRefreshInfos(for store: LibraryStore) {
        let metadataRefresher = LibraryMetadataRefresher(repository: store.repository)
        metadataRefresher.refreshInfos(
            for: store.library,
            fetcher: store.infoFetcher,
            language: store.language,
            prefetchAllImages: { entries in
                LibraryImageCacheService.prefetchImages(for: entries)
            }
        )
    }

    func clearLibrary() {
        let cachedImageURLs = Set(store.library.flatMap { LibraryImageCacheService.relatedImageURLs(for: $0) })
        do {
            try store.repository.clearLibrary()
            LibraryImageCacheService.removeCachedImages(for: cachedImageURLs)
        } catch {
            libraryStoreLogger.error("Error clearing library: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    func prefetchAllImages() {
        LibraryImageCacheService.prefetchImages(for: store.library)
    }
}
